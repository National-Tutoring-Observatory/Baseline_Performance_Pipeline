# Flexible JSON Parser
# ====================
# Handles multiple output formats from LLMs

#' Parse LLM output into standardized data frame
#'
#' Handles multiple observed output formats:
#' - Format A: {"Analysis": [...]} or {"records": [...]}
#' - Format B: {"annotations": [...]}
#' - Format C: {"ID": {"TalkMove": ...}} (ID as key)
#' - Format D: {"{}": {"analysis": [...]}} (malformed wrapper)
#' - Format E: {"{}": {"records": [...]}} (Claude malformed wrapper)
#' - Format F: [...] (raw array without wrapper)
#'
#' @param content Character string containing JSON output
#' @return Data frame with columns: ID, TalkMove, Reasoning (or NULL on failure)
parse_llm_output <- function(content) {
    tryCatch(
        {
            # Clean content
            content <- stringr::str_trim(content)
            if (nchar(content) == 0) {
                return(NULL)
            }

            # Parse JSON
            json_data <- jsonlite::fromJSON(content, simplifyDataFrame = FALSE)

            # Try different format handlers
            result <- NULL

            # Format F: Raw array (no wrapper) - check first since it's common
            if (is.list(json_data) && !is.null(json_data[[1]]) && is.list(json_data[[1]])) {
                # Check if it looks like an array of records
                first_item <- json_data[[1]]
                if (!is.null(first_item$ID) || !is.null(first_item$id) ||
                    !is.null(first_item$TalkMove) || !is.null(first_item$talkmove)) {
                    result <- parse_array_format(json_data)
                }
            }

            # Format A: records array
            if (is.null(result) && !is.null(json_data$records)) {
                result <- parse_array_format(json_data$records)
            }
            # Format A variant: Analysis array
            if (is.null(result) && !is.null(json_data$Analysis)) {
                result <- parse_array_format(json_data$Analysis)
            }
            # Format: Coding array (O3 sometimes uses this)
            if (is.null(result) && !is.null(json_data$Coding)) {
                result <- parse_array_format(json_data$Coding)
            }
            # Format: coding lowercase (O3 variant)
            if (is.null(result) && !is.null(json_data$coding)) {
                result <- parse_array_format(json_data$coding)
            }
            # Format: coded_utterances (O3 variant)
            if (is.null(result) && !is.null(json_data$coded_utterances)) {
                result <- parse_array_format(json_data$coded_utterances)
            }
            # Format B: annotations array
            if (is.null(result) && !is.null(json_data$annotations)) {
                result <- parse_array_format(json_data$annotations)
            }
            # Format: parameter wrapper (Claude variant) - array of records
            if (is.null(result) && !is.null(json_data$parameter) && is.list(json_data$parameter)) {
                # Could be array directly or contain records
                if (!is.null(json_data$parameter[[1]]$records)) {
                    result <- parse_array_format(json_data$parameter[[1]]$records)
                } else if (!is.null(json_data$parameter[[1]]$ID) || !is.null(json_data$parameter[[1]]$TalkMove)) {
                    result <- parse_array_format(json_data$parameter)
                }
            }

            # Format: Generic wrapper detection - any single key wrapping records/analysis
            if (is.null(result) && is.list(json_data) && length(json_data) == 1) {
                wrapper_key <- names(json_data)[1]
                wrapper <- json_data[[wrapper_key]]
                if (is.list(wrapper)) {
                    # Check for common array keys inside the wrapper
                    if (!is.null(wrapper$records)) {
                        result <- parse_array_format(wrapper$records)
                    } else if (!is.null(wrapper$analysis)) {
                        result <- parse_array_format(wrapper$analysis)
                    } else if (!is.null(wrapper$Analysis)) {
                        result <- parse_array_format(wrapper$Analysis)
                    } else if (!is.null(wrapper$Coding)) {
                        result <- parse_array_format(wrapper$Coding)
                    } else if (!is.null(wrapper$annotations)) {
                        result <- parse_array_format(wrapper$annotations)
                    }
                }
            }

            # Format C: ID as key {"140": {"TalkMove": ...}, "141": {...}}
            if (is.null(result) && is.list(json_data) && length(json_data) > 0) {
                # Check if keys look like IDs (numeric)
                keys <- names(json_data)
                if (!is.null(keys) && all(grepl("^\\d+$", keys))) {
                    result <- parse_dict_format(json_data)
                }
            }

            return(result)
        },
        error = function(e) {
            warning("Failed to parse LLM output: ", e$message)
            return(NULL)
        }
    )
}

#' Parse array format outputs
#'
#' @param arr List/array of annotation objects
#' @return Data frame with ID, Turn, TalkMove, Reasoning, Sentence
parse_array_format <- function(arr) {
    if (is.null(arr) || length(arr) == 0) {
        return(NULL)
    }

    # Convert list to data frame
    df <- tryCatch(
        {
            dplyr::bind_rows(lapply(arr, function(item) {
                data.frame(
                    ID = as.integer(item$ID %||% item$id %||% NA),
                    Turn = as.integer(item$Turn %||% item$turn %||% NA),
                    # Model outputs use "Transcript" for the sentence text
                    Sentence = as.character(item$Transcript %||% item$Sentence %||% item$sentence %||% ""),
                    TalkMove = as.character(item$TalkMove %||% item$talkmove %||% ""),
                    Reasoning = as.character(item$Reasoning %||% item$reasoning %||% ""),
                    stringsAsFactors = FALSE
                )
            }))
        },
        error = function(e) NULL
    )

    return(df)
}

#' Parse dictionary format outputs (ID as key)
#'
#' @param dict Named list with IDs as keys
#' @return Data frame with ID, TalkMove, Reasoning
parse_dict_format <- function(dict) {
    if (is.null(dict) || length(dict) == 0) {
        return(NULL)
    }

    df <- tryCatch(
        {
            dplyr::bind_rows(lapply(names(dict), function(id_key) {
                item <- dict[[id_key]]
                data.frame(
                    ID = as.integer(id_key),
                    Turn = NA_integer_,
                    TalkMove = as.character(item$TalkMove %||% item$talkmove %||% ""),
                    Reasoning = as.character(item$Reasoning %||% item$reasoning %||% ""),
                    stringsAsFactors = FALSE
                )
            }))
        },
        error = function(e) NULL
    )

    return(df)
}

#' Null-coalescing operator
#' @noRd
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || (is.character(x) && x == "")) y else x

#' Parse prediction file using flexible parser
#'
#' @param file_path Path to raw output file
#' @return Data frame or NULL
parse_prediction_file <- function(file_path) {
    tryCatch(
        {
            content <- readr::read_file(file_path)
            parse_llm_output(content)
        },
        error = function(e) {
            warning("Failed to read file: ", file_path)
            return(NULL)
        }
    )
}
