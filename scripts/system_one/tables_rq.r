#!/usr/bin/env Rscript
# RQ1-RQ3 tables on the evaluation set (Jev next to the six LLMs)
# ===============================================================
# Same inference as the paper: utterance-level bootstrap (R = 1,000, percentile CIs);
# each model is scored on the utterances it returned (Coverage reports how many);
# paired tests resample the utterances both arms returned, with the paper's p-value rule.
# Resamples saved predictions only (results/SystemOne/eval_predictions.csv).
#
# Outputs (results/SystemOne/):
#   overall_metrics.csv        accuracy, kappa, macro P/R/F1 with 95% CIs, coverage
#   per_code_metrics.csv       per-code binary kappa, P, R, F1 with 95% CIs
#   paired_prompt_tests.csv    prompt-condition differences within each model
#   paired_model_tests.csv     Jev vs each LLM within each prompt, and Jev 1.13 vs 1.14
#   confusion_matrices_jev.xlsx, figures/per_code_kappa.{png,jpg}
#
# Usage: Rscript scripts/system_one/tables_rq.r

source("scripts/system_one/so_utils.r")
suppressPackageStartupMessages({
    library(ggplot2)
    library(writexl)
})

R_BOOT <- 1000
jev_main <- "typesafe.jev-1.14-20261014"
fig_dir <- file.path(so_results_dir, "figures")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

ev <- read_csv(file.path(so_results_dir, "eval_predictions.csv"), show_col_types = FALSE) %>%
    mutate(Prompt = factor(Prompt, levels = c("ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL")))
returned <- ev %>% filter(!Missing)

combos <- ev %>% distinct(Prompt, Model, Family) %>% arrange(Prompt, Family, Model)
message("Bootstrapping ", nrow(combos), " model/prompt combinations (R = ", R_BOOT, ", utterance-level)")

boot <- list()
point <- list()
for (i in seq_len(nrow(combos))) {
    key <- paste(combos$Prompt[i], combos$Model[i], sep = "|")
    d <- returned %>% filter(Prompt == combos$Prompt[i], Model == combos$Model[i])
    point[[key]] <- metric_vector(matrix(confusion_vec(d$Truth, d$Pred), 7, 7))
    boot[[key]] <- boot_utterances(d$Truth, d$Pred, R = R_BOOT)
}

ci <- function(key, metric) quantile(boot[[key]][, metric], c(0.025, 0.975), na.rm = TRUE)

# ------------------------------------------------------------ overall table
overall <- bind_rows(lapply(seq_len(nrow(combos)), function(i) {
    key <- paste(combos$Prompt[i], combos$Model[i], sep = "|")
    d <- ev %>% filter(Prompt == combos$Prompt[i], Model == combos$Model[i])
    row <- tibble(Prompt = combos$Prompt[i], Model = combos$Model[i], Family = combos$Family[i],
                  N_Eval = nrow(d), N_Returned = sum(!d$Missing), Coverage = mean(!d$Missing))
    for (m in c("accuracy", "kappa", "macro_precision", "macro_recall", "macro_f1")) {
        q <- ci(key, m)
        row[[m]] <- point[[key]][[m]]
        row[[paste0(m, "_lo")]] <- q[[1]]
        row[[paste0(m, "_hi")]] <- q[[2]]
    }
    row
}))
write_csv(overall, file.path(so_results_dir, "overall_metrics.csv"))

# ------------------------------------------------------------ per-code table
per_code <- bind_rows(lapply(seq_len(nrow(combos)), function(i) {
    key <- paste(combos$Prompt[i], combos$Model[i], sep = "|")
    bind_rows(lapply(move_levels, function(mv) {
        row <- tibble(Prompt = combos$Prompt[i], Model = combos$Model[i], Family = combos$Family[i],
                      Code = mv, Code_Short = move_short[[mv]])
        for (m in c("bk", "prec", "rec", "f1")) {
            nm <- paste0(m, "__", mv)
            q <- ci(key, nm)
            out <- c(bk = "binary_kappa", prec = "precision", rec = "recall", f1 = "f1")[[m]]
            row[[out]] <- point[[key]][[nm]]
            row[[paste0(out, "_lo")]] <- q[[1]]
            row[[paste0(out, "_hi")]] <- q[[2]]
        }
        row
    }))
}))
write_csv(per_code, file.path(so_results_dir, "per_code_metrics.csv"))

# ------------------------------------------------------------ paired tests
# Paired on the utterances both arms returned (as the paper's inner join on ID).
paired <- function(prompt_a, model_a, prompt_b, model_b, metric) {
    a <- returned %>% filter(Prompt == prompt_a, Model == model_a) %>% select(ID, Truth, Pred_a = Pred)
    b <- returned %>% filter(Prompt == prompt_b, Model == model_b) %>% select(ID, Pred_b = Pred)
    d <- inner_join(a, b, by = "ID")
    obs <- metric_vector(matrix(confusion_vec(d$Truth, d$Pred_a), 7, 7))[[metric]] -
        metric_vector(matrix(confusion_vec(d$Truth, d$Pred_b), 7, 7))[[metric]]
    diffs <- boot_paired(d$Truth, d$Pred_a, d$Pred_b, metric, R = R_BOOT)
    tibble(metric = metric, N_Paired = nrow(d), estimate = obs,
           ci_lo = quantile(diffs, 0.025, na.rm = TRUE), ci_hi = quantile(diffs, 0.975, na.rm = TRUE),
           p_value = paper_p_value(diffs, obs))
}

prompt_pairs <- combn(levels(ev$Prompt), 2, simplify = FALSE)
prompt_tests <- bind_rows(lapply(unique(combos$Model), function(mod) {
    have <- as.character(combos$Prompt[combos$Model == mod])
    bind_rows(lapply(prompt_pairs, function(pp) {
        if (!all(pp %in% have)) return(NULL)
        bind_rows(lapply(c("kappa", "macro_f1"), function(m) {
            paired(pp[2], mod, pp[1], mod, m) %>%
                mutate(Model = mod, Comparison = paste(pp[2], "-", pp[1]), .before = 1)
        }))
    }))
}))
write_csv(prompt_tests, file.path(so_results_dir, "paired_prompt_tests.csv"))

model_tests <- bind_rows(lapply(levels(ev$Prompt), function(pr) {
    llms <- combos$Model[combos$Prompt == pr & combos$Family == "LLM"]
    bind_rows(lapply(llms, function(mod) {
        bind_rows(lapply(c("kappa", "macro_f1"), function(m) {
            paired(pr, jev_main, pr, mod, m) %>%
                mutate(Prompt = pr, Comparison = paste("Jev 1.14 -", mod), .before = 1)
        }))
    }))
}))
version_test <- bind_rows(lapply(c("kappa", "macro_f1"), function(m) {
    paired("ZeroShot", jev_main, "ZeroShot", "typesafe.jev-1.13-20260917", m) %>%
        mutate(Prompt = "ZeroShot", Comparison = "Jev 1.14 - Jev 1.13", .before = 1)
}))
write_csv(bind_rows(model_tests, version_test), file.path(so_results_dir, "paired_model_tests.csv"))

# ------------------------------------------------------------ confusion matrices (Jev)
cms <- lapply(levels(ev$Prompt), function(pr) {
    d <- returned %>% filter(Prompt == pr, Model == jev_main)
    m <- matrix(confusion_vec(d$Truth, d$Pred), 7, 7, dimnames = list(move_short[move_levels], move_short[move_levels]))
    as_tibble(m, rownames = "Truth \\ Pred")
})
names(cms) <- paste0("Jev_", levels(ev$Prompt))
write_xlsx(cms, file.path(so_results_dir, "confusion_matrices_jev.xlsx"))

# Heatmaps: scripts/system_one/confusion_heatmaps_jev.r

# ------------------------------------------------------------ per-code kappa figure
pc_plot <- per_code %>%
    filter(Code != "None", Model != "typesafe.jev-1.13-20260917") %>%
    mutate(Code_Short = factor(Code_Short, levels = move_short[-1]))
g_pc <- ggplot(pc_plot, aes(Code_Short, binary_kappa, color = Family, group = Model)) +
    geom_pointrange(aes(ymin = binary_kappa_lo, ymax = binary_kappa_hi),
                    position = position_dodge(width = 0.7), size = 0.25) +
    scale_color_manual(values = c("LLM" = "grey55", "System One" = "#d95f02")) +
    facet_wrap(~Prompt, nrow = 1) +
    labs(title = "Per-code binary kappa, evaluation set (95% bootstrap CIs)",
         subtitle = "Orange = Jev 1.14; grey = the six LLMs", x = NULL, y = "Binary kappa") +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "none")
save_fig(file.path(fig_dir, "per_code_kappa"), g_pc, width = 14, height = 4.5)

# ------------------------------------------------------------ console summary
overall %>%
    transmute(Prompt, Model, Coverage = round(Coverage, 3),
              kappa = sprintf("%.3f [%.3f, %.3f]", kappa, kappa_lo, kappa_hi),
              macro_f1 = sprintf("%.3f [%.3f, %.3f]", macro_f1, macro_f1_lo, macro_f1_hi)) %>%
    print(n = 40, width = 200)
message("\nSaved tables and figures to ", so_results_dir)
