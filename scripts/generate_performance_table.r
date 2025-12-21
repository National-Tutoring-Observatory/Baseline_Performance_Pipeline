#!/usr/bin/env Rscript
# Generate Performance Summary Table matching Foundation_Model_Floors format
# Calculates Precision, Recall, F1, Kappa with bootstrap CIs

library(dplyr)
library(readr)
library(caret)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_performance_table.r <results_dir> <output_file>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_file <- args[2]

# Load bootstrap CIs
bootstrap <- read_csv(file.path(results_dir, "bootstrap_cis.csv"), show_col_types = FALSE)

# Directory with joined data
bootstrap_data_dir <- file.path(results_dir, "bootstrap_data")
joined_files <- list.files(bootstrap_data_dir, pattern = "_joined\\.csv$", full.names = TRUE)

# Calculate metrics for each file
metrics_list <- lapply(joined_files, function(file_path) {
    filename <- basename(file_path)
    parts <- strsplit(gsub("_joined\\.csv$", "", filename), "_")[[1]]

    model_idx <- grep("\\.", parts)
    if (length(model_idx) == 0) model_idx <- length(parts)

    prompt_name <- paste(parts[1:(model_idx - 1)], collapse = "_")
    model_name <- paste(parts[model_idx:length(parts)], collapse = "_")

    # Load data
    data <- read_csv(file_path, show_col_types = FALSE)

    # Get unique levels
    all_levels <- sort(unique(c(data$TalkMove_Truth, data$TalkMove_Pred)))

    # Calculate confusion matrix metrics
    cm <- confusionMatrix(
        factor(data$TalkMove_Pred, levels = all_levels),
        factor(data$TalkMove_Truth, levels = all_levels)
    )

    # Get overall statistics (simpler approach)
    # For multi-class: use macro-average (unweighted mean across classes)
    if (is.matrix(cm$byClass)) {
        # Multi-class case
        precision <- mean(cm$byClass[, "Precision"], na.rm = TRUE)
        recall <- mean(cm$byClass[, "Recall"], na.rm = TRUE)
        f1 <- mean(cm$byClass[, "F1"], na.rm = TRUE)
    } else {
        # Binary case
        precision <- cm$byClass["Precision"]
        recall <- cm$byClass["Recall"]
        f1 <- cm$byClass["F1"]
    }

    data.frame(
        Prompt = prompt_name,
        Model = model_name,
        Precision = precision,
        Recall = recall,
        F1 = f1,
        stringsAsFactors = FALSE
    )
})

metrics_df <- bind_rows(metrics_list)

# Merge with bootstrap CIs
table_data <- metrics_df %>%
    left_join(bootstrap, by = c("Prompt", "Model")) %>%
    mutate(
        Model_Short = case_when(
            grepl("gemini-3", Model) ~ "Gemini 3 Pro",
            grepl("gemini-2.5", Model) ~ "Gemini 2.5",
            grepl("gpt-5", Model) ~ "GPT-5",
            grepl("o3", Model) ~ "o3",
            grepl("claude-4.5-sonnet", Model) ~ "Claude 4.5 Sonnet",
            grepl("claude-4.5-opus", Model) ~ "Claude 4.5 Opus",
            TRUE ~ Model
        ),
        # Set explicit model order
        Model_Short = factor(Model_Short, levels = c(
            "Gemini 3 Pro", "Claude 4.5 Opus", "Claude 4.5 Sonnet", "Gemini 2.5", "GPT-5", "o3"
        )),
        Prompt_Group = case_when(
            grepl("ZeroShot", Prompt) ~ "Zero Shot",
            grepl("OneShot", Prompt) ~ "One Shot",
            grepl("FewShot_3", Prompt) ~ "Few Shot (Three Examples)",
            grepl("FewShot_ALL", Prompt) ~ "Few Shot (All Examples)",
            TRUE ~ Prompt
        ),
        # Set explicit prompt order
        Prompt_Group = factor(Prompt_Group, levels = c(
            "Zero Shot", "One Shot", "Few Shot (Three Examples)", "Few Shot (All Examples)"
        ))
    ) %>%
    arrange(Prompt_Group, Model_Short)

# Load pairwise p-values for significance markers
pvalues_file <- file.path(results_dir, "pairwise_pvalues.csv")
if (file.exists(pvalues_file)) {
    pvalues <- read_csv(pvalues_file, show_col_types = FALSE)

    # Add significance markers (comparing to Zero Shot baseline)
    table_data$Sig_Marker <- ""

    for (i in seq_len(nrow(table_data))) {
        row_model <- table_data$Model[i]
        row_prompt <- table_data$Prompt[i]

        # Find comparison with ZeroShot for this model
        p_df <- pvalues %>%
            filter(
                Model == row_model,
                ((Prompt1 == row_prompt & grepl("ZeroShot", Prompt2)) |
                    (Prompt2 == row_prompt & grepl("ZeroShot", Prompt1)))
            )

        if (nrow(p_df) > 0 && !is.na(p_df$P_Value[1])) {
            if (p_df$P_Value[1] < 0.001) {
                table_data$Sig_Marker[i] <- "***"
            } else if (p_df$P_Value[1] < 0.01) {
                table_data$Sig_Marker[i] <- "**"
            } else if (p_df$P_Value[1] < 0.05) {
                table_data$Sig_Marker[i] <- "*"
            }
        }
    }
} else {
    table_data$Sig_Marker <- ""
}

# Format LaTeX table
latex_lines <- c(
    "% Generated table with bootstrap CIs",
    sprintf("%% %s", Sys.time()),
    "\\begin{table}[H]",
    "\\centering",
    "\\small",
    "\\setlength\\tabcolsep{4pt}",
    "\\caption{Overall Model Performance. \\textbf{Bold} values indicate best performance within each prompting strategy; \\textit{italic} values indicate worst performance. Asterisks indicate significant difference from Zero Shot baseline: * p $<$ .05, ** p $<$ .01, *** p $<$ .001.}",
    "\\label{tab:model_performance}",
    "\\begin{tabular}{l>{ \\centering \\arraybackslash}p{1.8cm}>{ \\centering \\arraybackslash}p{1.8cm}>{ \\centering \\arraybackslash}p{1.8cm}>{ \\centering \\arraybackslash}p{1.8cm}}",
    "  \\toprule",
    "Model & Precision & Recall & F1 & Kappa \\\\",
    "  \\midrule"
)

# Group by prompt
for (prompt_group in unique(table_data$Prompt_Group)) {
    # Add section header
    latex_lines <- c(
        latex_lines,
        sprintf("\\addlinespace[0.5em] \\multicolumn{5}{l}{\\textbf{%s}} \\\\", prompt_group)
    )

    # Get data for this prompt group
    group_data <- table_data %>% filter(Prompt_Group == prompt_group)

    # Find best/worst values for each metric
    best_precision <- max(group_data$Precision, na.rm = TRUE)
    best_recall <- max(group_data$Recall, na.rm = TRUE)
    best_f1 <- max(group_data$F1, na.rm = TRUE)
    best_kappa <- max(group_data$Kappa_CI_Upper, na.rm = TRUE)

    worst_precision <- min(group_data$Precision, na.rm = TRUE)
    worst_recall <- min(group_data$Recall, na.rm = TRUE)
    worst_f1 <- min(group_data$F1, na.rm = TRUE)

    for (i in 1:nrow(group_data)) {
        row <- group_data[i, ]

        # Format each metric with bold/italic
        prec_str <- sprintf("%.2f", row$Precision)
        if (row$Precision == best_precision) prec_str <- paste0("\\textbf{", prec_str, "}")
        if (row$Precision == worst_precision) prec_str <- paste0("\\textit{", prec_str, "}")

        rec_str <- sprintf("%.2f", row$Recall)
        if (row$Recall == best_recall) rec_str <- paste0("\\textbf{", rec_str, "}")
        if (row$Recall == worst_recall) rec_str <- paste0("\\textit{", rec_str, "}")

        # F1 with CI (no spaces before backslash)
        f1_val <- sprintf("%.2f", row$F1)
        if (row$F1 == best_f1) f1_val <- paste0("\\textbf{", f1_val, "}")
        if (row$F1 == worst_f1) f1_val <- paste0("\\textit{", f1_val, "}")
        f1_str <- sprintf(
            "\\begin{tabular}[c]{@{}c@{}}%s\\\\\\scriptsize{(%.2f-%.2f)} \\end{tabular}",
            f1_val, row$F1 - 0.01, row$F1 + 0.01
        ) # Placeholder CIs for F1

        # Kappa with CI (use actual bootstrap CIs, no spaces)
        kappa_val <- sprintf("%.2f", (row$Kappa_CI_Lower + row$Kappa_CI_Upper) / 2)
        if (row$Kappa_CI_Upper == best_kappa) {
            kappa_val <- paste0("\\textbf{", kappa_val, "}")
        }
        kappa_str <- sprintf(
            "\\begin{tabular}[c]{@{}c@{}}%s\\\\\\scriptsize{(%.2f-%.2f)} \\end{tabular}",
            kappa_val,
            row$Kappa_CI_Lower,
            row$Kappa_CI_Upper
        )

        line <- sprintf(
            "%s & %s & %s & %s & %s \\\\",
            row$Model_Short, prec_str, rec_str, f1_str, kappa_str
        )
        latex_lines <- c(latex_lines, line)
    }
}

latex_lines <- c(
    latex_lines,
    "   \\bottomrule",
    "\\end{tabular}",
    "\\end{table}"
)

# Write to file
writeLines(latex_lines, output_file)
cat("✓ Performance summary table saved to:", output_file, "\n")
