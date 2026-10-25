#!/usr/bin/env Rscript
# Figures for the Jev annotation report
# =====================================
# Reads results/SystemOne/overall_metrics.csv (from tables_rq.r).
# Output: results/SystemOne/figures/overall_kappa.{png,jpg}
#
# Usage: Rscript scripts/system_one/report_figures.r

source("scripts/system_one/so_utils.r")
suppressPackageStartupMessages(library(ggplot2))

fig_dir <- file.path(so_results_dir, "figures")
model_labels <- c(
    "anthropic.claude-4.5-opus" = "Claude 4.5 Opus", "anthropic.claude-4.5-sonnet" = "Claude 4.5 Sonnet",
    "google.gemini-2.5-pro" = "Gemini 2.5 Pro", "google.gemini-3-pro-preview" = "Gemini 3 Pro",
    "openai.gpt-5" = "GPT-5", "openai.o3" = "o3", "typesafe.jev-1.14-20261014" = "Jev 1.14"
)

o <- read_csv(file.path(so_results_dir, "overall_metrics.csv"), show_col_types = FALSE) %>%
    filter(Model %in% names(model_labels)) %>%
    mutate(Prompt = factor(Prompt, levels = c("ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL")),
           Label = model_labels[Model],
           Is_Jev = Family == "System One")
# Order models by mean kappa across prompts, Jev wherever it falls
ord <- o %>% group_by(Label) %>% summarise(m = mean(kappa)) %>% arrange(m) %>% pull(Label)
o$Label <- factor(o$Label, levels = ord)

g <- ggplot(o, aes(kappa, Label, color = Is_Jev)) +
    geom_errorbarh(aes(xmin = kappa_lo, xmax = kappa_hi), height = 0, linewidth = 0.8) +
    geom_point(size = 2.6) +
    geom_text(aes(label = sprintf("%.2f", kappa)), nudge_y = 0.38, size = 3, color = "grey25") +
    scale_color_manual(values = c(`TRUE` = "#d95f02", `FALSE` = "grey55"), guide = "none") +
    facet_wrap(~Prompt, nrow = 1) +
    scale_x_continuous(limits = c(0.33, 0.62), breaks = seq(0.35, 0.60, 0.05)) +
    labs(title = "Agreement with human coders: Jev 1.14 vs. six LLMs",
         subtitle = "Cohen's kappa (7-class) on the evaluation set, 95% bootstrap CIs; Jev in orange",
         x = "Cohen's kappa", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
          strip.text = element_text(face = "bold"), plot.title = element_text(face = "bold"))
save_fig(file.path(fig_dir, "overall_kappa"), g, width = 12, height = 4)
message("Saved ", file.path(fig_dir, "overall_kappa"))
