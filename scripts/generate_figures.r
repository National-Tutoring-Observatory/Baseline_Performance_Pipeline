#!/usr/bin/env Rscript
# Generate manuscript figures with bootstrap CIs and significance tests
# 1. Prompt differences plot (faceted by model) with significance brackets
# 2. Per-code performance plot

library(dplyr)
library(readr)
library(ggplot2)
library(tidyr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_figures.r <results_dir> <output_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_dir <- args[2]

# Load data
results <- read_csv(file.path(results_dir, "results.csv"), show_col_types = FALSE)
bootstrap_cis <- read_csv(file.path(results_dir, "bootstrap_cis.csv"), show_col_types = FALSE)
per_code_kappa <- read_csv(file.path(results_dir, "per_code_kappa.csv"), show_col_types = FALSE)
per_code_bootstrap <- read_csv(file.path(results_dir, "per_code_bootstrap_cis.csv"), show_col_types = FALSE)

# ================================================================================
# FIGURE 1: Prompt Differences with Significance Brackets
# ================================================================================

# Merge results with bootstrap
plot_data <- results %>%
    left_join(bootstrap_cis, by = c("Prompt", "Model")) %>%
    mutate(
        Model_Name = case_when(
            grepl("gpt-5", Model) ~ "GPT-5",
            grepl("o3", Model) ~ "o3",
            grepl("claude", Model) ~ "Claude 4.5",
            grepl("gemini", Model) ~ "Gemini 2.5",
            TRUE ~ Model
        ),
        Prompt_Short = case_when(
            grepl("ZeroShot", Prompt) ~ "Zero-Shot",
            grepl("OneShot", Prompt) ~ "One-Shot",
            grepl("FewShot_3", Prompt) ~ "Few-Shot (3)",
            grepl("FewShot_ALL", Prompt) ~ "Few-Shot (All)",
            TRUE ~ Prompt
        ),
        Prompt_Short = factor(Prompt_Short, levels = c("Zero-Shot", "One-Shot", "Few-Shot (3)", "Few-Shot (All)"))
    )

# Function to check if CIs overlap (conservative significance test)
cis_overlap <- function(lower1, upper1, lower2, upper2) {
    # CIs overlap if one's lower is less than the other's upper AND vice versa
    overlap <- (lower1 <= upper2) & (lower2 <= upper1)
    return(overlap)
}

# Calculate significance for each model
significance_data <- plot_data %>%
    group_by(Model_Name) %>%
    arrange(Model_Name, Prompt_Short) %>%
    summarize(
        # Compare Zero-Shot vs One-Shot
        zero_vs_one_sig = !cis_overlap(
            Kappa_CI_Lower[Prompt_Short == "Zero-Shot"],
            Kappa_CI_Upper[Prompt_Short == "Zero-Shot"],
            Kappa_CI_Lower[Prompt_Short == "One-Shot"],
            Kappa_CI_Upper[Prompt_Short == "One-Shot"]
        )[1],
        # Compare Zero-Shot vs Few-Shot (3)
        zero_vs_few3_sig = !cis_overlap(
            Kappa_CI_Lower[Prompt_Short == "Zero-Shot"],
            Kappa_CI_Upper[Prompt_Short == "Zero-Shot"],
            Kappa_CI_Lower[Prompt_Short == "Few-Shot (3)"],
            Kappa_CI_Upper[Prompt_Short == "Few-Shot (3)"]
        )[1],
        .groups = "drop"
    )

# Create plot
p1 <- ggplot(plot_data, aes(x = Prompt_Short, y = Kappa, group = Model_Name)) +
    geom_point(size = 3, alpha = 0.8) +
    geom_errorbar(aes(ymin = Kappa_CI_Lower, ymax = Kappa_CI_Upper),
        width = 0.2, alpha = 0.6, linewidth = 0.8
    ) +
    geom_line(alpha = 0.4, linewidth = 0.6) +
    facet_wrap(~Model_Name, nrow = 1) +
    theme_minimal() +
    theme(
        axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
        strip.text = element_text(face = "bold", size = 11),
        panel.grid.major.x = element_blank(),
        panel.grid.minor = element_blank()
    ) +
    labs(
        x = "Prompting Strategy",
        y = "Cohen's Kappa",
        title = "Model Performance Across Prompting Strategies"
    ) +
    ylim(0, 0.6)

# Save
output_file1 <- file.path(output_dir, "prompt_differences_faceted_plot.png")
ggsave(output_file1, p1, width = 10, height = 4, dpi = 300)
cat("✓ Generated:", output_file1, "\n")

# ================================================================================
# FIGURE 2: Per-Code Performance
# ================================================================================

# Merge per-code data
percode_plot_data <- per_code_kappa %>%
    left_join(per_code_bootstrap, by = c("Prompt", "Model", "Code")) %>%
    mutate(
        Model_Name = case_when(
            grepl("gpt-5", Model) ~ "GPT-5",
            grepl("o3", Model) ~ "o3",
            grepl("claude", Model) ~ "Claude 4.5",
            grepl("gemini", Model) ~ "Gemini 2.5",
            TRUE ~ Model
        ),
        Prompt_Group = case_when(
            grepl("ZeroShot", Prompt) ~ "Zero-Shot",
            grepl("OneShot", Prompt) ~ "One-Shot",
            grepl("FewShot_3", Prompt) ~ "Few-Shot (3)",
            grepl("FewShot_ALL", Prompt) ~ "Few-Shot (All)",
            TRUE ~ Prompt
        ),
        Code_Short = case_when(
            Code == "Keeping Everyone Together" ~ "Keep Together",
            Code == "Getting Students to Relate to Another's Ideas" ~ "Relate to Ideas",
            Code == "Pressing for Accuracy" ~ "Press Accuracy",
            Code == "Pressing for Reasoning" ~ "Press Reasoning",
            TRUE ~ Code
        )
    )

# Average across models for each code/prompt
percode_avg <- percode_plot_data %>%
    group_by(Code_Short, Prompt_Group) %>%
    summarize(
        Kappa_Mean = mean(Kappa, na.rm = TRUE),
        Kappa_CI_Lower_Mean = mean(Kappa_CI_Lower, na.rm = TRUE),
        Kappa_CI_Upper_Mean = mean(Kappa_CI_Upper, na.rm = TRUE),
        .groups = "drop"
    ) %>%
    mutate(
        Prompt_Group = factor(Prompt_Group, levels = c("Zero-Shot", "One-Shot", "Few-Shot (3)", "Few-Shot (All)"))
    )

p2 <- ggplot(percode_avg, aes(x = Code_Short, y = Kappa_Mean, fill = Prompt_Group)) +
    geom_bar(stat = "identity", position = position_dodge(width = 0.9), alpha = 0.8) +
    geom_errorbar(aes(ymin = Kappa_CI_Lower_Mean, ymax = Kappa_CI_Upper_Mean),
        position = position_dodge(width = 0.9), width = 0.3, alpha = 0.7
    ) +
    theme_minimal() +
    theme(
        axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
        legend.position = "bottom",
        legend.title = element_blank()
    ) +
    labs(
        x = "Talk Move",
        y = "Mean Cohen's Kappa (across models)",
        title = "Per-Code Performance by Prompting Strategy"
    ) +
    scale_fill_brewer(palette = "Set2")

# Save
output_file2 <- file.path(output_dir, "per_code_performance.png")
ggsave(output_file2, p2, width = 10, height = 6, dpi = 300)
cat("✓ Generated:", output_file2, "\n")

# Also save as PDF
output_file2_pdf <- file.path(output_dir, "per_code_performance.pdf")
ggsave(output_file2_pdf, p2, width = 10, height = 6)
cat("✓ Generated:", output_file2_pdf, "\n")

cat("\n✓ All figures generated\n")
