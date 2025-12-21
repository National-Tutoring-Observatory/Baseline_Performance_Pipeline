# Bootstrap CI Calculation Module
# ================================
# Calculates bootstrap confidence intervals ONCE and caches results
# To be integrated into analyze_results.r

library(boot)

#' Calculate bootstrap confidence interval for a metric
#'
#' @param data Data frame with predictions and truth
#' @param metric_fn Function to calculate metric (e.g., kappa, F1)
#' @param n_boot Number of bootstrap samples (default 1000)
#' @param conf_level Confidence level (default 0.95)
#' @return List with estimate, lower, upper
bootstrap_ci <- function(data, metric_fn, n_boot = 1000, conf_level = 0.95) {
    # Bootstrap function
    boot_fn <- function(data, indices) {
        boot_data <- data[indices, ]
        metric_fn(boot_data$pred, boot_data$truth)
    }

    # Run bootstrap
    boot_results <- boot(
        data = data,
        statistic = boot_fn,
        R = n_boot
    )

    # Get CI
    ci <- boot.ci(boot_results, conf = conf_level, type = "perc")

    list(
        estimate = boot_results$t0,
        lower = ci$percent[4],
        upper = ci$percent[5]
    )
}

#' Calculate and cache bootstrap CIs for all metrics
#'
#' @param results_data Data frame with predictions/truth for each model/prompt
#' @param output_dir Directory to save cached results
#' @param force_recalculate If TRUE, recalculate even if cache exists
calculate_and_cache_bootstrap <- function(results_data, output_dir,
                                          force_recalculate = FALSE) {
    cache_file <- file.path(output_dir, "bootstrap_cis.csv")

    # Check cache
    if (file.exists(cache_file) && !force_recalculate) {
        message("Loading cached bootstrap CIs from: ", cache_file)
        return(read_csv(cache_file, show_col_types = FALSE))
    }

    message("Calculating bootstrap CIs (this may take several minutes)...")

    # Calculate CIs for each model/prompt combination
    bootstrap_results <- results_data %>%
        group_by(Model, Prompt) %>%
        group_modify(~ {
            data.frame(
                Kappa_lower = bootstrap_ci(.x, kappa_fn)$lower,
                Kappa_upper = bootstrap_ci(.x, kappa_fn)$upper,
                F1_lower = bootstrap_ci(.x, f1_fn)$lower,
                F1_upper = bootstrap_ci(.x, f1_fn)$upper
            )
        }) %>%
        ungroup()

    # Save to cache
    write_csv(bootstrap_results, cache_file)
    message("Bootstrap CIs cached to: ", cache_file)

    return(bootstrap_results)
}

#' Calculate per-code bootstrap CIs and cache
#'
#' @param per_code_data Data frame with per-code predictions/truth
#' @param output_dir Directory to save cached results
#' @param force_recalculate If TRUE, recalculate even if cache exists
calculate_and_cache_percode_bootstrap <- function(per_code_data, output_dir,
                                                  force_recalculate = FALSE) {
    cache_file <- file.path(output_dir, "per_code_bootstrap_cis.csv")

    # Check cache
    if (file.exists(cache_file) && !force_recalculate) {
        message("Loading cached per-code bootstrap CIs from: ", cache_file)
        return(read_csv(cache_file, show_col_types = FALSE))
    }

    message("Calculating per-code bootstrap CIs (this will take a while)...")

    # Calculate CIs for each model/prompt/code combination
    bootstrap_results <- per_code_data %>%
        group_by(Model, Prompt, Code) %>%
        group_modify(~ {
            data.frame(
                Kappa_lower = bootstrap_ci(.x, kappa_fn)$lower,
                Kappa_upper = bootstrap_ci(.x, kappa_fn)$upper
            )
        }) %>%
        ungroup()

    # Save to cache
    write_csv(bootstrap_results, cache_file)
    message("Per-code bootstrap CIs cached to: ", cache_file)

    return(bootstrap_results)
}
