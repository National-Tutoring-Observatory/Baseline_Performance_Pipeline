# Prompt Builder Function
# =======================
# Constructs system prompts from prompt configuration files

#' Build system prompt from prompt configuration
#'
#' @param prompt_path Path to prompt JSON file
#' @return Character string with constructed system prompt
build_system_prompt <- function(prompt_path) {
    prompt_data <- jsonlite::fromJSON(readr::read_file(prompt_path))

    system_msg <- NULL

    # Check if system_prompt is directly provided
    if (!is.null(prompt_data$system_prompt)) {
        system_msg <- prompt_data$system_prompt
    } else {
        # Build from components
        sys_parts <- c()

        if (!is.null(prompt_data$role)) {
            sys_parts <- c(sys_parts, paste(prompt_data$role, collapse = "\n"))
        }

        if (!is.null(prompt_data$workflow)) {
            sys_parts <- c(sys_parts, "Workflow:", paste(prompt_data$workflow, collapse = "\n"))
        }

        if (!is.null(prompt_data$allowedMoves)) {
            sys_parts <- c(
                sys_parts, "Allowed Talk Moves:",
                paste("-", prompt_data$allowedMoves, collapse = "\n")
            )
        }

        if (!is.null(prompt_data$moveDefinitions)) {
            defs <- prompt_data$moveDefinitions
            def_str <- sapply(names(defs), function(n) paste0("- ", n, ": ", defs[[n]]))
            sys_parts <- c(sys_parts, "Definitions:", paste(def_str, collapse = "\n"))
        }

        # Add clarifications
        if (!is.null(prompt_data$clarifications)) {
            sys_parts <- c(
                sys_parts, "Clarifications:",
                paste("-", prompt_data$clarifications, collapse = "\n")
            )
        }

        # Add per-move examples (Fixed Bug: properly handle moveExamples)
        if (!is.null(prompt_data$moveExamples)) {
            exs <- prompt_data$moveExamples
            # Filter to only moves that exist in the map
            move_names <- names(exs)

            ex_strings <- sapply(move_names, function(m) {
                examples_list <- exs[[m]]
                if (length(examples_list) == 0) {
                    return(NULL)
                }

                # Format examples. If multiple, separate by newline or bullet?
                # Using a nested list style for clarity
                # - Move Name:
                #   * "Example 1"
                #   * "Example 2"

                formatted_exs <- paste(paste0("  * ", gsub("\n", " ", examples_list)), collapse = "\n")
                return(paste0("- ", m, ":\n", formatted_exs))
            })

            # Remove NULLs
            ex_strings <- ex_strings[!sapply(ex_strings, is.null)]

            if (length(ex_strings) > 0) {
                sys_parts <- c(sys_parts, "Examples of Talk Moves:", paste(ex_strings, collapse = "\n"))
            }
        }

        if (!is.null(prompt_data$examples)) {
            ex_json <- jsonlite::toJSON(prompt_data$examples, pretty = TRUE, auto_unbox = TRUE)
            sys_parts <- c(sys_parts, "Examples:", ex_json)
        }

        # Add required output format (CRITICAL for consistent JSON)
        if (!is.null(prompt_data$required_output)) {
            output_spec <- prompt_data$required_output
            output_section <- c("REQUIRED OUTPUT FORMAT:")
            if (!is.null(output_spec$format)) {
                output_section <- c(output_section, paste("Format:", output_spec$format))
            }
            if (!is.null(output_spec$envelope)) {
                output_section <- c(output_section, output_spec$envelope)
            }
            if (!is.null(output_spec$fields)) {
                fields_desc <- sapply(names(output_spec$fields), function(f) {
                    paste0("  - ", f, ": ", output_spec$fields[[f]])
                })
                output_section <- c(output_section, "Required fields:", fields_desc)
            }
            if (!is.null(output_spec$example)) {
                output_section <- c(
                    output_section, "Example output:",
                    jsonlite::toJSON(output_spec$example, pretty = TRUE, auto_unbox = TRUE)
                )
            }
            sys_parts <- c(sys_parts, paste(output_section, collapse = "\n"))
        }

        system_msg <- paste(sys_parts, collapse = "\n\n")
    }

    # Ensure system message exists
    if (is.null(system_msg) || length(system_msg) == 0 || system_msg == "") {
        system_msg <- "You are a helpful assistant."
    }

    # Ensure JSON output is requested
    if (!stringr::str_detect(tolower(system_msg), "json")) {
        system_msg <- paste0(system_msg, "\n\nIMPORTANT: Provide your output in JSON format.")
    }

    return(system_msg)
}

#' Build messages array for LLM call
#'
#' @param system_prompt System prompt string
#' @param user_content User content string (typically the transcript)
#' @return List of message objects
build_messages <- function(system_prompt, user_content) {
    messages <- list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = paste0("Analyze this transcript:\n", user_content))
    )
    return(messages)
}

#' Load and format transcript for LLM
#'
#' @param file_path Path to transcript JSON file
#' @return Character string with formatted transcript
load_transcript <- function(file_path) {
    transcript_json <- jsonlite::fromJSON(readr::read_file(file_path))
    utterances <- transcript_json$utterances
    input_str <- jsonlite::toJSON(utterances, dataframe = "rows", pretty = TRUE)
    return(input_str)
}
