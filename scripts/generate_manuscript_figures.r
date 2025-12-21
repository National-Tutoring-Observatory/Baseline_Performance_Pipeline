# Manuscript Figure Generation Script
# ====================================
# Generates figures for manuscript from cached bootstrap results
# IMPORTANT: Uses pre-computed bootstrap CIs - does NOT recalculate

library(ggplot2)
library(dplyr)
library(readr)
library(tidyr)

#' Generate per-code performance figure
#'
#' @param results_dir Path to results directory
#' @param output_file Output path for figure
generate_per_code_performance_figure <- function(results_dir, output_file) {
    # Load per-code kappa with cached bootstrap CIs
    per_code <- read_csv(
        file.path(results_dir, "per_code_kappa.csv"),
        show_col_types = FALSE
    )

    # Load bootstrap CIs if available
    bootstrap_file <- file.path(results_dir, "per_code_bootstrap_cis.csv")
    if (file.exists(bootstrap_file)) {
        bootstrap_cis <- read_csv(bootstrap_file, show_col_types = FALSE)
        per_code <- left_join(per_code, bootstrap_cis,
            by = c("Model", "Prompt", "Code")
        )
    }

    # Create plot
    p <- ggplot(per_code, aes(x = Code, y = Kappa, fill = Model)) +
        geom_bar(stat = "identity", position = position_dodge(width = 0.9)) +

        # Add error bars if CIs available
        {
            if ("Kappa_lower" %in% names(per_code)) {
                geom_errorbar(
                    aes(ymin = Kappa_lower, ymax = Kappa_upper),
                    position = position_dodge(width = 0.9),
                    width = 0.2
                )
            }
        } +
        facet_wrap(~Prompt, ncol = 2) +
        theme_minimal() +
        theme(
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom"
        ) +
        labs(
            x = "Talk Move Code",
            y = "Cohen's Kappa",
            fill = "Model"
        )

    # Save
    ggsave(output_file, p, width = 10, height = 8)
    message("Generated per-code performance figure: ", output_file)
}

#' Generate prompt comparison figure
#'
#' @param results_dir Path to results directory
#' @param output_file Output path for figure
generate_prompt_comparison_figure <- function(results_dir, output_file) {
    # Load results with cached bootstrap CIs
    results <- read_csv(
        file.path(results_dir, "results.csv"),
        show_col_types = FALSE
    )

    bootstrap_file <- file.path(results_dir, "bootstrap_cis.csv")
    if (file.exists(bootstrap_file)) {
        bootstrap_cis <- read_csv(bootstrap_file, show_col_types = FALSE)
        results <- left_join(results, bootstrap_cis, by = c("Model", "Prompt"))
    }

    # Create plot
    p <- ggplot(results, aes(x = Prompt, y = Kappa, color = Model, group = Model)) +
        geom_point(size = 3) +
        geom_line() +

        # Add error bars if available
        {
            if ("Kappa_lower" %in% names(results)) {
                geom_errorbar(
                    aes(ymin = Kappa_lower, ymax = Kappa_upper),
                    width = 0.2
                )
            }
        } +
        facet_wrap(~Model, ncol = 2) +
        theme_minimal() +
        theme(
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "none"
        ) +
        labs(
            x = "Prompting Strategy",
            y = "Cohen's Kappa"
        )

    # Save
    ggsave(output_file, p, width = 10, height = 6, dpi = 300)
    message("Generated prompt comparison figure: ", output_file)
}

#' Generate all manuscript figures
#'
#' @param results_dir Path to results directory
#' @param manuscript_dir Path to manuscript directory
generate_all_figures <- function(results_dir,
                                 manuscript_dir = "documentation/Foundation_Model_Floors") {
    figures_dir <- file.path(manuscript_dir, "figures")

    # Generate per-code performance
    generate_per_code_performance_figure(
        results_dir,
        file.path(figures_dir, "per_code_performance.pdf")
    )

    # Generate prompt comparison
    generate_prompt_comparison_figure(
        results_dir,
        file.path(figures_dir, "prompt_differences_faceted_plot.png")
    )

    message("\n=== All figures generated successfully ===")
}

# If run as script
if (!interactive()) {
    args <- commandArgs(trailingOnly = TRUE)
    if (length(args) > 0) {
        generate_all_figures(args[1])
    } else {
        cat("Usage: Rscript generate_manuscript_figures.r <results_directory>\n")
    }
}
