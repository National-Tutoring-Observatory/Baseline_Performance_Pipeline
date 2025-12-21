# Manuscript Update Pipeline - Main Script
# ==========================================
# Orchestrates generation of all manuscript components from analysis results
#
# Usage: Rscript scripts/update_manuscript.r <results_directory>
# Example: Rscript scripts/update_manuscript.r results/Diagnostic_FullSample_2Combos

library(dplyr)
library(readr)

# Source component generation scripts
source("scripts/generate_manuscript_tables.r")
source("scripts/generate_manuscript_figures.r")

#' Main function to update all manuscript components
#'
#' @param results_dir Path to results directory containing analysis outputs
#' @param manuscript_dir Path to manuscript directory (default: documentation/Foundation_Model_Floors)
#' @param validate If TRUE, run validation checks on generated components
update_manuscript <- function(results_dir,
                              manuscript_dir = "documentation/Foundation_Model_Floors",
                              validate = TRUE) {
    cat("\n╔══════════════════════════════════════════════════════════╗\n")
    cat("║  Manuscript Update Pipeline                             ║\n")
    cat("╚══════════════════════════════════════════════════════════╝\n\n")

    # Verify results directory exists
    if (!dir.exists(results_dir)) {
        stop("Results directory not found: ", results_dir)
    }

    # Check for required files
    required_files <- c("results.csv", "per_code_kappa.csv", "summary.csv")
    missing_files <- required_files[!file.exists(file.path(results_dir, required_files))]

    if (length(missing_files) > 0) {
        stop("Missing required files: ", paste(missing_files, collapse = ", "))
    }

    cat("✓ Results directory validated: ", results_dir, "\n\n")

    # Check for bootstrap cache
    bootstrap_files <- c("bootstrap_cis.csv", "per_code_bootstrap_cis.csv")
    has_bootstrap <- all(file.exists(file.path(results_dir, bootstrap_files)))

    if (!has_bootstrap) {
        cat("⚠ WARNING: Bootstrap CI cache not found!\n")
        cat("  Tables and figures will be generated without confidence intervals.\n")
        cat("  To add CIs, run analyze_results.r with bootstrap=TRUE first.\n\n")
    } else {
        cat("✓ Bootstrap CI cache found\n\n")
    }

    # Generate tables
    cat("═══ GENERATING TABLES ═══\n\n")
    generate_all_tables(results_dir, manuscript_dir)
    cat("\n")

    # Generate figures
    cat("═══ GENERATING FIGURES ═══\n\n")
    generate_all_figures(results_dir, manuscript_dir)
    cat("\n")

    # Validation
    if (validate) {
        cat("═══ VALIDATION ═══\n\n")
        validate_components(manuscript_dir)
        cat("\n")
    }

    # Compile manuscript to PDF
    cat("═══ COMPILING MANUSCRIPT ═══\n\n")
    compile_manuscript(manuscript_dir)
    cat("\n")

    cat("╔══════════════════════════════════════════════════════════╗\n")
    cat("║  ✓ Manuscript updated and compiled successfully!        ║\n")
    cat("╚══════════════════════════════════════════════════════════╝\n\n")

    cat("Generated files:\n")
    cat("  - Tables: ", file.path(manuscript_dir, "tables/*.tex"), "\n")
    cat("  - Figures: ", file.path(manuscript_dir, "figures/"), "\n")
    cat("  - PDF: ", file.path(manuscript_dir, "manuscript.pdf"), "\n\n")
}

#' Compile manuscript to PDF using pdflatex
#'
#' @param manuscript_dir Path to manuscript directory
compile_manuscript <- function(manuscript_dir) {
    manuscript_file <- file.path(manuscript_dir, "manuscript.tex")

    if (!file.exists(manuscript_file)) {
        warning("manuscript.tex not found in ", manuscript_dir)
        return(FALSE)
    }

    cat("Compiling manuscript.tex to PDF...\n")
    cat("(This may take 2-3 runs for references/citations)\n\n")

    # Change to manuscript directory
    old_wd <- getwd()
    setwd(manuscript_dir)

    # Run pdflatex 3 times (for references and citations)
    for (i in 1:3) {
        cat("  Pass ", i, "/3...\n")
        result <- system2("pdflatex",
            args = c("-interaction=nonstopmode", "manuscript.tex"),
            stdout = FALSE,
            stderr = FALSE
        )

        if (result != 0 && i == 1) {
            warning("pdflatex failed on first pass - check manuscript.log for errors")
            setwd(old_wd)
            return(FALSE)
        }
    }

    setwd(old_wd)

    pdf_file <- file.path(manuscript_dir, "manuscript.pdf")
    if (file.exists(pdf_file)) {
        cat("✓ PDF generated successfully: ", pdf_file, "\n")
        return(TRUE)
    } else {
        warning("PDF not generated - check manuscript.log")
        return(FALSE)
    }
}

#' Validate generated manuscript components
#'
#' @param manuscript_dir Path to manuscript directory
validate_components <- function(manuscript_dir) {
    # Check tables
    table_files <- c(
        "performance_summary.tex",
        "per_code_claude_4_5.tex",
        "per_code_gemini_2_5.tex",
        "per_code_gpt_5.tex",
        "per_code_o3.tex"
    )

    tables_dir <- file.path(manuscript_dir, "tables")
    missing_tables <- table_files[!file.exists(file.path(tables_dir, table_files))]

    if (length(missing_tables) > 0) {
        warning("Missing table files: ", paste(missing_tables, collapse = ", "))
    } else {
        cat("✓ All 5 tables generated\n")
    }

    # Check figures
    figure_files <- c(
        "per_code_performance.pdf",
        "prompt_differences_faceted_plot.png"
    )

    figures_dir <- file.path(manuscript_dir, "figures")
    missing_figures <- figure_files[!file.exists(file.path(figures_dir, figure_files))]

    if (length(missing_figures) > 0) {
        warning("Missing figure files: ", paste(missing_figures, collapse = ", "))
    } else {
        cat("✓ All 2 figures generated\n")
    }
}

# If run as script
if (!interactive()) {
    args <- commandArgs(trailingOnly = TRUE)

    if (length(args) == 0) {
        cat("\nUsage: Rscript scripts/update_manuscript.r <results_directory> [manuscript_directory]\n\n")
        cat("Arguments:\n")
        cat("  results_directory     Path to analysis results (required)\n")
        cat("  manuscript_directory  Path to manuscript (optional, default: documentation/Foundation_Model_Floors)\n\n")
        cat("Example:\n")
        cat("  Rscript scripts/update_manuscript.r results/Diagnostic_FullSample_2Combos\n\n")
        quit(status = 1)
    }

    results_dir <- args[1]
    manuscript_dir <- if (length(args) > 1) args[2] else "documentation/Foundation_Model_Floors"

    update_manuscript(results_dir, manuscript_dir)
}
