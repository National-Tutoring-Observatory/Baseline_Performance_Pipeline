#!/usr/bin/env Rscript
# Compute Bootstrap CIs for Analysis Results
# ===========================================
# Part of Stage 2 - runs after analyze_results.r
#
# Usage: Rscript scripts/compute_bootstrap_cis.r <results_dir>

library(dplyr)
library(readr)
library(purrr)

# Source bootstrap functions
source("scripts/functions/bootstrap_ci.r")

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
    cat("\nUsage: Rscript scripts/compute_bootstrap_cis.r <results_dir>\n")
    cat("Example: Rscript scripts/compute_bootstrap_cis.r results/stratified_467_chunks\n\n")
    quit(status = 1)
}

results_dir <- args[1]

message("╔══════════════════════════════════════════════════════════╗")
message("║  Bootstrap CI Computation                                ║")
message("╚══════════════════════════════════════════════════════════╝\n")
message("Results directory: ", results_dir, "\n")

# Check for required files
results_file <- file.path(results_dir, "results.csv")
per_code_file <- file.path(results_dir, "per_code_kappa.csv")

if (!file.exists(results_file)) {
    stop("results.csv not found in ", results_dir, "\nRun analyze_results.r first!")
}

# Cache files
bootstrap_cache_file <- file.path(results_dir, "bootstrap_cis.csv")
percode_cache_file <- file.path(results_dir, "per_code_bootstrap_cis.csv")

# Load results
results <- read_csv(results_file, show_col_types = FALSE)

# Define talk moves
move_levels <- c(
    "None", "Keeping Everyone Together",
    "Getting Students to Relate to Another's Ideas",
    "Restating", "Revoicing", "Pressing for Accuracy",
    "Pressing for Reasoning"
)

# ============================================================
# OVERALL KAPPA BOOTSTRAP
# ============================================================

if (file.exists(bootstrap_cache_file)) {
    message("✓ Found cached overall bootstrap CIs: ", bootstrap_cache_file)
    bootstrap_cis <- read_csv(bootstrap_cache_file, show_col_types = FALSE)
} else {
    message("Computing overall bootstrap CIs (R=1000 iterations per model/prompt)...")
    message("This will take ~5-10 minutes...\n")

    # Check for bootstrap_data directory
    bootstrap_data_dir <- file.path(results_dir, "bootstrap_data")
    if (!dir.exists(bootstrap_data_dir)) {
        stop(
            "Bootstrap data directory not found: ", bootstrap_data_dir,
            "\nMake sure analyze_results.r was run with the updated version that saves joined data."
        )
    }

    # Get all joined data files
    joined_files <- list.files(bootstrap_data_dir, pattern = "_joined\\.csv$", full.names = TRUE)

    if (length(joined_files) == 0) {
        stop("No joined data files found in: ", bootstrap_data_dir)
    }

    message("Found ", length(joined_files), " model/prompt combinations\n")

    # Compute bootstrap for each
    bootstrap_results_list <- lapply(joined_files, function(file_path) {
        # Parse filename to get prompt and model
        filename <- basename(file_path)
        parts <- strsplit(gsub("_joined\\.csv$", "", filename), "_")[[1]]

        # Reconstruct prompt and model names
        # Filename format: PromptName_ModelName_joined.csv
        # Need to handle multi-word names
        model_idx <- grep("\\.", parts) # Find index with dot (model ID)
        if (length(model_idx) == 0) model_idx <- length(parts)

        prompt_parts <- parts[1:(model_idx - 1)]
        model_parts <- parts[model_idx:length(parts)]

        prompt_name <- paste(prompt_parts, collapse = "_")
        model_name <- paste(model_parts, collapse = "_")

        message("  ", prompt_name, " + ", model_name)

        # Load joined data
        joined_data <- read_csv(file_path, show_col_types = FALSE)

        # Compute bootstrap CI
        ci_result <- compute_kappa_bootstrap_ci(
            data = joined_data,
            model_col = "TalkMove_Pred",
            truth_col = "TalkMove_Truth",
            move_levels = move_levels,
            R = 1000
        )

        data.frame(
            Prompt = prompt_name,
            Model = model_name,
            Kappa_SE = ci_result$se,
            Kappa_CI_Lower = ci_result$ci_lower,
            Kappa_CI_Upper = ci_result$ci_upper,
            stringsAsFactors = FALSE
        )
    })

    bootstrap_cis <- bind_rows(bootstrap_results_list)
    write_csv(bootstrap_cis, bootstrap_cache_file)
    message("\n✓ Overall bootstrap CIs saved: ", bootstrap_cache_file)
}

# ============================================================
# PER-CODE KAPPA BOOTSTRAP
# ============================================================

if (file.exists(per_code_file)) {
    if (file.exists(percode_cache_file)) {
        message("✓ Found cached per-code bootstrap CIs: ", percode_cache_file)
    } else {
        message("\nComputing per-code bootstrap CIs (R=1000 per code×model×prompt)...")
        message("This will take 20-30 minutes...")
        message(
            "(Processing ", length(move_levels), " codes × ",
            nrow(results), " model/prompt combos)\n"
        )

        bootstrap_data_dir <- file.path(results_dir, "bootstrap_data")
        joined_files <- list.files(bootstrap_data_dir, pattern = "_joined\\.csv$", full.names = TRUE)

        all_codes <- move_levels

        # Compute per-code bootstrap for each model/prompt/code
        percode_results_list <- lapply(joined_files, function(file_path) {
            filename <- basename(file_path)
            parts <- strsplit(gsub("_joined\\.csv$", "", filename), "_")[[1]]

            model_idx <- grep("\\.", parts)
            if (length(model_idx) == 0) model_idx <- length(parts)

            prompt_name <- paste(parts[1:(model_idx - 1)], collapse = "_")
            model_name <- paste(parts[model_idx:length(parts)], collapse = "_")

            message("  ", prompt_name, " + ", model_name)

            joined_data <- read_csv(file_path, show_col_types = FALSE)

            # Compute for each code
            code_results <- lapply(all_codes, function(code) {
                ci_result <- compute_percode_bootstrap_ci(
                    data = joined_data,
                    pred_col = "TalkMove_Pred",
                    truth_col = "TalkMove_Truth",
                    target_code = code,
                    R = 1000
                )

                data.frame(
                    Prompt = prompt_name,
                    Model = model_name,
                    Code = code,
                    Kappa_SE = ci_result$se,
                    Kappa_CI_Lower = ci_result$ci_lower,
                    Kappa_CI_Upper = ci_result$ci_upper,
                    stringsAsFactors = FALSE
                )
            })

            bind_rows(code_results)
        })

        per_code_bootstrap <- bind_rows(percode_results_list)
        write_csv(per_code_bootstrap, percode_cache_file)
        message("\n✓ Per-code bootstrap CIs saved: ", percode_cache_file)
    }
}

message("\n╔══════════════════════════════════════════════════════════╗")
message("║  ✓ Bootstrap computation complete                        ║")
message("╚══════════════════════════════════════════════════════════╝\n")

message("Files created:")
message("  - ", bootstrap_cache_file)
if (file.exists(percode_cache_file)) {
    message("  - ", percode_cache_file)
}

message("\nNOTE: Full bootstrap implementation requires raw prediction data.")
message("To enable, modify analyze_results.r to save joined predictions/truth.")
message("\nNext: Run update_manuscript.r to generate tables/figures\n")
