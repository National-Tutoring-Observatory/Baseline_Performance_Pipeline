#!/usr/bin/env Rscript
# Jev confusion heatmaps in the style of the paper's figures
# ==========================================================
# Matches results/Analysis/confusion_heatmaps/confusion_*.png: row-normalized (% of each
# human label), orange-to-red scale, predicted labels on top, labels shown when >= 2%.
#
# Outputs (results/SystemOne/figures/, each as .png and .jpg):
#   confusion_jev_FewShot_ALL   single heatmap, directly comparable to the paper's panels
#   confusion_jev               the four prompt conditions side by side
#
# Usage: Rscript scripts/system_one/confusion_heatmaps_jev.r

source("scripts/system_one/so_utils.r")
suppressPackageStartupMessages({
    library(ggplot2)
    library(patchwork)
})

jev_main <- "typesafe.jev-1.14-20261014"
fig_dir <- file.path(so_results_dir, "figures")
prompts <- c("ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL")

# Axis order and short labels as in the paper's heatmaps
pred_order <- c("Keeping Everyone Together", "Getting Students to Relate to Another's Ideas", "Restating",
                "Pressing for Accuracy", "Revoicing", "Pressing for Reasoning", "None")
paper_short <- c(
    "Keeping Everyone Together" = "Keep Together",
    "Getting Students to Relate to Another's Ideas" = "Relate Ideas",
    "Restating" = "Restating", "Revoicing" = "Revoicing",
    "Pressing for Accuracy" = "Press Accuracy", "Pressing for Reasoning" = "Press Reasoning",
    "None" = "None"
)

ev <- read_csv(file.path(so_results_dir, "eval_predictions.csv"), show_col_types = FALSE) %>%
    filter(!Missing, Model == jev_main)

heatmap <- function(d, title, show_y = TRUE, base = 20) {
    cm <- d %>%
        count(Truth, Pred) %>%
        complete(Truth = move_levels, Pred = move_levels, fill = list(n = 0)) %>%
        group_by(Truth) %>%
        mutate(Pct = 100 * n / max(sum(n), 1)) %>%
        ungroup() %>%
        mutate(Label = ifelse(Pct >= 1.5, sprintf("%.0f%%", Pct), ""),
               # y runs bottom-up, so None ends on top and the diagonal rises left to right
               Truth = factor(paper_short[Truth], levels = paper_short[pred_order]),
               Pred = factor(paper_short[Pred], levels = paper_short[pred_order]))
    ggplot(cm, aes(Pred, Truth, fill = Pct)) +
        geom_tile(color = "white", linewidth = 0.8) +
        geom_text(aes(label = Label), size = base * 0.3, color = "black") +
        scale_fill_gradientn(colors = c("#FED6A0", "#FDB863", "#E0613F", "#B2182B"),
                             limits = c(0, 100), name = "Row %") +
        scale_x_discrete(position = "top") +
        labs(title = title, x = "Predicted", y = if (show_y) "Ground Truth" else NULL) +
        theme_minimal(base_size = base) +
        theme(
            axis.text.x = element_text(angle = 45, hjust = 0, vjust = 0, size = base * 0.8),
            axis.text.y = if (show_y) element_text(size = base * 0.8) else element_blank(),
            axis.title = element_text(face = "bold"),
            plot.title = element_text(face = "bold", hjust = 0.5, size = base * 1.1),
            panel.grid = element_blank()
        ) +
        coord_fixed()
}

# Single panel, comparable to the paper's FewShot_ALL heatmaps
save_fig(file.path(fig_dir, "confusion_jev_FewShot_ALL"),
         heatmap(ev %>% filter(Prompt == "FewShot_ALL"), "Jev 1.14 (FewShot_ALL)"),
         width = 10, height = 8.75)

# All four prompt conditions
panels <- lapply(seq_along(prompts), function(i) {
    heatmap(ev %>% filter(Prompt == prompts[i]), prompts[i], show_y = i == 1, base = 14)
})
combined <- wrap_plots(panels, nrow = 1, guides = "collect") +
    plot_annotation(title = "Jev 1.14 confusion matrices (evaluation set)",
                    theme = theme(plot.title = element_text(face = "bold", hjust = 0.5, size = 18)))
save_fig(file.path(fig_dir, "confusion_jev"), combined, width = 22, height = 6.5)
message("Saved confusion heatmaps to ", fig_dir)
