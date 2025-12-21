# Task Processor Function
# ========================
# Processes individual benchmark tasks

#' Process a single benchmark task
#'
#' @param file_path Path to input transcript file
#' @param prompt_name Name of the prompt
#' @param prompt_path Path to prompt JSON file
#' @param model_id Model identifier
#' @param output_base Base output directory
#' @param api_key API key for LLM
#' @param base_url Base URL for API
#' @param config Configuration list with temperature, max_tokens, etc.
#' @return Status string: "DONE", "SKIPPED", or "FAILED"
process_task <- function(file_path, prompt_name, prompt_path, model_id,
                         output_base, api_key, base_url, config) {
    # Source dependencies if not already loaded
    if (!exists("call_llm")) {
        source("scripts/functions/llm_caller.r")
    }
    if (!exists("build_system_prompt")) {
        source("scripts/functions/prompt_builder.r")
    }

    # Create output directory
    target_dir <- file.path(output_base, prompt_name, model_id)
    if (!fs::dir_exists(target_dir)) {
        fs::dir_create(target_dir, recurse = TRUE)
    }

    # Check if already processed
    file_name <- basename(file_path)
    done_path <- file.path(target_dir, paste0(file_name, "_raw.txt"))

    if (file.exists(done_path) && file.size(done_path) > 0) {
        return("SKIPPED")
    }

    # Load and format transcript
    input_str <- load_transcript(file_path)

    # Build system prompt
    system_msg <- build_system_prompt(prompt_path)

    # Build messages
    messages <- build_messages(system_msg, input_str)

    # Call LLM with retry logic for empty responses
    max_retries <- 3
    response <- NULL

    for (attempt in 1:max_retries) {
        response <- call_llm(
            messages = messages,
            model = model_id,
            api_key = api_key,
            base_url = base_url,
            temperature = config$temperature,
            max_tokens = config$max_tokens,
            timeout = config$request_timeout
        )

        # Check if we got a valid non-empty response
        if (!is.null(response) && nchar(response) > 10) {
            break
        }

        # Wait before retry
        if (attempt < max_retries) {
            Sys.sleep(2 * attempt) # Exponential backoff
        }
    }

    # Save result only if we have content
    if (!is.null(response) && nchar(response) > 10) {
        readr::write_file(response, done_path)
        return("DONE")
    } else {
        # Log the failure for debugging
        error_path <- file.path(target_dir, paste0(file_name, "_error.txt"))
        error_msg <- sprintf("Empty response after %d retries for %s", max_retries, model_id)
        readr::write_file(error_msg, error_path)
        return("FAILED")
    }
}

#' Create task grid from inputs
#'
#' @param input_files Vector of input file paths
#' @param models Vector of model identifiers
#' @param prompt_names Vector of prompt names
#' @return Data frame with all task combinations
create_task_grid <- function(input_files, models, prompt_names) {
    tasks <- expand.grid(
        file = input_files,
        model = models,
        prompt_name = prompt_names,
        stringsAsFactors = FALSE
    )
    return(tasks)
}

#' Run tasks in parallel
#'
#' @param tasks Data frame of tasks
#' @param prompts Named list of prompt paths
#' @param output_base Base output directory
#' @param api_key API key
#' @param base_url Base URL
#' @param config Configuration list
#' @param workers Number of parallel workers
#' @return Vector of status results
run_tasks_parallel <- function(tasks, prompts, output_base, api_key, base_url, config, workers) {
    # Setup parallel
    future::plan(future::multisession, workers = workers)

    # Run tasks
    results <- furrr::future_pmap(tasks, function(file, model, prompt_name) {
        p_path <- prompts[[prompt_name]]
        status <- process_task(
            file_path = file,
            prompt_name = prompt_name,
            prompt_path = p_path,
            model_id = model,
            output_base = output_base,
            api_key = api_key,
            base_url = base_url,
            config = config
        )
        return(status)
    }, .options = furrr::furrr_options(seed = TRUE))

    return(unlist(results))
}
