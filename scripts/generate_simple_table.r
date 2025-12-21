#!/usr/bin/env Rscript
# Simple Performance Summary Table Generator
# Uses results.csv and bootstrap_cis.csv to create performance_summary.tex

library(dplyr)
library(readr)
library(xtable)

# Get arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_simple_table.r <results_dir> <output_file>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_file <- args[2]

# Load data
results <- read_csv(file.path(results_dir, "results.csv"), show_col_types = FALSE)
bootstrap_file <- file.path(results_dir, "bootstrap_cis.csv")

if (file.exists(bootstrap_file)) {
    bootstrap <- read_csv(bootstrap_file, show_col_types = FALSE)
    results <- results %>%
        left_join(bootstrap, by = c("Prompt", "Model"))
} else {
    results$Kappa_SE <- NA
    results$Kappa_CI_Lower <- NA
    results$Kappa_CI_Upper <- NA
}

# Create simple performance table
table_data <- results %>%
    mutate(
        Model_Short = case_when(
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
        Kappa_Formatted = if_else(
            !is.na(Kappa_CI_Lower),
            sprintf("%.3f [%.3f, %.3f]", Kappa, Kappa_CI_Lower, Kappa_CI_Upper),
            sprintf("%.3f", Kappa)
        ),
        Accuracy_Formatted = sprintf("%.1f\\%%", Accuracy * 100)
    ) %>%
    select(Model_Short, Prompt_Short, N, Accuracy_Formatted, Kappa_Formatted) %>%
    arrange(desc(Kappa_Formatted))

# Get top rows
top_table <- head(table_data, 16)

# Create LaTeX table
latex_code <- paste0(
    "\\begin{table}[htbp]\n",
    "\\centering\n",
    "\\caption{Performance Summary: Top Model/Prompt Combinations}\n",
    "\\label{tab:performance_summary}\n",
    "\\begin{tabular}{llrrr}\n",
    "\\toprule\n",
    "Model & Prompt & N & Accuracy & Kappa [95\\% CI] \\\\\n",
    "\\midrule\n"
)

for (i in 1:nrow(top_table)) {
    row <- top_table[i, ]
    latex_code <- paste0(
        latex_code,
        row$Model_Short, " & ",
        row$Prompt_Short, " & ",
        row$N, " & ",
        row$Accuracy_Formatted, " & ",
        row$Kappa_Formatted, " \\\\\n"
    )
}

latex_code <- paste0(
    latex_code,
    "\\bottomrule\n",
    "\\end{tabular}\n",
    "\\end{table}\n"
)

# Write to file
writeLines(latex_code, output_file)
cat("✓ Table saved to:", output_file, "\n")
