#!/usr/bin/env Rscript
# Generate Appendix Significance Table

library(dplyr)
library(readr)
library(xtable)
library(stringr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_appendix_significance_table.r <results_dir> <output_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_dir <- args[2]

# Load p-values
pvalues_file <- file.path(results_dir, "pairwise_pvalues.csv")
if (!file.exists(pvalues_file)) {
    stop("pairwise_pvalues.csv not found in results directory.")
}

p_df <- read_csv(pvalues_file, show_col_types = FALSE)

# Clean up Model Names
p_df <- p_df %>%
    mutate(
        Model_Clean = case_when(
            grepl("gemini-3", Model) ~ "Gemini 3 Pro",
            grepl("gemini-2.5", Model) ~ "Gemini 2.5",
            grepl("gpt-5", Model) ~ "GPT-5",
            grepl("o3", Model) ~ "o3",
            grepl("claude-4.5", Model) ~ "Claude Sonnet 4.5",
            TRUE ~ Model
        ),
        # Order models
        Model_Clean = factor(Model_Clean, levels = c("Gemini 3 Pro", "Gemini 2.5", "GPT-5", "o3", "Claude Sonnet 4.5"))
    ) %>%
    arrange(Model_Clean)

# Clean up Prompt Names function
clean_prompt <- function(p) {
    case_when(
        grepl("ZeroShot", p) ~ "0-Shot",
        grepl("OneShot", p) ~ "1-Shot",
        grepl("FewShot_3", p) ~ "FS (3)",
        grepl("FewShot_ALL", p) ~ "FS (All)",
        TRUE ~ p
    )
}

p_df <- p_df %>%
    mutate(
        Comparison = paste0(clean_prompt(Prompt1), " vs. ", clean_prompt(Prompt2)),
        Diff_Fmt = sprintf("%.3f", Kappa_Diff_Observed),
        P_Value_Fmt = case_when(
            P_Value < 0.001 ~ "< .001",
            TRUE ~ sprintf("%.3f", P_Value)
        ),
        Significance = case_when(
            P_Value < 0.001 ~ "***",
            P_Value < 0.01 ~ "**",
            P_Value < 0.05 ~ "*",
            TRUE ~ "ns"
        )
    )

# Select and rename columns for table
table_df <- p_df %>%
    select(Model = Model_Clean, Comparison, Difference = Diff_Fmt, `P-Value` = P_Value_Fmt, Sig = Significance)

# Create LaTeX table
# Use longtable with specific column widths to prevent overflow
latex_lines <- c(
    "\\setlength\\tabcolsep{12pt}", # Add more space between columns
    "\\begin{longtable}{llrc}",
    "\\caption{Pairwise Significance Tests for Model Performance (Kappa). Comparison shows Prompt 1 vs Prompt 2. Difference is (Prompt 1 - Prompt 2). Significant differences ($p < .05$) are shown in bold.} \\label{tab:pairwise_significance} \\\\",
    "\\toprule",
    "\\textbf{Model} & \\textbf{Comparison} & \\textbf{Diff.} & \\textbf{$p$} \\\\",
    "\\midrule",
    "\\endfirsthead",
    "\\toprule",
    "\\textbf{Model} & \\textbf{Comparison} & \\textbf{Diff.} & \\textbf{$p$} \\\\",
    "\\midrule",
    "\\endhead",
    "\\bottomrule",
    "\\endlastfoot"
)

# Add rows
current_model <- ""
for (i in 1:nrow(table_df)) {
    row <- table_df[i, ]

    # Handle Model grouping (only print model name on first row of group)
    model_cell <- if (as.character(row$Model) != current_model) {
        current_model <- as.character(row$Model)
        paste0("\\textbf{", current_model, "}")
    } else {
        ""
    }

    # Add spacing between models
    if (i > 1 && model_cell != "") {
        latex_lines <- c(latex_lines, "\\addlinespace[0.5em]")
    }

    # Bold significant rows (p < .05)
    # The 'Sig' column has stars or ns. If it is not 'ns', it is significant.
    is_sig <- row$Sig != "ns"

    diff_val <- row$Difference
    pval_val <- row$`P-Value`

    if (is_sig) {
        diff_val <- paste0("\\textbf{", diff_val, "}")
        pval_val <- paste0("\\textbf{", pval_val, "}")
    }

    line <- sprintf(
        "%s & %s & %s & %s \\\\",
        model_cell, row$Comparison, diff_val, pval_val
    )
    latex_lines <- c(latex_lines, line)
}

latex_lines <- c(latex_lines, "\\end{longtable}")

# Write to file
output_file <- file.path(output_dir, "appendix_significance.tex")
writeLines(latex_lines, output_file)

cat("Appendix significance table saved to:", output_file, "\n")
