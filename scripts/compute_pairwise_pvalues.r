#!/usr/bin/env Rscript
# Compute pairwise p-values for within-model prompt comparisons
# Uses bootstrap resampling to test if Kappa differs significantly between prompts

library(dplyr)
library(readr)
library(boot)
library(irr)
library(purrr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
    cat("Usage: Rscript compute_pairwise_pvalues.r <results_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
bootstrap_data_dir <- file.path(results_dir, "bootstrap_data")
output_file <- file.path(results_dir, "pairwise_pvalues.csv")

# Check if already computed
if (file.exists(output_file)) {
    cat("✓ Pairwise p-values already computed. Loading from cache:\n")
    cat("  ", output_file, "\n")
    pvalues <- read_csv(output_file, show_col_types = FALSE)
    print(pvalues)
    quit(status = 0)
}

cat("╔══════════════════════════════════════════════════════════╗\n")
cat("║  Computing Pairwise P-Values (Bootstrap)                ║\n")
cat("╚══════════════════════════════════════════════════════════╝\n\n")

# Get all joined files
joined_files <- list.files(bootstrap_data_dir, pattern = "_joined\\.csv$", full.names = TRUE)

# Extract model and prompt info
file_info <- data.frame(
    file = joined_files,
    stringsAsFactors = FALSE
) %>%
    mutate(
        basename = basename(file),
        parts = strsplit(gsub("_joined\\.csv$", "", basename), "_")
    ) %>%
    rowwise() %>%
    mutate(
        model_idx = min(grep("\\.", parts)),
        prompt = paste(parts[1:(model_idx - 1)], collapse = "_"),
        model = paste(parts[model_idx:length(parts)], collapse = "_")
    ) %>%
    ungroup() %>%
    select(file, prompt, model)

# Get unique models
models <- unique(file_info$model)

# Bootstrap function to compute kappa difference
boot_kappa_diff <- function(data1, data2, indices) {
    # Resample both datasets with same indices (paired bootstrap)
    d1 <- data1[indices, ]
    d2 <- data2[indices, ]

    # Calculate kappa for each
    calc_k <- function(d) {
        if (nrow(d) < 2) {
            return(NA)
        }

        levels <- sort(unique(c(d$TalkMove_Truth, d$TalkMove_Pred)))
        truth <- factor(d$TalkMove_Truth, levels = levels)
        pred <- factor(d$TalkMove_Pred, levels = levels)

        tryCatch(
            irr::kappa2(data.frame(truth, pred), weight = "unweighted")$value,
            error = function(e) NA
        )
    }

    k1 <- calc_k(d1)
    k2 <- calc_k(d2)

    return(k1 - k2)
}

# Store results
results_list <- list()

# For each model, compare all prompt pairs
for (model in models) {
    cat("Processing model:", model, "\n")

    # Get all prompts for this model
    model_files <- file_info %>% filter(model == !!model)
    prompts <- model_files$prompt

    if (length(prompts) < 2) {
        cat("  Skipping (only 1 prompt)\n")
        next
    }

    # Load all data for this model
    prompt_data <- list()
    for (i in seq_len(nrow(model_files))) {
        prompt_data[[model_files$prompt[i]]] <- read_csv(model_files$file[i], show_col_types = FALSE)
    }

    # Compare all pairs
    for (i in 1:(length(prompts) - 1)) {
        for (j in (i + 1):length(prompts)) {
            prompt1 <- prompts[i]
            prompt2 <- prompts[j]

            cat("  Comparing:", prompt1, "vs", prompt2, "\n")

            data1 <- prompt_data[[prompt1]]
            data2 <- prompt_data[[prompt2]]

            # Ensure same sample size (inner join on ID if available)
            if ("ID" %in% names(data1) && "ID" %in% names(data2)) {
                common_ids <- intersect(data1$ID, data2$ID)
                data1 <- data1 %>%
                    filter(ID %in% common_ids) %>%
                    arrange(ID)
                data2 <- data2 %>%
                    filter(ID %in% common_ids) %>%
                    arrange(ID)
            } else {
                # If no ID, just use min length
                n <- min(nrow(data1), nrow(data2))
                data1 <- data1[1:n, ]
                data2 <- data2[1:n, ]
            }

            # Bootstrap with R=1000
            set.seed(123)

            # Create wrapper function for boot
            boot_stat_wrapper <- function(data, indices) {
                boot_kappa_diff(data1, data2, indices)
            }

            boot_result <- boot(
                data = 1:nrow(data1),
                statistic = boot_stat_wrapper,
                R = 1000
            )

            # Calculate p-value (two-tailed)
            diffs <- boot_result$t[!is.na(boot_result$t)]
            if (length(diffs) == 0) {
                p_value <- NA
            } else {
                # Proportion of bootstrap samples with opposite sign
                obs_diff <- boot_result$t0
                if (is.na(obs_diff)) {
                    p_value <- NA
                } else {
                    if (obs_diff >= 0) {
                        p_value <- 2 * mean(diffs <= 0)
                    } else {
                        p_value <- 2 * mean(diffs >= 0)
                    }
                    p_value <- min(p_value, 1.0) # Cap at 1
                }
            }

            results_list[[length(results_list) + 1]] <- data.frame(
                Model = model,
                Prompt1 = prompt1,
                Prompt2 = prompt2,
                Kappa_Diff_Observed = boot_result$t0,
                P_Value = p_value,
                Significant_05 = !is.na(p_value) && p_value < 0.05,
                Significant_01 = !is.na(p_value) && p_value < 0.01,
                Significant_001 = !is.na(p_value) && p_value < 0.001,
                stringsAsFactors = FALSE
            )
        }
    }
}

# Combine and save
pvalues_df <- bind_rows(results_list)

write_csv(pvalues_df, output_file)

cat("\n✓ Pairwise p-values saved to:", output_file, "\n\n")
cat("Summary:\n")
print(pvalues_df %>%
    select(Model, Prompt1, Prompt2, Kappa_Diff_Observed, P_Value, Significant_05) %>%
    arrange(Model, P_Value))

cat("\n╔══════════════════════════════════════════════════════════╗\n")
cat("║  ✓ Pairwise significance testing complete               ║\n")
cat("╚══════════════════════════════════════════════════════════╝\n\n")
