# LLM Caller Function
# ====================
# Handles all LLM API calls

#' Call LLM API
#'
#' @param messages List of message objects with role and content
#' @param model Model identifier (e.g., "openai.gpt-5.1")
#' @param api_key API key for authentication
#' @param base_url Base URL for the API
#' @param temperature Temperature for sampling (default 0.0)
#' @param max_tokens Maximum tokens per response
#' @param timeout Request timeout in seconds
#' @return Character string with model response, or NULL on failure
call_llm <- function(messages, model, api_key, base_url,
                     temperature = 0.0, max_tokens = 4000, timeout = 300) {
    url <- paste0(base_url, "/v1/chat/completions")

    # LOG: Capture prompt variation for verification
    system_msg <- if (length(messages) > 0 && messages[[1]]$role == "system") {
        substr(messages[[1]]$content, 1, 150) # First 150 chars
    } else {
        "NO_SYSTEM_MSG"
    }
    message(sprintf("[API_CALL] Model: %s | Prompt: %s...", model, system_msg))

    body <- list(
        model = model,
        messages = messages,
        temperature = temperature,
        max_tokens = max_tokens,
        response_format = list(type = "json_object")
    )

    resp <- tryCatch(
        {
            httr::POST(
                url,
                httr::add_headers(
                    "Authorization" = paste("Bearer", api_key),
                    "Content-Type" = "application/json"
                ),
                body = jsonlite::toJSON(body, auto_unbox = TRUE),
                encode = "json",
                httr::timeout(timeout)
            )
        },
        error = function(e) {
            warning("Request Failed: ", e$message)
            return(NULL)
        }
    )

    if (is.null(resp)) {
        return(NULL)
    }

    if (httr::status_code(resp) != 200) {
        warning("API Error [", model, "]: ", httr::content(resp, "text"))
        return(NULL)
    }

    result <- httr::content(resp, "parsed")
    return(result$choices[[1]]$message$content)
}

#' Call LLM with retry logic
#'
#' @param ... Arguments passed to call_llm
#' @param max_retries Maximum number of retry attempts
#' @param retry_delay Delay between retries in seconds
#' @return Character string with model response, or NULL on failure
call_llm_with_retry <- function(..., max_retries = 3, retry_delay = 5) {
    for (attempt in 1:max_retries) {
        result <- call_llm(...)
        if (!is.null(result)) {
            return(result)
        }
        if (attempt < max_retries) {
            message("  Retry ", attempt, "/", max_retries, " in ", retry_delay, "s...")
            Sys.sleep(retry_delay)
        }
    }
    return(NULL)
}
