#!/usr/bin/env Rscript
# FloorBenchmark Results Analyzer
# ================================
# Analyzes pipeline results and generates performance metrics
#
# Usage:
#   Rscript analyze_results.r [output_dir] [run_name] [input_dir]
#
# Arguments:
#   output_dir  - Path to output directory containing raw results (optional)
#   run_name    - Name for this analysis run (optional)
#   input_dir   - Path to input/ground truth directory (optional)
#
# If no arguments provided, uses values from pipeline_config.yaml

library(dplyr)
library(readr)
library(stringr)
library(irr)
library(fs)
library(purrr)
library(jsonlite)
library(tidyr)
library(yaml)

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Load configuration (as fallback)
config_path <- "config/pipeline_config.yaml"
if (file.exists(config_path)) {
    config <- read_yaml(config_path)
} else {
    config <- list(
        output_directory = "data/outputs",
        run_name = "unknown",
        sample_type = "full_sample",
        sample_paths = list(full_sample = "data/inputs/FullSample_Chunks_WithID")
    )
}

# Determine parameters (command-line overrides config)
if (length(args) >= 1) {
    output_dir <- args[1]
    run_name <- if (length(args) >= 2) args[2] else basename(output_dir)
    input_dir <- if (length(args) >= 3) {
        args[3]
    } else {
        # Try to infer from config
        sample_type <- config$sample_type
        if (!is.null(config$sample_paths[[sample_type]])) {
            config$sample_paths[[sample_type]]
        } else {
            "data/inputs/FullSample_Chunks_WithID"
        }
    }
} else {
    # Use config values
    output_dir <- file.path(config$output_directory, config$run_name)
    run_name <- config$run_name
    sample_type <- config$sample_type
    input_dir <- if (!is.null(config$sample_paths[[sample_type]])) {
        config$sample_paths[[sample_type]]
    } else {
        "data/inputs/FullSample_Chunks_WithID"
    }
}

if (!dir_exists(output_dir)) {
    stop("Output directory does not exist: ", output_dir)
}

if (!dir_exists(input_dir)) {
    warning("Input/ground truth directory not found: ", input_dir)
}

message("╔══════════════════════════════════════════════════════════╗")
message("║  FloorBenchmark Results Analyzer                        ║")
message("╚══════════════════════════════════════════════════════════╝\n")
message("Output directory: ", output_dir)
message("Input directory:  ", input_dir)
message("Run name:         ", run_name, "\n")

# Create run-specific results folder
run_results_dir <- file.path("results", run_name)
if (!dir_exists(run_results_dir)) {
    dir_create(run_results_dir, recurse = TRUE)
}

# Load Ground Truth
gt_file <- config$ground_truth_file
if (is.null(gt_file) || length(gt_file) == 0) {
    gt_file <- "data/inputs/ground_truth/ZeroShot_merged_annotations.csv"
}
if (!file.exists(gt_file)) {
    stop("Ground truth file not found: ", gt_file)
}

message("Loading ground truth from: ", gt_file)
df_map <- read_csv(gt_file, col_types = cols(.default = "c")) %>%
    select(ID, Transcript, Turn, Sentence, TalkMove_Truth = TalkMove_truth) %>%
    mutate(
        Transcript = str_remove(Transcript, "\\.xlsx$"),
        TalkMove_Truth = str_trim(TalkMove_Truth),
        ID = as.integer(ID),
        Turn = as.integer(Turn)
    ) %>%
    filter(!is.na(ID))

message("Loaded ", nrow(df_map), " ground truth records")

# Source flexible JSON parser
source("scripts/functions/json_parser.r")

# Source bootstrap CI functions
source("scripts/functions/bootstrap_ci.r")

# Get input files for calculating expected utterances
input_files <- list.files(input_dir, pattern = "[.]json$", full.names = TRUE)
if (!is.null(config$test_mode) && config$test_mode) {
    input_files <- input_files[seq_len(min(config$test_subset_size, length(input_files)))]
}


# Count total teacher utterances sent
total_teacher_sent <- 0
for (f in input_files) {
    data <- tryCatch(fromJSON(f), error = function(e) NULL)
    if (!is.null(data) && !is.null(data$utterances)) {
        total_teacher_sent <- total_teacher_sent + sum(data$utterances$Speaker == "T")
    }
}

message("Total teacher utterances sent per model/prompt: ", total_teacher_sent)

# Initialize data quality tracking
data_quality <- list()

# Analyze all results
comparisons <- list()
per_code_kappa <- list()
prompts <- dir_ls(output_dir, type = "directory")

for (prompt_path in prompts) {
    prompt_name <- basename(prompt_path)
    model_dirs <- dir_ls(prompt_path, type = "directory")

    for (model_path in model_dirs) {
        model_name <- basename(model_path)
        message("Analyzing: ", prompt_name, " -> ", model_name)

        # Get all output files
        files <- dir_ls(model_path, glob = "*_raw.txt")

        # Track data quality for this combination
        empty_count <- 0
        truncated_count <- 0
        parse_fail_count <- 0
        success_count <- 0
        total_preds <- 0

        # Parse all predictions
        all_preds <- list()
        for (f in files) {
            if (file.size(f) == 0) {
                empty_count <- empty_count + 1
                next
            }

            content <- tryCatch(read_file(f), error = function(e) "")
            df <- tryCatch(parse_prediction_file(f), error = function(e) NULL, warning = function(w) NULL)

            if (is.null(df) || nrow(df) == 0) {
                # Check if truncated
                last_char <- trimws(substr(content, max(1, nchar(content) - 5), nchar(content)))
                if (!grepl("[\\]\\}]$", last_char)) {
                    truncated_count <- truncated_count + 1
                } else {
                    parse_fail_count <- parse_fail_count + 1
                }
            } else {
                success_count <- success_count + 1
                total_preds <- total_preds + nrow(df)
                all_preds <- c(all_preds, list(df))
            }
        }

        # Store data quality for this combination
        data_quality[[paste(prompt_name, model_name, sep = "|")]] <- data.frame(
            Prompt = prompt_name,
            Model = model_name,
            Files_Total = length(files),
            Files_Empty = empty_count,
            Files_Truncated = truncated_count,
            Files_Parse_Fail = parse_fail_count,
            Files_Success = success_count,
            Predictions_Parsed = total_preds,
            Expected_Utterances = total_teacher_sent,
            stringsAsFactors = FALSE
        )

        # Combine and process
        if (length(all_preds) == 0) {
            message("  No valid predictions")
            next
        }

        df_preds_raw <- bind_rows(all_preds)

        # Try to join with ground truth
        cols <- names(df_preds_raw)
        joined <- NULL

        if ("ID" %in% cols && !all(is.na(df_preds_raw$ID))) {
            df_preds_clean <- df_preds_raw %>%
                mutate(ID = as.integer(ID)) %>%
                filter(!is.na(ID)) %>%
                select(ID, TalkMove_Pred = TalkMove)

            joined <- inner_join(df_preds_clean, df_map, by = "ID")
        }

        if (!is.null(joined) && nrow(joined) > 0) {
            # Normalize TalkMove values
            joined <- joined %>%
                mutate(
                    # Fix all curly apostrophes to straight apostrophes using explicit UTF-8 codes
                    # U+2019 (right single quotation mark) and U+2018 (left single quotation mark)
                    TalkMove_Pred = str_replace_all(TalkMove_Pred, intToUtf8(8217), "'"), # '
                    TalkMove_Pred = str_replace_all(TalkMove_Pred, intToUtf8(8216), "'"), # '
                    TalkMove_Truth = str_replace_all(TalkMove_Truth, intToUtf8(8217), "'"),
                    TalkMove_Truth = str_replace_all(TalkMove_Truth, intToUtf8(8216), "'"),
                    # Fix missing apostrophe in "Another's" (some models output "Anothers" or "Another s")
                    TalkMove_Pred = str_replace_all(TalkMove_Pred, "Anothers", "Another's"),
                    TalkMove_Pred = str_replace_all(TalkMove_Pred, "Another s", "Another's"),
                    # Fix corrupted UTF-8 apostrophe (byte 0x19 remaining after mangled curly quote)
                    TalkMove_Pred = str_replace_all(TalkMove_Pred, intToUtf8(0x19), "'"),
                    # Normalize None values
                    TalkMove_Pred = ifelse(
                        is.na(TalkMove_Pred) | TalkMove_Pred == "" |
                            TalkMove_Pred == "NA" | TalkMove_Pred == "null",
                        "None", TalkMove_Pred
                    ),
                    TalkMove_Truth = ifelse(
                        is.na(TalkMove_Truth) | TalkMove_Truth == "",
                        "None", TalkMove_Truth
                    )
                )

            # Calculate metrics
            acc <- mean(joined$TalkMove_Truth == joined$TalkMove_Pred)
            k_res <- kappa2(joined[, c("TalkMove_Truth", "TalkMove_Pred")])
            kappa <- k_res$value

            message("  N=", nrow(joined), " Acc=", round(acc, 3), " Kappa=", round(kappa, 3))

            # Save joined data for bootstrap computation
            bootstrap_data_dir <- file.path(run_results_dir, "bootstrap_data")
            if (!dir_exists(bootstrap_data_dir)) {
                dir_create(bootstrap_data_dir, recurse = TRUE)
            }
            joined_file <- file.path(
                bootstrap_data_dir,
                paste0(prompt_name, "_", model_name, "_joined.csv")
            )
            write_csv(joined, joined_file)

            comparisons[[paste(prompt_name, model_name, sep = "|")]] <- data.frame(
                Prompt = prompt_name,
                Model = model_name,
                N = nrow(joined),
                Accuracy = acc,
                Kappa = kappa,
                stringsAsFactors = FALSE
            )

            # Calculate per-code kappa
            unique_codes <- unique(c(joined$TalkMove_Truth, joined$TalkMove_Pred))
            per_code_results <- lapply(unique_codes, function(code) {
                # Create binary coding for this code
                code_df <- data.frame(
                    Truth = ifelse(joined$TalkMove_Truth == code, "Yes", "No"),
                    Pred = ifelse(joined$TalkMove_Pred == code, "Yes", "No"),
                    stringsAsFactors = FALSE
                )

                # Calculate kappa for this code
                k_code <- tryCatch(
                    {
                        k_res <- kappa2(code_df)
                        k_res$value
                    },
                    error = function(e) NA
                )

                # Calculate accuracy for this code
                acc_code <- mean(code_df$Truth == code_df$Pred)

                # Count occurrences
                n_truth <- sum(joined$TalkMove_Truth == code)
                n_pred <- sum(joined$TalkMove_Pred == code)

                data.frame(
                    Prompt = prompt_name,
                    Model = model_name,
                    Code = code,
                    N_Truth = n_truth,
                    N_Pred = n_pred,
                    Accuracy = acc_code,
                    Kappa = k_code,
                    stringsAsFactors = FALSE
                )
            })

            per_code_df <- bind_rows(per_code_results)
            per_code_kappa[[paste(prompt_name, model_name, sep = "|")]] <- per_code_df
        } else {
            message("  Join failed (no matches)")
        }
    }
}

# Generate and save data quality report
if (length(data_quality) > 0) {
    quality_df <- bind_rows(data_quality) %>%
        rename(Utterances_Returned = Predictions_Parsed) %>%
        mutate(
            Utterances_Returned_Pct = round(100 * Utterances_Returned / Expected_Utterances, 1),
            Files_Returned_Pct = round(100 * Files_Success / Files_Total, 1)
        )

    # Save detailed quality report
    quality_file <- file.path(run_results_dir, "data_quality_report.csv")
    write_csv(quality_df, quality_file)

    # Generate summary by model
    quality_by_model <- quality_df %>%
        group_by(Model) %>%
        summarise(
            Total_Files = sum(Files_Total),
            Empty_Files = sum(Files_Empty),
            Truncated_Files = sum(Files_Truncated),
            Parse_Fail_Files = sum(Files_Parse_Fail),
            Success_Files = sum(Files_Success),
            Utterances_Returned = sum(Utterances_Returned),
            Expected_Utterances = sum(Expected_Utterances),
            .groups = "drop"
        ) %>%
        mutate(
            Utterances_Returned_Pct = round(100 * Utterances_Returned / Expected_Utterances, 1),
            Files_Returned_Pct = round(100 * Success_Files / Total_Files, 1)
        )

    quality_model_file <- file.path(run_results_dir, "data_quality_by_model.csv")
    write_csv(quality_by_model, quality_model_file)

    # Generate summary by prompt
    quality_by_prompt <- quality_df %>%
        group_by(Prompt) %>%
        summarise(
            Total_Files = sum(Files_Total),
            Empty_Files = sum(Files_Empty),
            Truncated_Files = sum(Files_Truncated),
            Parse_Fail_Files = sum(Files_Parse_Fail),
            Success_Files = sum(Files_Success),
            Utterances_Returned = sum(Utterances_Returned),
            Expected_Utterances = sum(Expected_Utterances),
            .groups = "drop"
        ) %>%
        mutate(
            Utterances_Returned_Pct = round(100 * Utterances_Returned / Expected_Utterances, 1),
            Files_Returned_Pct = round(100 * Success_Files / Total_Files, 1)
        )

    quality_prompt_file <- file.path(run_results_dir, "data_quality_by_prompt.csv")
    write_csv(quality_by_prompt, quality_prompt_file)

    message("\n=== Data Quality Report ===")
    message("Saved to: ", run_results_dir)
    message("\nBy Model:")
    print(quality_by_model)
    message("\nBy Prompt:")
    print(quality_by_prompt)
}

# Save results
if (length(comparisons) > 0) {
    final_results <- bind_rows(comparisons) %>%
        arrange(desc(Kappa))

    # Add run metadata columns
    final_results <- final_results %>%
        mutate(
            Run_Name = config$run_name,
            Sample_Type = config$sample_type,
            Analysis_Time = Sys.time()
        )

    # Save to run-specific results directory
    results_file <- file.path(run_results_dir, "results.csv")
    write_csv(final_results, results_file)

    message("\n=== Results Summary ===")
    print(final_results)

    message("\nResults saved to: ", results_file)

    # Also save in output directory
    write_csv(final_results, file.path(output_dir, "analysis_results.csv"))

    # Create summary statistics with metadata
    summary_stats <- final_results %>%
        group_by(Model) %>%
        summarize(
            Prompts_Tested = n(),
            Avg_Accuracy = mean(Accuracy),
            Avg_Kappa = mean(Kappa),
            Best_Kappa = max(Kappa),
            Total_Utterances = sum(N),
            .groups = "drop"
        ) %>%
        mutate(
            Run_Name = config$run_name,
            Sample_Type = config$sample_type,
            Analysis_Time = Sys.time()
        ) %>%
        arrange(desc(Avg_Kappa))

    summary_file <- file.path(run_results_dir, "summary.csv")
    write_csv(summary_stats, summary_file)

    # Save per-code kappa breakdown
    if (length(per_code_kappa) > 0) {
        per_code_df <- bind_rows(per_code_kappa)
        per_code_file <- file.path(run_results_dir, "per_code_kappa.csv")
        write_csv(per_code_df, per_code_file)
        message("\nPer-code kappa breakdown saved to: ", per_code_file)
    }

    # Add bootstrap computation with caching
    # This section is a placeholder for actual bootstrap code.
    # The implementation would typically involve:
    # 1. Defining a bootstrap function that samples with replacement and calculates metrics.
    # 2. Using a caching mechanism (e.g., `memoise` package or manual file-based caching)
    #    to store bootstrap results for each prompt/model combination.
    # 3. Iterating through `comparisons` or `joined` data to perform bootstrapping.
    # 4. Storing and summarizing bootstrap results (e.g., confidence intervals).
    #
    # Example structure (conceptual, not executable without full implementation):
    #
    # bootstrap_results_list <- list()
    # bootstrap_cache_dir <- file.path(run_results_dir, "bootstrap_cache")
    # dir.create(bootstrap_cache_dir, showWarnings = FALSE)
    #
    # for (comp_name in names(comparisons)) {
    #     parts <- strsplit(comp_name, "\\|")[[1]]
    #     current_prompt_name <- parts[1]
    #     current_model_name <- parts[2]
    #
    #     # Retrieve the original joined data for this comparison
    #     # (This would require storing 'joined' data per comparison or re-joining)
    #     # For simplicity, let's assume 'joined_data_for_bootstrap' is available
    #     # joined_data_for_bootstrap <- get_joined_data(current_prompt_name, current_model_name)
    #
    #     if (!is.null(joined_data_for_bootstrap) && nrow(joined_data_for_bootstrap) > 0) {
    #         cache_file <- file.path(bootstrap_cache_dir, paste0("bootstrap_", comp_name, ".rds"))
    #
    #         if (file.exists(cache_file)) {
    #             message("  Loading cached bootstrap results for ", comp_name)
    #             boot_res <- readRDS(cache_file)
    #         } else {
    #             message("  Running bootstrap for ", comp_name)
    #             # Define bootstrap function
    #             boot_func <- function(data, indices) {
    #                 d <- data[indices, ]
    #                 acc <- mean(d$TalkMove_Truth == d$TalkMove_Pred)
    #                 k_res <- kappa2(d[, c("TalkMove_Truth", "TalkMove_Pred")])
    #                 kappa <- k_res$value
    #                 c(Accuracy = acc, Kappa = kappa)
    #             }
    #
    #             # Run bootstrap (e.g., using 'boot' package)
    #             # library(boot)
    #             # boot_obj <- boot(data = joined_data_for_bootstrap, statistic = boot_func, R = 1000)
    #             # boot_ci_acc <- boot.ci(boot_obj, type = "perc", index = 1)$percent[4:5]
    #             # boot_ci_kappa <- boot.ci(boot_obj, type = "perc", index = 2)$percent[4:5]
    #
    #             # Placeholder for actual results
    #             boot_res <- data.frame(
    #                 Prompt = current_prompt_name,
    #                 Model = current_model_name,
    #                 Metric = c("Accuracy", "Kappa"),
    #                 Lower_CI = c(NA, NA), # Replace with actual CI
    #                 Upper_CI = c(NA, NA)  # Replace with actual CI
    #             )
    #             saveRDS(boot_res, cache_file)
    #         }
    #         bootstrap_results_list[[comp_name]] <- boot_res
    #     }
    # }
    #
    # if (length(bootstrap_results_list) > 0) {
    #     bootstrap_df <- bind_rows(bootstrap_results_list)
    #     bootstrap_file <- file.path(run_results_dir, "bootstrap_results.csv")
    #     write_csv(bootstrap_df, bootstrap_file)
    #     message("\nBootstrap results saved to: ", bootstrap_file)
    # }


    # Save run metadata as JSON
    run_metadata <- list(
        run_name = config$run_name,
        sample_type = config$sample_type,
        ground_truth_file = gt_file,
        input_files_count = length(input_files),
        total_teacher_utterances_sent = total_teacher_sent,
        models_tested = unique(final_results$Model),
        prompts_tested = unique(final_results$Prompt),
        total_comparisons = nrow(final_results),
        total_utterances_analyzed = sum(final_results$N),
        analysis_time = as.character(Sys.time()),
        config = config
    )
    metadata_file <- file.path(run_results_dir, "metadata.json")
    write(toJSON(run_metadata, pretty = TRUE, auto_unbox = TRUE), metadata_file)

    message("\n=== Model Summary ===")
    print(summary_stats)
    message("\nSummary saved to: ", summary_file)
    message("Metadata saved to: ", metadata_file)
} else {
    message("No results to analyze!")
}

message("\n=== Analysis Complete ===")
message("All results saved to: ", run_results_dir)
