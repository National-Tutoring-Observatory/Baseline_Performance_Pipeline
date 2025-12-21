#!/usr/bin/env Rscript
# FloorBenchmark Pipeline Runner
# ===============================
# Main entry point for the configurable benchmark pipeline
#
# Usage:
#   Rscript scripts/run_pipeline.r                           # Use default config
#   Rscript scripts/run_pipeline.r config/my_config.yaml     # Use custom config

# Load required packages
suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(stringr)
    library(purrr)
    library(jsonlite)
    library(fs)
    library(httr)
    library(furrr)
    library(yaml)
    library(future)
})

# Source modular functions
source("scripts/functions/config_loader.r")
source("scripts/functions/llm_caller.r")
source("scripts/functions/prompt_builder.r")
source("scripts/functions/task_processor.r")
source("scripts/functions/logging.r")

# ==============================================================================
# Main Pipeline
# ==============================================================================

main <- function() {
    # Parse command line arguments
    args <- commandArgs(trailingOnly = TRUE)
    config_path <- if (length(args) > 0) args[1] else "config/pipeline_config.yaml"

    # Load configuration
    message("Loading configuration from: ", config_path)
    config <- load_config(config_path)

    # Setup logging
    log_path <- setup_logging(config)
    log_pipeline_start(config, log_path)

    # Load API credentials
    creds <- load_api_credentials()
    api_key <- creds$api_key
    base_url <- creds$base_url
    log_message("API credentials loaded", log_path)

    # Determine input directory
    input_dir <- get_input_dir(config)
    log_message(paste("Input directory:", input_dir), log_path)

    if (!dir_exists(input_dir)) {
        stop("Input directory does not exist: ", input_dir)
    }

    # Setup output directory
    output_base <- file.path(config$output_directory, config$run_name)
    if (!dir_exists(output_base)) {
        dir_create(output_base, recurse = TRUE)
    }
    log_message(paste("Output directory:", output_base), log_path)

    # Get models
    models <- config$models
    log_message(paste("Models:", length(models)), log_path)

    # Get prompts
    prompts <- get_prompts(config)
    log_message(paste("Prompts:", length(prompts)), log_path)

    # Get input files
    input_files <- dir_ls(input_dir, glob = "*.json")
    log_message(paste("Found", length(input_files), "input files"), log_path)

    # Apply test mode with optional offset
    if (config$test_mode) {
        start_offset <- if (!is.null(config$test_start_offset)) config$test_start_offset else 0
        n_test <- config$test_subset_size

        if (start_offset > 0) {
            log_message(paste("Skipping first", start_offset, "files (already processed)"), log_path)
            input_files <- input_files[(start_offset + 1):length(input_files)]
        }

        log_message(paste("TEST MODE: Using subset of", n_test, "files"), log_path)
        input_files <- head(input_files, n_test)
    }

    # Create task grid
    tasks <- create_task_grid(input_files, models, names(prompts))
    log_message(paste("Total tasks:", nrow(tasks)), log_path)

    # Run pipeline
    workers <- config$parallel_workers
    log_message(paste("Starting parallel execution with", workers, "workers"), log_path)

    start_time <- Sys.time()

    # Run tasks
    results <- run_tasks_parallel(
        tasks = tasks,
        prompts = prompts,
        output_base = output_base,
        api_key = api_key,
        base_url = base_url,
        config = config,
        workers = workers
    )

    end_time <- Sys.time()
    elapsed <- difftime(end_time, start_time, units = "mins")

    # Summarize results
    results_table <- table(results)
    log_pipeline_end(results_table, elapsed, log_path)
    print(results_table)

    # Save metadata
    metadata_path <- save_run_metadata(
        config = config,
        input_dir = input_dir,
        output_base = output_base,
        models = models,
        prompts = prompts,
        tasks = tasks,
        results_table = results_table,
        start_time = start_time,
        end_time = end_time
    )
    log_message(paste("Metadata saved to:", metadata_path), log_path)

    # Run analysis if configured
    if (config$auto_analyze) {
        log_message("Starting automated analysis...", log_path)

        analysis_script <- "scripts/analyze_results.r"
        if (file.exists(analysis_script)) {
            tryCatch(
                {
                    source(analysis_script)
                    log_message("Analysis complete", log_path)
                },
                error = function(e) {
                    log_message(paste("Analysis failed:", e$message), log_path, level = "ERROR")
                }
            )
        } else {
            log_message("Analysis script not found, skipping", log_path, level = "WARN")
        }
    }

    log_message("=== Pipeline Finished ===", log_path)

    # Return results summary
    invisible(list(
        results = results_table,
        elapsed = elapsed,
        output_dir = output_base
    ))
}

# Run main if executed directly
if (!interactive()) {
    main()
}
