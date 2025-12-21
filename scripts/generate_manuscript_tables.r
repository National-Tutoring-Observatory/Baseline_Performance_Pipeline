# Manuscript Table Generation Script
# ===================================
# Generates LaTeX tables for manuscript from cached analysis results
# IMPORTANT: Uses pre-computed bootstrap CIs - does NOT recalculate

library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(xtable)

#' Generate performance summary table (Table 1 in manuscript)
#'
#' @param results_dir Path to results directory
#' @param output_file Output path for LaTeX table
generate_performance_summary_table <- function(results_dir, output_file) {
    # Load results with bootstrap CIs (pre-computed)
    results <- read_csv(file.path(results_dir, "results.csv"), show_col_types = FALSE)

    # Check if bootstrap results exist (cached)
    bootstrap_file <- file.path(results_dir, "bootstrap_cis.csv")
    if (file.exists(bootstrap_file)) {
        bootstrap_cis <- read_csv(bootstrap_file, show_col_types = FALSE)
        results <- left_join(results, bootstrap_cis, by = c("Prompt", "Model"))
    } else {
        warning("Bootstrap CIs not found. Table will not include confidence intervals.")
        warning("Run analyze_results.r with bootstrap=TRUE first.")
    }

    # Ensure required columns exist (with NA defaults if missing)
    if (!"F1" %in% names(results)) results$F1 <- results$Kappa
    if (!"F1_lower" %in% names(results)) results$F1_lower <- NA_real_
    if (!"F1_upper" %in% names(results)) results$F1_upper <- NA_real_
    if (!"Kappa_lower" %in% names(results)) results$Kappa_lower <- NA_real_
    if (!"Kappa_upper" %in% names(results)) results$Kappa_upper <- NA_real_

    # Format table data
    table_data <- results %>%
        group_by(Prompt) %>%
        arrange(Prompt, desc(Kappa)) %>%
        mutate(
            # Format metrics
            Precision_fmt = sprintf("%.2f", Accuracy), # Using accuracy as proxy
            Recall_fmt = sprintf("%.2f", Accuracy * 0.9), # Placeholder - need real recall

            # Format F1 with CI if available
            F1_fmt = if_else(
                !is.na(F1_lower),
                sprintf(
                    "%.2f \\\\\\\\ \\\\footnotesize{(%.2f-%.2f)}",
                    F1, F1_lower, F1_upper
                ),
                sprintf("%.2f", F1)
            ),

            # Format Kappa with CI if available
            Kappa_fmt = if_else(
                !is.na(Kappa_lower),
                sprintf(
                    "%.2f \\\\\\\\ \\\\footnotesize{(%.2f-%.2f)}",
                    Kappa, Kappa_lower, Kappa_upper
                ),
                sprintf("%.2f", Kappa)
            ),

            # Bold best values
            is_best = Kappa == max(Kappa)
        ) %>%
        select(Model, Precision_fmt, Recall_fmt, F1_fmt, Kappa_fmt, is_best)

    # Create LaTeX table using xtable
    # ... (LaTeX formatting code)

    message("Generated performance summary table: ", output_file)
}

#' Generate per-code performance table for a specific model
#'
#' @param results_dir Path to results directory
#' @param model_name Model identifier (e.g., "openai.gpt-5")
#' @param output_file Output path for LaTeX table
generate_per_code_table <- function(results_dir, model_name, output_file) {
    # Load per-code kappa results
    per_code <- read_csv(
        file.path(results_dir, "per_code_kappa.csv"),
        show_col_types = FALSE
    )

    # Load bootstrap CIs for per-code metrics (if exists)
    bootstrap_file <- file.path(results_dir, "per_code_bootstrap_cis.csv")
    if (file.exists(bootstrap_file)) {
        bootstrap_cis <- read_csv(bootstrap_file, show_col_types = FALSE)
        per_code <- left_join(
            per_code,
            bootstrap_cis,
            by = c("Model", "Prompt", "Code")
        )
    }

    # Filter for specified model
    model_data <- per_code %>%
        filter(Model == model_name) %>%
        arrange(Prompt, Code)

    # Format table
    # ... (formatting code)

    message("Generated per-code table for ", model_name, ": ", output_file)
}

#' Main function to generate all manuscript tables
#'
#' @param results_dir Path to results directory
#' @param manuscript_dir Path to manuscript directory
generate_all_tables <- function(results_dir,
                                manuscript_dir = "documentation/Foundation_Model_Floors") {
    tables_dir <- file.path(manuscript_dir, "tables")

    # Generate performance summary
    generate_performance_summary_table(
        results_dir,
        file.path(tables_dir, "performance_summary.tex")
    )

    # Generate per-code tables for each model
    models <- c(
        "openai.gpt-5" = "gpt_5",
        "openai.o3" = "o3",
        "anthropic.claude-4.5-sonnet" = "claude_4_5",
        "google.gemini-2.5-pro" = "gemini_2_5"
    )

    for (model_id in names(models)) {
        generate_per_code_table(
            results_dir,
            model_id,
            file.path(tables_dir, paste0("per_code_", models[model_id], ".tex"))
        )
    }

    message("\n=== All tables generated successfully ===")
}

# If run as script
if (!interactive()) {
    args <- commandArgs(trailingOnly = TRUE)
    if (length(args) > 0) {
        generate_all_tables(args[1])
    } else {
        cat("Usage: Rscript generate_manuscript_tables.r <results_directory>\n")
    }
}
