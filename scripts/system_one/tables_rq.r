#!/usr/bin/env Rscript
# RQ1-RQ3 tables on the evaluation set (Jev next to the six LLMs)
# ===============================================================
# Transcript-clustered bootstrap: resample the 54 evaluation transcripts with replacement
# (R = 1,000). One weight matrix is shared by every model/prompt, so all differences are
# paired. Resamples saved predictions only (results/SystemOne/eval_predictions.csv).
#
# Outputs (results/SystemOne/):
#   overall_metrics.csv        accuracy, kappa, macro P/R/F1 with 95% CIs
#   per_code_metrics.csv       per-code binary kappa, P, R, F1 with 95% CIs
#   paired_prompt_tests.csv    prompt-condition differences within each model
#   paired_model_tests.csv     Jev vs each LLM within each prompt, and Jev 1.13 vs 1.14
#   confusion_matrices_jev.xlsx, figures/per_code_kappa.png, figures/confusion_jev.png
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
W <- cluster_weights(ev$Transcript, R = R_BOOT)
tx <- colnames(W)

combos <- ev %>% distinct(Prompt, Model, Family) %>% arrange(Prompt, Family, Model)
message("Bootstrapping ", nrow(combos), " model/prompt combinations (R = ", R_BOOT, ", clustered by transcript)")

boot <- list()
point <- list()
for (i in seq_len(nrow(combos))) {
    key <- paste(combos$Prompt[i], combos$Model[i], sep = "|")
    d <- ev %>% filter(Prompt == combos$Prompt[i], Model == combos$Model[i])
    tcm <- transcript_cms(d, tx)
    point[[key]] <- metric_vector(matrix(colSums(tcm), 7, 7))
    boot[[key]] <- boot_metrics(tcm, W)
}

ci <- function(key, metric) quantile(boot[[key]][, metric], c(0.025, 0.975), na.rm = TRUE)

# ------------------------------------------------------------ overall table
overall <- bind_rows(lapply(seq_len(nrow(combos)), function(i) {
    key <- paste(combos$Prompt[i], combos$Model[i], sep = "|")
    d <- ev %>% filter(Prompt == combos$Prompt[i], Model == combos$Model[i])
    parsed <- d %>% filter(!Missing)
    row <- tibble(Prompt = combos$Prompt[i], Model = combos$Model[i], Family = combos$Family[i],
                  N = nrow(d), Missing = sum(d$Missing))
    for (m in c("accuracy", "kappa", "macro_precision", "macro_recall", "macro_f1")) {
        q <- ci(key, m)
        row[[m]] <- point[[key]][[m]]
        row[[paste0(m, "_lo")]] <- q[[1]]
        row[[paste0(m, "_hi")]] <- q[[2]]
    }
    # Paper-style kappa: returned predictions only (inner join), for comparison
    row$kappa_parsed_only <- metrics_from_cm(matrix(confusion_vec(parsed$Truth, parsed$Pred), 7, 7))$kappa
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
paired <- function(key_a, key_b, metric) {
    delta <- boot[[key_a]][, metric] - boot[[key_b]][, metric]
    delta <- delta[!is.na(delta)]
    p <- 2 * min(mean(delta <= 0), mean(delta >= 0))
    tibble(metric = metric, estimate = point[[key_a]][[metric]] - point[[key_b]][[metric]],
           ci_lo = quantile(delta, 0.025), ci_hi = quantile(delta, 0.975),
           p_value = max(p, 1 / length(delta)))
}

prompt_pairs <- combn(levels(ev$Prompt), 2, simplify = FALSE)
prompt_tests <- bind_rows(lapply(unique(combos$Model), function(mod) {
    have <- as.character(combos$Prompt[combos$Model == mod])
    bind_rows(lapply(prompt_pairs, function(pp) {
        if (!all(pp %in% have)) return(NULL)
        bind_rows(lapply(c("kappa", "macro_f1"), function(m) {
            paired(paste(pp[2], mod, sep = "|"), paste(pp[1], mod, sep = "|"), m) %>%
                mutate(Model = mod, Comparison = paste(pp[2], "-", pp[1]), .before = 1)
        }))
    }))
}))
write_csv(prompt_tests, file.path(so_results_dir, "paired_prompt_tests.csv"))

model_tests <- bind_rows(lapply(levels(ev$Prompt), function(pr) {
    llms <- combos$Model[combos$Prompt == pr & combos$Family == "LLM"]
    bind_rows(lapply(llms, function(mod) {
        bind_rows(lapply(c("kappa", "macro_f1"), function(m) {
            paired(paste(pr, jev_main, sep = "|"), paste(pr, mod, sep = "|"), m) %>%
                mutate(Prompt = pr, Comparison = paste("Jev 1.14 -", mod), .before = 1)
        }))
    }))
}))
version_test <- bind_rows(lapply(c("kappa", "macro_f1"), function(m) {
    paired(paste("ZeroShot", jev_main, sep = "|"), "ZeroShot|typesafe.jev-1.13-20260917", m) %>%
        mutate(Prompt = "ZeroShot", Comparison = "Jev 1.14 - Jev 1.13", .before = 1)
}))
write_csv(bind_rows(model_tests, version_test), file.path(so_results_dir, "paired_model_tests.csv"))

# ------------------------------------------------------------ confusion matrices (Jev)
cms <- lapply(levels(ev$Prompt), function(pr) {
    d <- ev %>% filter(Prompt == pr, Model == jev_main)
    m <- matrix(confusion_vec(d$Truth, d$Pred), 7, 7, dimnames = list(move_short[move_levels], move_short[move_levels]))
    as_tibble(m, rownames = "Truth \\ Pred")
})
names(cms) <- paste0("Jev_", levels(ev$Prompt))
write_xlsx(cms, file.path(so_results_dir, "confusion_matrices_jev.xlsx"))

cm_long <- ev %>%
    filter(Model == jev_main) %>%
    count(Prompt, Truth, Pred) %>%
    complete(Prompt, Truth = move_levels, Pred = move_levels, fill = list(n = 0)) %>%
    group_by(Prompt, Truth) %>%
    mutate(row_pct = ifelse(sum(n) > 0, n / sum(n), 0)) %>%
    ungroup() %>%
    mutate(Truth = factor(move_short[Truth], levels = move_short), Pred = factor(move_short[Pred], levels = move_short))
g_cm <- ggplot(cm_long, aes(Pred, Truth, fill = row_pct)) +
    geom_tile(color = "white") +
    geom_text(aes(label = n), size = 2.6) +
    scale_fill_gradient(low = "#f7fbff", high = "#08519c", labels = scales::percent, name = "Row %") +
    scale_y_discrete(limits = rev) +
    facet_wrap(~Prompt, nrow = 1) +
    labs(title = "Jev 1.14 confusion matrices (evaluation set)", x = "Predicted", y = "Human label") +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(fig_dir, "confusion_jev.png"), g_cm, width = 14, height = 4, dpi = 200)

# ------------------------------------------------------------ per-code kappa figure
pc_plot <- per_code %>%
    filter(Code != "None", Model != "typesafe.jev-1.13-20260917") %>%
    mutate(Code_Short = factor(Code_Short, levels = move_short[-1]),
           Label = ifelse(Family == "System One", "Jev 1.14", Model))
g_pc <- ggplot(pc_plot, aes(Code_Short, binary_kappa, color = Family, group = Model)) +
    geom_pointrange(aes(ymin = binary_kappa_lo, ymax = binary_kappa_hi),
                    position = position_dodge(width = 0.7), size = 0.25) +
    scale_color_manual(values = c("LLM" = "grey55", "System One" = "#d95f02")) +
    facet_wrap(~Prompt, nrow = 1) +
    labs(title = "Per-code binary kappa, evaluation set (95% transcript-clustered CIs)",
         subtitle = "Orange = Jev 1.14; grey = the six LLMs", x = NULL, y = "Binary kappa") +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "none")
ggsave(file.path(fig_dir, "per_code_kappa.png"), g_pc, width = 14, height = 4.5, dpi = 200)

# ------------------------------------------------------------ console summary
overall %>%
    transmute(Prompt, Model, Missing,
              kappa = sprintf("%.3f [%.3f, %.3f]", kappa, kappa_lo, kappa_hi),
              macro_f1 = sprintf("%.3f [%.3f, %.3f]", macro_f1, macro_f1_lo, macro_f1_hi),
              kappa_parsed_only = round(kappa_parsed_only, 3)) %>%
    print(n = 40, width = 200)
message("\nSaved tables and figures to ", so_results_dir)
