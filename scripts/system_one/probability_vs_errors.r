#!/usr/bin/env Rscript
# How Jev's probabilities relate to its errors (evaluation set, uncalibrated)
# ==========================================================================
# Uses saved probabilities only (results/SystemOne/eval_predictions.csv); no model calls.
# Confidence = probability of the label Jev chose (top-label).
#
# Outputs (results/SystemOne/):
#   calibration_summary.csv     per prompt: ECE (equal-width, equal-mass + realized bins),
#                               smooth ECE, Brier, AUROC(conf -> correct), with clustered CIs
#   calibration_per_code.csv    one-vs-rest ECE / Brier / AUROC per code
#   reliability_bins.csv        reliability-diagram data
#   confidence_by_outcome.csv   confidence quantiles for correct vs. wrong, per true code
#   risk_coverage.csv           accuracy when keeping the top x% most confident labels,
#                               Jev vs. LLM consensus (k of 6 agreeing) as a confidence proxy
#   universal_failures_confidence.csv
#   figures/reliability_jev.png, figures/error_rate_by_confidence.png,
#   figures/risk_coverage.png, figures/reliability_per_code.png
#
# Usage: Rscript scripts/system_one/probability_vs_errors.r

source("scripts/system_one/so_utils.r")
suppressPackageStartupMessages(library(ggplot2))

R_BOOT <- 1000
jev_models <- c("typesafe.jev-1.14-20261014", "typesafe.jev-1.13-20260917")
fig_dir <- file.path(so_results_dir, "figures")
p_cols <- paste0("p_", move_levels)
prompts <- c("ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL")

ev <- read_csv(file.path(so_results_dir, "eval_predictions.csv"), show_col_types = FALSE) %>%
    mutate(Prompt = factor(Prompt, levels = prompts))
jev <- ev %>%
    filter(Model %in% jev_models) %>%
    mutate(
        Correct = Pred == Truth,
        Label = ifelse(Model == jev_models[1], paste("Jev 1.14", Prompt), "Jev 1.13 ZeroShot")
    )
# Top-label confidence: probability Jev assigned to the label it chose
P <- as.matrix(jev[, p_cols])
colnames(P) <- move_levels
jev$Conf <- P[cbind(seq_len(nrow(P)), match(jev$Pred, move_levels))]
W <- cluster_weights(ev$Transcript, R = R_BOOT)

# ------------------------------------------------------------ summary with clustered CIs
calib_stats <- function(d) {
    Pd <- as.matrix(d[, p_cols])
    colnames(Pd) <- move_levels
    em <- bins_equal_mass(d$Conf)
    c(
        accuracy = mean(d$Correct), mean_conf = mean(d$Conf),
        ece_equal_width = ece(d$Conf, d$Correct, bins_equal_width(d$Conf)),
        ece_equal_mass = ece(d$Conf, d$Correct, em),
        equal_mass_bins_realized = length(unique(em)),
        smooth_ece = smooth_ece(d$Conf, d$Correct),
        brier = brier_multiclass(Pd, d$Truth),
        auroc_conf_correct = auroc(d$Conf, d$Correct),
        share_conf_ge_0.9 = mean(d$Conf >= 0.9),
        error_rate_conf_ge_0.9 = mean(!d$Correct[d$Conf >= 0.9]),
        share_exact_zero_probs = mean(Pd == 0)
    )
}

# Clustered bootstrap: resample transcripts by expanding rows by their weights
boot_calib <- function(d, metrics = c("ece_equal_width", "smooth_ece", "brier", "auroc_conf_correct"), R = 200) {
    tx <- colnames(W)
    idx_by_tx <- split(seq_len(nrow(d)), factor(d$Transcript, levels = tx))
    reps <- t(sapply(seq_len(R), function(r) {
        rows <- unlist(rep(idx_by_tx, W[r, ]), use.names = FALSE)
        calib_stats(d[rows, ])[metrics]
    }))
    apply(reps, 2, quantile, c(0.025, 0.975))
}

groups <- jev %>% distinct(Label, Prompt, Model)
message("Calibration summary for ", nrow(groups), " Jev runs (CIs: R = 200 transcript resamples)")
summary_tbl <- bind_rows(lapply(seq_len(nrow(groups)), function(i) {
    d <- jev %>% filter(Label == groups$Label[i])
    s <- calib_stats(d)
    q <- boot_calib(d)
    row <- as_tibble(as.list(s)) %>% mutate(Label = groups$Label[i], Prompt = groups$Prompt[i], Model = groups$Model[i], N = nrow(d), .before = 1)
    for (m in colnames(q)) {
        row[[paste0(m, "_lo")]] <- q[1, m]
        row[[paste0(m, "_hi")]] <- q[2, m]
    }
    row
}))
write_csv(summary_tbl, file.path(so_results_dir, "calibration_summary.csv"))

# ------------------------------------------------------------ per-code (one-vs-rest)
per_code <- jev %>%
    group_by(Label, Prompt) %>%
    group_modify(function(d, k) {
        bind_rows(lapply(move_levels, function(mv) {
            p <- d[[paste0("p_", mv)]]
            y <- d$Truth == mv
            tibble(Code = mv, Code_Short = move_short[[mv]], Base_Rate = mean(y), Mean_P = mean(p),
                   ECE_Equal_Width = ece(p, y, bins_equal_width(p)),
                   ECE_Equal_Mass = ece(p, y, bins_equal_mass(p)),
                   Equal_Mass_Bins_Realized = length(unique(bins_equal_mass(p))),
                   Brier = mean((p - y)^2), AUROC = auroc(p, y))
        }))
    }) %>%
    ungroup()
write_csv(per_code, file.path(so_results_dir, "calibration_per_code.csv"))

# ------------------------------------------------------------ reliability bins
rel <- jev %>%
    group_by(Label, Prompt) %>%
    group_modify(function(d, k) {
        bind_rows(
            reliability_table(d$Conf, d$Correct, bins_equal_width(d$Conf)) %>% mutate(Binning = "Equal width (15)"),
            reliability_table(d$Conf, d$Correct, bins_equal_mass(d$Conf)) %>% mutate(Binning = "Equal mass (15, ties kept)")
        )
    }) %>%
    ungroup()
write_csv(rel, file.path(so_results_dir, "reliability_bins.csv"))

main_labels <- paste("Jev 1.14", prompts)
g_rel <- ggplot(rel %>% filter(Label %in% main_labels, Binning == "Equal width (15)") %>% mutate(Prompt = factor(Prompt, levels = prompts)),
                aes(mean_conf, accuracy)) +
    geom_abline(linetype = "dashed", color = "grey60") +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0, color = "#d95f02", alpha = 0.6) +
    geom_point(aes(size = n), color = "#d95f02") +
    geom_line(color = "#d95f02") +
    scale_size_area(max_size = 6, name = "Utterances") +
    coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    facet_wrap(~Prompt, nrow = 1) +
    labs(title = "Jev 1.14 reliability against human labels (evaluation set, uncalibrated)",
         subtitle = "Top-label confidence; 15 equal-width bins; bars = 95% Jeffreys intervals",
         x = "Jev confidence in its chosen label", y = "Share correct") +
    theme_minimal(base_size = 10)
ggsave(file.path(fig_dir, "reliability_jev.png"), g_rel, width = 13, height = 3.9, dpi = 200)

# ------------------------------------------------------------ confidence by outcome
by_outcome <- jev %>%
    filter(Label %in% main_labels) %>%
    mutate(Outcome = ifelse(Correct, "Correct", "Wrong")) %>%
    group_by(Prompt, Truth, Outcome) %>%
    summarise(n = n(), conf_q25 = quantile(Conf, 0.25), conf_median = median(Conf),
              conf_q75 = quantile(Conf, 0.75), share_conf_ge_0.9 = mean(Conf >= 0.9), .groups = "drop")
write_csv(by_outcome, file.path(so_results_dir, "confidence_by_outcome.csv"))

err_bins <- jev %>%
    filter(Label %in% main_labels) %>%
    mutate(Bin = cut(Conf, breaks = seq(0, 1, 0.1), include.lowest = TRUE),
           Outcome = case_when(Correct ~ "Correct",
                               Pred == "None" ~ "Wrong: missed move (pred None)",
                               Truth == "None" ~ "Wrong: false move (truth None)",
                               TRUE ~ "Wrong: wrong move"))
g_err <- ggplot(err_bins, aes(Bin, fill = Outcome)) +
    geom_bar() +
    scale_fill_manual(values = c("Correct" = "grey75", "Wrong: missed move (pred None)" = "#7570b3",
                                 "Wrong: false move (truth None)" = "#d95f02", "Wrong: wrong move" = "#1b9e77")) +
    facet_wrap(~Prompt, nrow = 1) +
    labs(title = "Jev 1.14 outcomes by confidence (evaluation set)", x = "Confidence in chosen label", y = "Utterances", fill = NULL) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 60, hjust = 1, size = 7), legend.position = "bottom")
ggsave(file.path(fig_dir, "error_rate_by_confidence.png"), g_err, width = 13, height = 4.6, dpi = 200)

# ------------------------------------------------------------ per-code reliability (one-vs-rest)
pc_rel <- jev %>%
    filter(Label %in% main_labels) %>%
    select(Prompt, Truth, all_of(p_cols)) %>%
    pivot_longer(all_of(p_cols), names_to = "Code", values_to = "p") %>%
    mutate(Code = sub("^p_", "", Code), y = Truth == Code) %>%
    group_by(Prompt, Code) %>%
    group_modify(~ reliability_table(.x$p, .x$y, bins_equal_width(.x$p))) %>%
    ungroup() %>%
    mutate(Code = factor(move_short[Code], levels = move_short), Prompt = factor(Prompt, levels = prompts))
g_pc <- ggplot(pc_rel, aes(mean_conf, accuracy, color = Prompt)) +
    geom_abline(linetype = "dashed", color = "grey60") +
    geom_point(aes(size = n), alpha = 0.7) +
    geom_line(alpha = 0.7) +
    scale_size_area(max_size = 4, guide = "none") +
    scale_color_brewer(palette = "Dark2") +
    coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    facet_wrap(~Code, nrow = 1) +
    labs(title = "Per-code reliability (one-vs-rest), Jev 1.14", x = "Jev probability for the code", y = "Share where humans gave that code") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom")
ggsave(file.path(fig_dir, "reliability_per_code.png"), g_pc, width = 15, height = 3.8, dpi = 200)

# ------------------------------------------------------------ risk-coverage vs. LLM consensus
llm_cons <- ev %>%
    filter(Family == "LLM") %>%
    group_by(Prompt, ID, Truth) %>%
    summarise(Conf = max(table(Pred)) / n(),
              Pred = names(sort(-table(factor(Pred, levels = move_levels))))[1], .groups = "drop") %>%
    mutate(Label = "LLM consensus (k of 6)")
risk_cov <- bind_rows(
    jev %>% filter(Label %in% main_labels) %>% transmute(Prompt, Source = "Jev 1.14 confidence", Conf, Correct),
    llm_cons %>% transmute(Prompt, Source = "LLM consensus (k of 6)", Conf, Correct = Pred == Truth)
) %>%
    # Evaluate only at distinct confidence thresholds: order within a tie is arbitrary
    # (half the utterances have unanimous LLM agreement), so it must not shape the curve.
    mutate(Conf = round(Conf, 6)) %>%
    group_by(Prompt, Source, Conf) %>%
    summarise(n = n(), n_correct = sum(Correct), .groups = "drop") %>%
    group_by(Prompt, Source) %>%
    arrange(desc(Conf), .by_group = TRUE) %>%
    mutate(Coverage = cumsum(n) / sum(n), Accuracy_Kept = cumsum(n_correct) / cumsum(n)) %>%
    ungroup()
write_csv(risk_cov, file.path(so_results_dir, "risk_coverage.csv"))
auroc_cmp <- bind_rows(
    jev %>% filter(Label %in% main_labels) %>% group_by(Prompt) %>% summarise(Source = "Jev 1.14 confidence", AUROC = auroc(Conf, Correct), Accuracy = mean(Correct)),
    llm_cons %>% group_by(Prompt) %>% summarise(Source = "LLM consensus (k of 6)", AUROC = auroc(Conf, Pred == Truth), Accuracy = mean(Pred == Truth))
)
write_csv(auroc_cmp, file.path(so_results_dir, "auroc_confidence_vs_consensus.csv"))
g_rc <- ggplot(risk_cov, aes(Coverage, Accuracy_Kept, color = Source)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1) +
    scale_color_manual(values = c("Jev 1.14 confidence" = "#d95f02", "LLM consensus (k of 6)" = "grey40")) +
    scale_x_continuous(labels = scales::percent) +
    scale_y_continuous(labels = scales::percent) +
    facet_wrap(~Prompt, nrow = 1) +
    labs(title = "Accuracy of the most confident labels (evaluation set)",
         subtitle = "Keep the top x% of utterances by confidence; consensus = modal LLM label, confidence = share of the 6 LLMs agreeing",
         x = "Coverage (share of utterances kept)", y = "Accuracy of kept labels", color = NULL) +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom")
ggsave(file.path(fig_dir, "risk_coverage.png"), g_rc, width = 13, height = 4.2, dpi = 200)

# ------------------------------------------------------------ universal failures
uf <- read_csv("results/Analysis/universal_failures.csv", show_col_types = FALSE) %>%
    transmute(Prompt = sub("TalkMoves_Teacher_", "", Prompt), ID = as.integer(ID), Consensus_Wrong)
uf_tbl <- jev %>%
    filter(Label %in% main_labels) %>%
    left_join(uf, by = c("Prompt", "ID")) %>%
    mutate(Group = ifelse(is.na(Consensus_Wrong), "Other utterances", "Universal failure")) %>%
    group_by(Prompt) %>%
    group_modify(function(d, k) {
        w <- wilcox.test(d$Conf[d$Group == "Universal failure"], d$Conf[d$Group == "Other utterances"])
        d %>%
            group_by(Group) %>%
            summarise(n = n(), jev_accuracy = mean(Correct), conf_median = median(Conf), conf_mean = mean(Conf), .groups = "drop") %>%
            mutate(wilcoxon_p = w$p.value)
    }) %>%
    ungroup()
write_csv(uf_tbl, file.path(so_results_dir, "universal_failures_confidence.csv"))

# ------------------------------------------------------------ console summary
summary_tbl %>%
    transmute(Label, N, accuracy = round(accuracy, 3), mean_conf = round(mean_conf, 3),
              ECE_ew = sprintf("%.3f [%.3f, %.3f]", ece_equal_width, ece_equal_width_lo, ece_equal_width_hi),
              ECE_em = sprintf("%.3f (%d bins)", ece_equal_mass, equal_mass_bins_realized),
              smECE = round(smooth_ece, 3), Brier = round(brier, 3),
              AUROC = sprintf("%.3f [%.3f, %.3f]", auroc_conf_correct, auroc_conf_correct_lo, auroc_conf_correct_hi),
              err_at_ge_0.9 = round(error_rate_conf_ge_0.9, 3), share_ge_0.9 = round(share_conf_ge_0.9, 3)) %>%
    print(width = 250)
print(auroc_cmp)
print(uf_tbl, width = 200)
message("\nSaved calibration tables and figures to ", so_results_dir)
