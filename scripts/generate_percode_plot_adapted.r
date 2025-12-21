#!/usr/bin/env Rscript
# Adapted from scripts/analysis/generate_per_code_plot.r
# Uses FloorBenchmark_Pipeline bootstrap_data and per_code_bootstrap_cis.csv

library(dplyr)
library(readr)
library(ggplot2)
library(irr)
library(tidyr)
library(stringr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_percode_plot_adapted.r <results_dir> <output_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_dir <- args[2]

# Load per-code kappa and bootstrap CIs
per_code_kappa <- read_csv(file.path(results_dir, "per_code_kappa.csv"), show_col_types = FALSE)
per_code_bootstrap <- read_csv(file.path(results_dir, "per_code_bootstrap_cis.csv"), show_col_types = FALSE)

# Merge and filter out problematic rows
all_data <- per_code_kappa %>%
    filter(N_Truth > 0) %>% # Filter out codes with 0 ground truth
    left_join(per_code_bootstrap, by = c("Prompt", "Model", "Code")) %>%
    filter(!is.na(Kappa_CI_Lower)) %>% # Remove rows without CIs
    mutate(
        ModelLabel = case_when(
            grepl("gemini-3", Model) ~ "Gemini 3 Pro",
            grepl("gemini-2.5", Model) ~ "Gemini 2.5",
            grepl("gpt-5", Model) ~ "GPT-5",
            grepl("o3", Model) ~ "o3",
            grepl("claude-4.5-sonnet", Model) ~ "Claude Sonnet 4.5",
            grepl("claude-4.5-opus", Model) ~ "Claude Opus 4.5",
            TRUE ~ Model
        ),
        # Set model order
        ModelLabel = factor(ModelLabel, levels = c("Gemini 3 Pro", "Claude Opus 4.5", "Claude Sonnet 4.5", "Gemini 2.5", "GPT-5", "o3")),
        CodeLabel = case_when(
            Code == "Keeping Everyone Together" ~ "Keep Together",
            Code == "Getting Students to Relate to Another's Ideas" ~ "Relate to Ideas",
            Code == "Pressing for Accuracy" ~ "Press Accuracy",
            Code == "Pressing for Reasoning" ~ "Press Reasoning",
            Code == "None" ~ "None",
            TRUE ~ Code
        ),
        Prompt_Factor = case_when(
            grepl("ZeroShot", Prompt) ~ "ZeroShot",
            grepl("OneShot", Prompt) ~ "One Shot",
            grepl("FewShot_3", Prompt) ~ "FewShot3",
            grepl("FewShot_ALL", Prompt) ~ "FewShot",
            TRUE ~ "ZeroShot"
        ),
        Prompt_Factor = factor(Prompt_Factor, levels = c("ZeroShot", "OneShot", "FewShot3", "FewShot"))
    )

# Aggregate Data for Bars (Means only)
agg_data <- all_data %>%
    group_by(Prompt_Factor, CodeLabel) %>%
    summarise(
        Mean_Kappa = mean(Kappa, na.rm = TRUE),
        .groups = "drop"
    )

# Order Codes
agg_data$CodeLabel <- factor(agg_data$CodeLabel, levels = c(
    "Keep Together", "Relate to Ideas", "Restating", "Revoicing",
    "Press Accuracy", "Press Reasoning", "None"
))
all_data$CodeLabel <- factor(all_data$CodeLabel, levels = levels(agg_data$CodeLabel))

# Position object for jittering
pos <- position_jitterdodge(jitter.width = 0.2, dodge.width = 0.8)

# Plotting with increased font sizes
p <- ggplot() +
    # Bars (Mean)
    geom_bar(
        data = agg_data,
        aes(x = CodeLabel, y = Mean_Kappa, fill = Prompt_Factor),
        stat = "identity",
        position = position_dodge(width = 0.8),
        alpha = 0.3, # Lighter bars to emphasize points
        width = 0.7
    ) +
    # Points with Error Bars (Individual Models)
    geom_pointrange(
        data = all_data,
        aes(
            x = CodeLabel,
            y = Kappa,
            ymin = Kappa_CI_Lower,
            ymax = Kappa_CI_Upper,
            shape = ModelLabel,
            group = Prompt_Factor,
            color = Prompt_Factor,
            fill = Prompt_Factor
        ),
        position = pos,
        size = 0.6,
        fatten = 4,
        alpha = 0.7
    ) +
    # Reference Lines
    geom_hline(yintercept = 0.4, linetype = "dashed", color = "#999999", alpha = 0.5) +
    geom_hline(yintercept = 0.6, linetype = "dashed", color = "#999999", alpha = 0.5) +
    annotate("text", x = 0.5, y = 0.41, label = "Moderate (>=0.40)", hjust = 0, vjust = 0, size = 4, color = "#666666") +
    annotate("text", x = 0.5, y = 0.61, label = "Substantial (>=0.60)", hjust = 0, vjust = 0, size = 4, color = "#666666") +
    # Scales
    scale_fill_manual(values = c(
        "ZeroShot" = "#D55E00",
        "OneShot" = "#0072B2",
        "FewShot3" = "#009E73",
        "FewShot" = "#CC79A7"
    ), labels = c("Zero Shot", "One Shot", "Few Shot (3)", "Few Shot (All)")) +
    scale_color_manual(values = c(
        "ZeroShot" = "#D55E00",
        "OneShot" = "#0072B2",
        "FewShot3" = "#009E73",
        "FewShot" = "#CC79A7"
    ), labels = c("Zero Shot", "One Shot", "Few Shot (3)", "Few Shot (All)")) +
    scale_shape_manual(values = c(
        "Gemini 3 Pro" = 2, # Open Triangle (Point Up)
        "Claude Opus 4.5" = 0, # Open Square
        "Claude Sonnet 4.5" = 1, # Open Circle
        "Gemini 2.5" = 5, # Open Diamond
        "GPT-5" = 6, # Open Triangle (Point Down)
        "o3" = 3 # Plus / Cross
    )) +
    # Labels and Theme
    labs(
        title = "Per-Code Performance: Average and Individual Models",
        subtitle = "Bars show mean kappa; Points show individual model kappa with 95% CIs",
        x = NULL,
        y = "Cohen's Kappa",
        fill = "Prompt Strategy",
        shape = "Model",
        color = "Prompt Strategy"
    ) +
    theme_minimal(base_size = 16, base_family = "serif") +
    theme(
        legend.position = "top",
        legend.box = "vertical",
        legend.box.just = "left",
        axis.text.x = element_text(angle = 45, hjust = 1, size = 14),
        axis.text.y = element_text(size = 14),
        axis.title = element_text(size = 16, face = "bold"),
        legend.text = element_text(size = 14),
        legend.title = element_text(size = 14, face = "bold"),
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank(),
        plot.title = element_text(hjust = 0.5, face = "bold", size = 18),
        plot.subtitle = element_text(hjust = 0.5, color = "#666666", size = 14)
    ) +
    coord_cartesian(ylim = c(0, 0.8))

# Save
ggsave(
    file.path(output_dir, "per_code_performance.pdf"),
    p,
    width = 12,
    height = 10,
    device = cairo_pdf
)

ggsave(
    file.path(output_dir, "per_code_performance.png"),
    p,
    width = 12,
    height = 8,
    dpi = 300
)

message("Per-code performance plot saved to: ", output_dir)
