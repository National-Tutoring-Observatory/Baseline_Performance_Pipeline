# Bootstrap Confidence Interval Functions
# =========================================
# Compute bootstrap CIs for Kappa values
# Ported from scripts/analysis/ to make pipeline self-contained

library(irr)
library(boot)
library(dplyr)

# ============================================================
# OVERALL KAPPA BOOTSTRAP
# ============================================================

#' Bootstrap function for overall kappa
#' @param data Data frame with predictions and truth
#' @param indices Bootstrap sample indices
#' @param model_col Name of model prediction column
#' @param truth_col Name of ground truth column
#' @param move_levels Factor levels for talk moves
boot_kappa <- function(data, indices, model_col, truth_col, move_levels) {
    d <- data[indices, ]

    df_sub <- d %>%
        select(truth = !!sym(truth_col), pred = !!sym(model_col)) %>%
        filter(!is.na(truth), !is.na(pred)) %>%
        mutate(
            truth = factor(as.character(truth), levels = move_levels),
            pred = factor(as.character(pred), levels = move_levels)
        )

    if (nrow(df_sub) < 2) {
        return(NA_real_)
    }

    tryCatch(
        irr::kappa2(df_sub, weight = "unweighted")$value,
        error = function(e) NA_real_
    )
}

#' Compute bootstrap CI for kappa
#' @param data Data frame with predictions and truth
#' @param model_col Model prediction column name
#' @param truth_col Ground truth column name
#' @param move_levels Factor levels for moves
#' @param R Number of bootstrap iterations (default 1000)
#' @return List with se, ci_lower, ci_upper
compute_kappa_bootstrap_ci <- function(data, model_col, truth_col, move_levels, R = 1000) {
    boot_result <- tryCatch(
        {
            boot(
                data = data,
                statistic = boot_kappa,
                R = R,
                model_col = model_col,
                truth_col = truth_col,
                move_levels = move_levels
            )
        },
        error = function(e) NULL
    )

    if (is.null(boot_result) || all(is.na(boot_result$t))) {
        return(list(se = NA_real_, ci_lower = NA_real_, ci_upper = NA_real_))
    }

    ci <- tryCatch(
        {
            boot.ci(boot_result, type = "perc")
        },
        error = function(e) NULL
    )

    list(
        se = sd(boot_result$t, na.rm = TRUE),
        ci_lower = if (!is.null(ci)) ci$percent[4] else NA_real_,
        ci_upper = if (!is.null(ci)) ci$percent[5] else NA_real_
    )
}

# ============================================================
# PER-CODE KAPPA BOOTSTRAP
# ============================================================

#' Bootstrap function for binary kappa (one code vs all others)
#' @param data Data frame
#' @param indices Bootstrap indices
#' @param pred_col Prediction column
#' @param truth_col Truth column
#' @param target_code Code to test (binary: this code vs all others)
boot_binary_kappa <- function(data, indices, pred_col, truth_col, target_code) {
    d <- data[indices, ]

    # Create binary coding
    df_binary <- d %>%
        select(pred = !!sym(pred_col), truth = !!sym(truth_col)) %>%
        filter(!is.na(pred), !is.na(truth)) %>%
        mutate(
            pred_binary = factor(ifelse(pred == target_code, "Yes", "No"), levels = c("No", "Yes")),
            truth_binary = factor(ifelse(truth == target_code, "Yes", "No"), levels = c("No", "Yes"))
        ) %>%
        select(pred_binary, truth_binary)

    if (nrow(df_binary) < 2) {
        return(NA_real_)
    }

    tryCatch(
        irr::kappa2(df_binary, weight = "unweighted")$value,
        error = function(e) NA_real_
    )
}

#' Compute per-code bootstrap CI
#' @param data Data frame
#' @param pred_col Prediction column
#' @param truth_col Truth column
#' @param target_code Code to test
#' @param R Number of bootstrap iterations
#' @return List with se, ci_lower, ci_upper
compute_percode_bootstrap_ci <- function(data, pred_col, truth_col, target_code, R = 1000) {
    boot_result <- tryCatch(
        {
            boot(
                data = data,
                statistic = boot_binary_kappa,
                R = R,
                pred_col = pred_col,
                truth_col = truth_col,
                target_code = target_code
            )
        },
        error = function(e) NULL
    )

    if (is.null(boot_result) || all(is.na(boot_result$t))) {
        return(list(se = NA_real_, ci_lower = NA_real_, ci_upper = NA_real_))
    }

    ci <- tryCatch(
        {
            boot.ci(boot_result, type = "perc")
        },
        error = function(e) NULL
    )

    list(
        se = sd(boot_result$t, na.rm = TRUE),
        ci_lower = if (!is.null(ci)) ci$percent[4] else NA_real_,
        ci_upper = if (!is.null(ci)) ci$percent[5] else NA_real_
    )
}
