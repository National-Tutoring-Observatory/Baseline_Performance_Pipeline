#!/usr/bin/env Rscript
# Generate Per-Code Tables (one per model)
# Format matches Foundation_Model_Floors/tables/per_code_*.tex

library(dplyr)
library(readr)
library(tidyr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_percode_tables.r <results_dir> <output_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_dir <- args[2]

# Load data
per_code_kappa <- read_csv(file.path(results_dir, "per_code_kappa.csv"), show_col_types = FALSE)
per_code_bootstrap <- read_csv(file.path(results_dir, "per_code_bootstrap_cis.csv"), show_col_types = FALSE)

# Merge
per_code_full <- per_code_kappa %>%
    left_join(per_code_bootstrap, by = c("Prompt", "Model", "Code"))

# Model mappings
model_mapping <- c(
    "openai.gpt-5" = "gpt_5",
    "openai.o3" = "o3",
    "anthropic.claude-4.5-sonnet" = "claude_4_5",
    "google.gemini-2.5-pro" = "gemini_2_5"
)

model_names <- c(
    "openai.gpt-5" = "GPT-5",
    "openai.o3" = "o3",
    "anthropic.claude-4.5-sonnet" = "Claude 4.5 Sonnet",
    "google.gemini-2.5-pro" = "Gemini 2.5 Pro"
)

# Generate table for each model
for (model_id in names(model_mapping)) {
    model_file <- model_mapping[model_id]
    model_name <- model_names[model_id]

    # Filter data
    model_data <- per_code_full %>%
        filter(Model == model_id) %>%
        mutate(
            Prompt_Group = case_when(
                grepl("ZeroShot", Prompt) ~ "Zero Shot",
                grepl("OneShot", Prompt) ~ "One Shot",
                grepl("FewShot_3", Prompt) ~ "Few Shot (3)",
                grepl("FewShot_ALL", Prompt) ~ "Few Shot (All)",
                TRUE ~ Prompt
            )
        ) %>%
        select(Prompt_Group, Code, Kappa, Kappa_CI_Lower, Kappa_CI_Upper) %>%
        arrange(Prompt_Group, Code)

    if (nrow(model_data) == 0) next

    # Start LaTeX
    latex_lines <- c(
        sprintf("%% Per-code table for %s", model_name),
        sprintf("%% Generated: %s", Sys.time()),
        "\\begin{table}[H]",
        "\\centering",
        sprintf("\\caption{Per-Code Performance: %s}", model_name),
        sprintf("\\label{tab:percode_%s}", model_file),
        "\\begin{tabular}{p{5cm}cccc}",
        "  \\toprule",
        "Talk Move & Zero Shot & One Shot & Few Shot (3) & Few Shot (All) \\\\",
        "  \\midrule"
    )

    # Get unique codes
    codes <- unique(model_data$Code)

    # For each code, create a row
    for (code in codes) {
        code_data <- model_data %>% filter(Code == !!code)

        # Get kappa for each prompt
        prompts <- c("Zero Shot", "One Shot", "Few Shot (3)", "Few Shot (All)")
        values <- sapply(prompts, function(p) {
            row <- code_data %>% filter(Prompt_Group == p)
            if (nrow(row) == 0) {
                return("---")
            }
            if (!is.na(row$Kappa_CI_Lower[1])) {
                sprintf(
                    "\\begin{tabular}[c]{@{}c@{}}%.2f \\\\\\\\ \\footnotesize{(%.2f-%.2f)} \\end{tabular}",
                    row$Kappa[1], row$Kappa_CI_Lower[1], row$Kappa_CI_Upper[1]
                )
            } else {
                sprintf("%.2f", row$Kappa[1])
            }
        })

        line <- sprintf(
            "%s & %s & %s & %s & %s \\\\",
            code, values[1], values[2], values[3], values[4]
        )
        latex_lines <- c(latex_lines, line)
    }

    latex_lines <- c(
        latex_lines,
        "  \\bottomrule",
        "\\end{tabular}",
        "\\end{table}"
    )

    # Write file
    output_file <- file.path(output_dir, paste0("per_code_", model_file, ".tex"))
    writeLines(latex_lines, output_file)
    cat("✓ Generated:", output_file, "\n")
}

cat("\n✓ All per-code tables generated\n")
