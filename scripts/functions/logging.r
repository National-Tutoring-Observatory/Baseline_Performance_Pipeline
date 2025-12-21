# Logging Utilities
# =================
# Handles logging for the pipeline

#' Setup logging
#'
#' @param config Configuration list
#' @return Path to log file, or NULL if logging disabled
setup_logging <- function(config) {
    if (!config$verbose_logging) {
        return(NULL)
    }

    log_file <- config$log_file
    log_dir <- dirname(log_file)

    if (!fs::dir_exists(log_dir)) {
        fs::dir_create(log_dir, recurse = TRUE)
    }

    # Create log file with timestamp
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    log_path <- stringr::str_replace(log_file, "\\.log$", paste0("_", timestamp, ".log"))

    return(log_path)
}

#' Log a message
#'
#' @param msg Message to log
#' @param log_path Path to log file (optional)
#' @param level Log level: "INFO", "WARN", "ERROR"
log_message <- function(msg, log_path = NULL, level = "INFO") {
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    formatted_msg <- paste0("[", timestamp, "] [", level, "] ", msg)

    message(formatted_msg)

    if (!is.null(log_path)) {
        write(formatted_msg, file = log_path, append = TRUE)
    }
}

#' Log pipeline start
#'
#' @param config Configuration list
#' @param log_path Path to log file
log_pipeline_start <- function(config, log_path = NULL) {
    log_message("=== FloorBenchmark Pipeline Started ===", log_path)
    log_message(paste("Sample Type:", config$sample_type), log_path)
    log_message(paste("Run Name:", config$run_name), log_path)
    log_message(paste("Models:", paste(config$models, collapse = ", ")), log_path)
    log_message(paste("Test Mode:", config$test_mode), log_path)
}

#' Log pipeline end
#'
#' @param results_table Table of results
#' @param elapsed Elapsed time
#' @param log_path Path to log file
log_pipeline_end <- function(results_table, elapsed, log_path = NULL) {
    log_message("=== Pipeline Complete ===", log_path)
    log_message(paste("Elapsed time:", round(elapsed, 2), "minutes"), log_path)
    log_message("Results summary:", log_path)

    if (!is.null(log_path)) {
        capture.output(print(results_table), file = log_path, append = TRUE)
    }
}

#' Save run metadata
#'
#' @param config Configuration list
#' @param input_dir Input directory used
#' @param output_base Output directory
#' @param models Models used
#' @param prompts Prompts used
#' @param tasks Total tasks
#' @param results_table Results summary
#' @param start_time Start time
#' @param end_time End time
save_run_metadata <- function(config, input_dir, output_base, models, prompts,
                              tasks, results_table, start_time, end_time) {
    elapsed <- difftime(end_time, start_time, units = "mins")

    metadata <- list(
        run_name = config$run_name,
        sample_type = config$sample_type,
        input_directory = input_dir,
        output_directory = output_base,
        models = models,
        prompts = names(prompts),
        total_tasks = nrow(tasks),
        results = as.list(results_table),
        start_time = as.character(start_time),
        end_time = as.character(end_time),
        elapsed_minutes = as.numeric(elapsed),
        config = config
    )

    metadata_path <- file.path(output_base, "run_metadata.json")
    jsonlite::write_json(metadata, metadata_path, pretty = TRUE)

    return(metadata_path)
}
