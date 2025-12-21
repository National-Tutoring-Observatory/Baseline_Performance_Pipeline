#!/usr/bin/env Rscript
# Adapted prompt differences plot with significance testing
# Based on scripts/analysis/analyze_prompt_differences.r

library(dplyr)
library(readr)
library(ggplot2)
library(boot)
library(irr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    cat("Usage: Rscript generate_prompt_diff_plot_adapted.r <results_dir> <output_dir>\n")
    quit(status = 1)
}

results_dir <- args[1]
output_dir <- args[2]

# Load results and bootstrap CIs
results <- read_csv(file.path(results_dir, "results.csv"), show_col_types = FALSE)
bootstrap_cis <- read_csv(file.path(results_dir, "bootstrap_cis.csv"), show_col_types = FALSE)

# Merge
plot_df <- results %>%
    left_join(bootstrap_cis, by = c("Prompt", "Model")) %>%
    mutate(
        Model_Clean = case_when(
            grepl("gemini-3", Model) ~ "Gemini 3 Pro",
            grepl("gemini-2.5", Model) ~ "Gemini 2.5",
            grepl("gpt-5", Model) ~ "GPT-5",
            grepl("o3", Model) ~ "o3",
            grepl("claude-4.5-sonnet", Model) ~ "Claude Sonnet 4.5",
            grepl("claude-4.5-opus", Model) ~ "Claude Opus 4.5",
            TRUE ~ Model
        ),
        Condition = case_when(
            grepl("ZeroShot", Prompt) ~ "Zero Shot",
            grepl("OneShot", Prompt) ~ "One Shot",
            grepl("FewShot_3", Prompt) ~ "Few Shot (3)",
            grepl("FewShot_ALL", Prompt) ~ "Few Shot (All)",
            TRUE ~ Prompt
        )
    )

# Set model order (top to bottom in facet) - Opus ranked 2nd
plot_df$Model_Clean <- factor(plot_df$Model_Clean, levels = c(
    "Gemini 3 Pro", "Claude Opus 4.5", "Claude Sonnet 4.5", "Gemini 2.5", "GPT-5", "o3"
))

# Set factor levels (for coord_flip: bottom to top)
plot_df$Condition <- factor(plot_df$Condition, levels = c("Few Shot (All)", "Few Shot (3)", "One Shot", "Zero Shot"))

# Load pairwise p-values
pvalues_file <- file.path(results_dir, "pairwise_pvalues.csv")
if (!file.exists(pvalues_file)) {
    cat("Warning: pairwise_pvalues.csv not found. Run compute_pairwise_pvalues.r first.\n")
    cat("Generating plot without significance brackets.\n")
    pvalues_df <- data.frame()
    bracket_df <- data.frame()
} else {
    pvalues_df <- read_csv(pvalues_file, show_col_types = FALSE)

    # Create brackets for significant comparisons
    bracket_list <- list()
    model_bracket_count <- list() # Track count per model

    for (i in seq_len(nrow(pvalues_df))) {
        row <- pvalues_df[i, ]

        if (is.na(row$P_Value) || row$P_Value >= 0.05) next

        # Map prompt names to condition names
        cond1 <- case_when(
            grepl("ZeroShot", row$Prompt1) ~ "Zero Shot",
            grepl("OneShot", row$Prompt1) ~ "One Shot",
            grepl("FewShot_3", row$Prompt1) ~ "Few Shot (3)",
            grepl("FewShot_ALL", row$Prompt1) ~ "Few Shot (All)",
            TRUE ~ row$Prompt1
        )

        cond2 <- case_when(
            grepl("ZeroShot", row$Prompt2) ~ "Zero Shot",
            grepl("OneShot", row$Prompt2) ~ "One Shot",
            grepl("FewShot_3", row$Prompt2) ~ "Few Shot (3)",
            grepl("FewShot_ALL", row$Prompt2) ~ "Few Shot (All)",
            TRUE ~ row$Prompt2
        )

        # Determine label
        label <- if (row$Significant_001) "***" else if (row$Significant_01) "**" else "*"

        # Get y position - match by original Model name from plot_df
        model_data <- plot_df %>% filter(Model == row$Model)
        if (nrow(model_data) == 0) next # Skip if model not found

        max_y <- max(model_data$Kappa_CI_Upper, na.rm = TRUE)

        # Get bracket count for THIS model (reset per model)
        if (is.null(model_bracket_count[[row$Model]])) {
            model_bracket_count[[row$Model]] <- 0
        }
        model_idx <- model_bracket_count[[row$Model]]
        model_bracket_count[[row$Model]] <- model_idx + 1

        bracket_list[[length(bracket_list) + 1]] <- data.frame(
            Model = row$Model,
            Model_Clean = model_data$Model_Clean[1],
            group1 = cond1,
            group2 = cond2,
            label = label,
            p_value = row$P_Value,
            y.position = max_y + 0.015 + (model_idx * 0.02),
            stringsAsFactors = FALSE
        )
    }

    bracket_df <- if (length(bracket_list) > 0) bind_rows(bracket_list) else data.frame()
}


# Color/Shape Maps
color_map <- c(
    "Zero Shot" = "#D55E00",
    "One Shot" = "#0072B2",
    "Few Shot (3)" = "#009E73",
    "Few Shot (All)" = "#CC79A7"
)

shape_map <- c(
    "Gemini 3 Pro" = 2, # Open Triangle (Point Up)
    "Claude Opus 4.5" = 0, # Open Square
    "Claude Sonnet 4.5" = 1, # Open Circle
    "Gemini 2.5" = 5, # Open Diamond
    "GPT-5" = 6, # Open Triangle (Point Down)
    "o3" = 3 # Plus / Cross
)

# Create plot
p <- ggplot(plot_df, aes(x = Condition, y = Kappa, color = Condition, shape = Model_Clean)) +
    geom_pointrange(aes(ymin = Kappa_CI_Lower, ymax = Kappa_CI_Upper),
        size = 0.6, linewidth = 1.2, fatten = 4, alpha = 0.7
    ) +
    geom_point(aes(shape = Model_Clean, fill = Condition), size = 5, alpha = 0.9) +
    facet_wrap(~Model_Clean, ncol = 1, strip.position = "top") +
    scale_color_manual(values = color_map) +
    scale_fill_manual(values = color_map) +
    scale_shape_manual(values = shape_map) +
    theme_minimal(base_size = 14, base_family = "serif") +
    theme(
        legend.position = "none",
        panel.border = element_rect(color = "grey", fill = NA, linewidth = 0.5),
        axis.text.y = element_text(size = 12, face = "bold"),
        strip.text = element_text(face = "bold", size = 12),
        axis.text.x = element_text(size = 12, face = "bold")
    ) +
    labs(
        title = "Model Performance by Prompting Strategy",
        y = "Cohen's Kappa",
        x = NULL,
        caption = if (nrow(bracket_df) > 0) {
            "Significance determined by paired bootstrap test (R=1,000). * p < .05, ** p < .01, *** p < .001.\nNote: Overlapping 95% CIs do not preclude significant differences when using paired testing."
        } else {
            NULL
        }
    ) +
    coord_flip()

# Add significance brackets if computed
if (nrow(bracket_df) > 0) {
    cat("Adding", nrow(bracket_df), "significance brackets\n")

    # Map condition names to numeric positions
    cond_map <- c("Few Shot (All)" = 1, "Few Shot (3)" = 2, "One Shot" = 3, "Zero Shot" = 4)

    bracket_df <- bracket_df %>%
        mutate(
            x_start = cond_map[group1],
            x_end = cond_map[group2]
        )

    p <- p +
        geom_segment(
            data = bracket_df,
            aes(x = x_start, xend = x_end, y = y.position, yend = y.position),
            inherit.aes = FALSE, color = "black", linewidth = 0.5
        ) +
        geom_segment(
            data = bracket_df,
            aes(x = x_start, xend = x_start, y = y.position, yend = y.position - 0.01),
            inherit.aes = FALSE, color = "black", linewidth = 0.5
        ) +
        geom_segment(
            data = bracket_df,
            aes(x = x_end, xend = x_end, y = y.position, yend = y.position - 0.01),
            inherit.aes = FALSE, color = "black", linewidth = 0.5
        ) +
        geom_text(
            data = bracket_df,
            aes(x = (x_start + x_end) / 2, y = y.position + 0.005, label = label),
            inherit.aes = FALSE, size = 4, hjust = 0, vjust = 0.75
        )
}

# Save
ggsave(file.path(output_dir, "prompt_differences_faceted_plot.png"), p,
    width = 8, height = 10, bg = "white"
)

message("Prompt differences plot saved to: ", output_dir)
