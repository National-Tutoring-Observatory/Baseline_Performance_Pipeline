# Configuration Loader
# ====================
# Handles loading and validating pipeline configuration

#' Load pipeline configuration from YAML file
#'
#' @param config_path Path to YAML configuration file
#' @return Configuration list
load_config <- function(config_path = "config/pipeline_config.yaml") {
    if (!file.exists(config_path)) {
        stop("Configuration file not found: ", config_path)
    }

    config <- yaml::read_yaml(config_path)
    config <- validate_config(config)

    return(config)
}

#' Validate configuration and set defaults
#'
#' @param config Configuration list
#' @return Validated configuration list with defaults applied
validate_config <- function(config) {
    # Set defaults for missing values
    defaults <- list(
        sample_type = "stratified_sample",
        run_name = paste0("FloorBenchmark_", format(Sys.time(), "%Y%m%d_%H%M%S")),
        output_directory = "data/outputs",
        prompt_directory = "prompts",
        parallel_workers = 10,
        temperature = 0.0,
        max_tokens = 4000,
        request_timeout = 300,
        test_mode = FALSE,
        test_subset_size = 10,
        auto_analyze = TRUE,
        verbose_logging = TRUE,
        log_file = "logs/pipeline.log"
    )

    # Apply defaults for missing values
    for (key in names(defaults)) {
        if (is.null(config[[key]])) {
            config[[key]] <- defaults[[key]]
        }
    }

    return(config)
}

#' Get input directory based on sample type
#'
#' @param config Configuration list
#' @return Path to input directory
get_input_dir <- function(config) {
    sample_type <- config$sample_type

    if (sample_type == "custom") {
        if (is.null(config$custom_sample_path)) {
            stop("custom_sample_path must be specified when sample_type is 'custom'")
        }
        return(config$custom_sample_path)
    } else if (sample_type %in% names(config$sample_paths)) {
        return(config$sample_paths[[sample_type]])
    } else {
        stop(
            "Invalid sample_type: ", sample_type,
            ". Valid options: ", paste(names(config$sample_paths), collapse = ", "), ", custom"
        )
    }
}

#' Load API credentials from environment
#'
#' @param env_paths Vector of paths to check for .env file
#' @return List with api_key and base_url
load_api_credentials <- function(env_paths = c(".env", "../.env")) {
    # Try to load .env file
    for (env_path in env_paths) {
        if (file.exists(env_path)) {
            readRenviron(env_path)
            break
        }
    }

    api_key <- Sys.getenv("AI_GATEWAY_KEY")
    base_url <- Sys.getenv("AI_GATEWAY_BASE_URL")

    if (api_key == "" || base_url == "") {
        stop("AI_GATEWAY_KEY and AI_GATEWAY_BASE_URL must be set in .env file or environment")
    }

    return(list(api_key = api_key, base_url = base_url))
}

#' Get prompts based on configuration
#'
#' @param config Configuration list
#' @return Named list of prompt paths
get_prompts <- function(config) {
    prompt_dir <- config$prompt_directory

    if (!fs::dir_exists(prompt_dir)) {
        stop("Prompt directory does not exist: ", prompt_dir)
    }

    if (length(config$specific_prompts) > 0 && !is.null(config$specific_prompts[[1]])) {
        # Use specific prompts
        prompt_files <- file.path(prompt_dir, config$specific_prompts)
        # Check they exist
        missing <- prompt_files[!file.exists(prompt_files)]
        if (length(missing) > 0) {
            warning("Some specified prompts not found: ", paste(missing, collapse = ", "))
            prompt_files <- prompt_files[file.exists(prompt_files)]
        }
    } else {
        # Use all prompts in directory
        prompt_files <- fs::dir_ls(prompt_dir, glob = "*.json")
    }

    if (length(prompt_files) == 0) {
        stop("No prompt files found in: ", prompt_dir)
    }

    prompts <- stats::setNames(prompt_files, fs::path_ext_remove(fs::path_file(prompt_files)))
    return(prompts)
}
