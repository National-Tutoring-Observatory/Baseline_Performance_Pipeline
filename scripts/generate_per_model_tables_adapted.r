#!/usr/bin/env Rscript
# Adapted from scripts/analysis/generate_per_model_tables.r
# Uses FloorBenchmark_Pipeline bootstrap_data instead of merged_annotations.csv

library(dplyr)
library(readr)
library(xtable)
library(irr)
library(caret)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_per_model_tables_adapted.r <results_dir> <output_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_dir <- args[2]

# Code mapping (in manuscript order)
code_map <- c(
    "Keeping Everyone Together" = "Keep Together",
    "Getting Students to Relate to Another's Ideas" = "Relate to Ideas",
    "Restating" = "Restating",
    "Revoicing" = "Revoicing",
    "Pressing for Accuracy" = "Press Accuracy",
    "Pressing for Reasoning" = "Press Reasoning"
)

# Model list (in manuscript order)
models <- c(
    "google.gemini-3-pro-preview" = "Gemini 3 Pro",
    "google.gemini-2.5-pro" = "Gemini 2.5",
    "openai.gpt-5" = "GPT-5",
    "openai.o3" = "o3",
    "anthropic.claude-4.5-sonnet" = "Claude 4.5 Sonnet",
    "anthropic.claude-4.5-opus" = "Claude 4.5 Opus"
)

# Calculate me metrics for a specific code
calc_code_metrics <- function(df, code_full) {
    # Binary classification: this code vs not this code
    truth_binary <- ifelse(df$TalkMove_Truth == code_full, "Positive", "Negative")
    pred_binary <- ifelse(df$TalkMove_Pred == code_full, "Positive", "Negative")

    # Manual calculation
    tp <- sum(truth_binary == "Positive" & pred_binary == "Positive", na.rm = TRUE)
    fp <- sum(truth_binary == "Negative" & pred_binary == "Positive", na.rm = TRUE)
    tn <- sum(truth_binary == "Negative" & pred_binary == "Negative", na.rm = TRUE)
    fn <- sum(truth_binary == "Positive" & pred_binary == "Negative", na.rm = TRUE)

    # Calculate metrics
    precision <- if (tp + fp > 0) tp / (tp + fp) else 0
    recall <- if (tp + fn > 0) tp / (tp + fn) else 0
    f1 <- if (precision + recall > 0) 2 * (precision * recall) / (precision + recall) else 0

    # Calculate Kappa
    kappa_val <- tryCatch(
        {
            irr::kappa2(data.frame(truth_binary, pred_binary), weight = "unweighted")$value
        },
        error = function(e) {
            NA
        }
    )

    return(c(
        Precision = precision,
        Recall = recall,
        F1 = f1,
        Kappa = kappa_val
    ))
}

# Process each model
prompts <- c("TalkMoves_Teacher_ZeroShot", "TalkMoves_Teacher_OneShot", "TalkMoves_Teacher_FewShot_3", "TalkMoves_Teacher_FewShot_ALL")
prompt_labels <- c("ZeroShot", "OneShot", "FewShot3", "FewShot")

bootstrap_data_dir <- file.path(results_dir, "bootstrap_data")

for (model_key in names(models)) {
    model_name <- models[model_key]
    message(paste("Processing model:", model_name))

    all_results <- list()

    for (i in seq_along(prompts)) {
        prompt <- prompts[i]
        prompt_label <- prompt_labels[i]

        # Find matching file
        file_pattern <- paste0(prompt, "_", model_key, "_joined.csv")
        file_path <- file.path(bootstrap_data_dir, file_pattern)

        if (!file.exists(file_path)) {
            warning(paste("File not found:", file_path))
            next
        }

        df <- read_csv(file_path, show_col_types = FALSE)

        # Calculate metrics for each code
        for (code_full in names(code_map)) {
            code_short <- code_map[code_full]
            metrics <- calc_code_metrics(df, code_full)

            all_results[[length(all_results) + 1]] <- data.frame(
                Prompt = prompt_label,
                Code = code_short,
                Precision = metrics["Precision"],
                Recall = metrics["Recall"],
                F1 = metrics["F1"],
                Kappa = metrics["Kappa"],
                stringsAsFactors = FALSE
            )
        }
    }

    # Combine results
    final_df <- do.call(rbind, all_results)

    # Format values
    final_df$Precision <- sprintf("%.2f", final_df$Precision)
    final_df$Recall <- sprintf("%.2f", final_df$Recall)
    final_df$F1 <- sprintf("%.2f", final_df$F1)
    final_df$Kappa <- sprintf("%.2f", final_df$Kappa)

    # Replace NaN with --
    final_df[final_df == "NaN"] <- "--"

    # Bold max values per prompt per metric, italicize min values
    for (p in prompt_labels) {
        sub_df <- final_df[final_df$Prompt == p, ]

        for (metric in c("Precision", "Recall", "F1", "Kappa")) {
            # Get numeric values
            vals <- as.numeric(sub_df[[metric]])
            if (all(is.na(vals))) next

            max_val <- max(vals, na.rm = TRUE)
            min_val <- min(vals, na.rm = TRUE)

            max_idx <- which(abs(vals - max_val) < 1e-6)
            min_idx <- which(abs(vals - min_val) < 1e-6)

            # Bold the max
            for (idx in max_idx) {
                row_idx <- which(final_df$Prompt == p)[idx]
                final_df[row_idx, metric] <- paste0("\\textbf{", final_df[row_idx, metric], "}")
            }

            # Italicize the min (if different from max)
            for (idx in min_idx) {
                row_idx <- which(final_df$Prompt == p)[idx]
                # Don't italicize if already bolded
                if (!grepl("textbf", final_df[row_idx, metric])) {
                    final_df[row_idx, metric] <- paste0("\\textit{", final_df[row_idx, metric], "}")
                }
            }
        }
    }

    # Prepare for table output
    table_df <- final_df %>% select(Code, Precision, Recall, F1, Kappa)

    # Create section headers
    rows_per_group <- sapply(prompt_labels, function(p) sum(final_df$Prompt == p))
    header_pos <- cumsum(c(0, rows_per_group[-length(rows_per_group)]))

    add_row_cmd <- list()
    add_row_cmd$pos <- as.list(header_pos)
    add_row_cmd$command <- as.vector(sapply(prompt_labels, function(x) {
        display_x <- case_when(
            x == "FewShot3" ~ "Few Shot (Three Examples)",
            x == "FewShot" ~ "Few Shot (All Examples)",
            x == "ZeroShot" ~ "Zero Shot",
            x == "OneShot" ~ "One Shot",
            TRUE ~ x
        )
        prefix <- if (x == "ZeroShot") "\\midrule " else "\\addlinespace[0.2em] "
        paste0(prefix, "\\multicolumn{5}{l}{\\textbf{", display_x, "}} \\\\ \n")
    }))

    # Rename Kappa column
    colnames(table_df)[colnames(table_df) == "Kappa"] <- "$\\kappa$"

    # Create LaTeX table
    latex_table <- xtable(
        table_df,
        caption = paste0("Per-Code Performance for ", model_name, "."),
        label = paste0("tab:per_code_", gsub("[^a-z0-9]", "_", tolower(model_name))),
        align = c("l", "p{3.5cm}", ">{ \\centering \\arraybackslash}p{2.0cm}", ">{ \\centering \\arraybackslash}p{2.0cm}", ">{ \\centering \\arraybackslash}p{2.0cm}", ">{ \\centering \\arraybackslash}p{2.0cm}")
    )

    # Output file
    output_file <- file.path(output_dir, paste0("per_code_", gsub("[^a-z0-9]", "_", tolower(model_name)), ".tex"))

    print(
        latex_table,
        file = output_file,
        include.rownames = FALSE,
        booktabs = TRUE,
        caption.placement = "top",
        sanitize.text.function = function(x) x,
        add.to.row = add_row_cmd,
        hline.after = c(-1, nrow(table_df)),
        table.placement = "H"
    )

    message(paste("Table saved to:", output_file))
}

message("All tables generated successfully!")
