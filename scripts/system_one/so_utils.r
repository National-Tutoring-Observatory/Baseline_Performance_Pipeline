# System One analysis helpers
# ===========================
# Metrics from confusion matrices, transcript-clustered bootstrap, and calibration
# (ECE equal-width / tie-preserving equal-mass, smooth ECE, Brier, AUROC).
# Sourced by the scripts in scripts/system_one/.

suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(tidyr)
    library(jsonlite)
})

move_levels <- c(
    "None", "Keeping Everyone Together",
    "Getting Students to Relate to Another's Ideas",
    "Restating", "Revoicing", "Pressing for Accuracy",
    "Pressing for Reasoning"
)
move_short <- c(
    "None" = "None", "Keeping Everyone Together" = "Together",
    "Getting Students to Relate to Another's Ideas" = "Relate",
    "Restating" = "Restating", "Revoicing" = "Revoicing",
    "Pressing for Accuracy" = "Accuracy", "Pressing for Reasoning" = "Reasoning"
)
so_results_dir <- "results/SystemOne"
so_seed <- 20261025

normalize_move <- function(x) {
    x <- gsub(intToUtf8(8217), "'", x)
    x <- gsub(intToUtf8(8216), "'", x)
    x <- gsub("Anothers", "Another's", x)
    ifelse(is.na(x) | x == "" | x == "NA" | tolower(x) == "none" | tolower(x) == "null", "None", x)
}

# ------------------------------------------------------------ metrics

#' 7x7 confusion matrix (rows = truth, cols = pred) as a length-49 count vector
confusion_vec <- function(truth, pred) {
    as.vector(table(factor(truth, levels = move_levels), factor(pred, levels = move_levels)))
}

#' Metrics from a 7x7 count matrix
metrics_from_cm <- function(cm) {
    n <- sum(cm)
    po <- sum(diag(cm)) / n
    pe <- sum(rowSums(cm) * colSums(cm)) / n^2
    tp <- diag(cm)
    prec <- ifelse(colSums(cm) > 0, tp / colSums(cm), 0)
    rec <- ifelse(rowSums(cm) > 0, tp / rowSums(cm), 0)
    f1 <- ifelse(prec + rec > 0, 2 * prec * rec / (prec + rec), 0)
    # Per-code binary kappa (one-vs-rest)
    bk <- sapply(seq_along(tp), function(k) {
        a <- tp[k]
        b <- colSums(cm)[k] - a
        c <- rowSums(cm)[k] - a
        d <- n - a - b - c
        po_k <- (a + d) / n
        pe_k <- ((a + b) * (a + c) + (c + d) * (b + d)) / n^2
        if (pe_k == 1) NA_real_ else (po_k - pe_k) / (1 - pe_k)
    })
    list(
        accuracy = po, kappa = (po - pe) / (1 - pe),
        macro_precision = mean(prec), macro_recall = mean(rec), macro_f1 = mean(f1),
        precision = setNames(prec, move_levels), recall = setNames(rec, move_levels),
        f1 = setNames(f1, move_levels), binary_kappa = setNames(bk, move_levels)
    )
}

#' Flatten metrics_from_cm() output to a named numeric vector (for bootstrapping)
metric_vector <- function(cm) {
    m <- metrics_from_cm(cm)
    c(
        accuracy = m$accuracy, kappa = m$kappa, macro_precision = m$macro_precision,
        macro_recall = m$macro_recall, macro_f1 = m$macro_f1,
        setNames(m$binary_kappa, paste0("bk__", move_levels)),
        setNames(m$precision, paste0("prec__", move_levels)),
        setNames(m$recall, paste0("rec__", move_levels)),
        setNames(m$f1, paste0("f1__", move_levels))
    )
}

# ------------------------------------------------------------ clustered bootstrap

#' Bootstrap weight matrix: R x T counts of how often each transcript is drawn.
#' Shared across all models/prompts so comparisons are paired.
cluster_weights <- function(transcripts, R = 1000, seed = so_seed) {
    set.seed(seed)
    tx <- sort(unique(transcripts))
    W <- t(replicate(R, tabulate(sample.int(length(tx), length(tx), replace = TRUE), length(tx))))
    colnames(W) <- tx
    W
}

#' Per-transcript confusion counts: T x 49 matrix (rows ordered as colnames(W))
transcript_cms <- function(df, tx_order) {
    m <- df %>%
        group_by(Transcript) %>%
        group_map(~ confusion_vec(.x$Truth, .x$Pred), .keep = TRUE)
    names(m) <- df %>% group_by(Transcript) %>% group_keys() %>% pull(Transcript)
    out <- matrix(0, nrow = length(tx_order), ncol = 49, dimnames = list(tx_order, NULL))
    out[names(m), ] <- do.call(rbind, m)
    out
}

#' Bootstrap replicate metric matrix (R x metrics) from transcript counts and weights
boot_metrics <- function(tcm, W) {
    agg <- W %*% tcm
    t(apply(agg, 1, function(v) metric_vector(matrix(v, 7, 7))))
}

# ------------------------------------------------------------ calibration

#' Equal-width bins over [0, 1]
bins_equal_width <- function(p, n_bins = 15) {
    pmin(floor(p * n_bins), n_bins - 1) + 1
}

#' Equal-mass bins that never split tied values: each distinct value goes to the bin
#' containing the midpoint of its block in the sorted order. Empty bins are dropped.
bins_equal_mass <- function(p, n_bins = 15) {
    n <- length(p)
    p <- round(p, 6) # Jev returns float noise such as 0.9400000000000001; treat as ties
    u <- sort(unique(p))
    cnt <- tabulate(match(p, u), length(u))
    mid <- cumsum(cnt) - cnt / 2
    b <- pmin(floor(mid / (n / n_bins)), n_bins - 1) + 1
    b <- match(b, sort(unique(b)))
    b[match(p, u)]
}

#' ECE = sum_b (n_b / n) |acc_b - conf_b|
ece <- function(conf, correct, bins) {
    d <- tibble(conf, correct, bins) %>%
        group_by(bins) %>%
        summarise(n = n(), conf = mean(conf), acc = mean(correct), .groups = "drop")
    sum(d$n / sum(d$n) * abs(d$acc - d$conf))
}

#' Reliability table for plotting
reliability_table <- function(conf, correct, bins) {
    tibble(conf, correct, bins) %>%
        group_by(bins) %>%
        summarise(
            n = n(), mean_conf = mean(conf), accuracy = mean(correct),
            lo = qbeta(0.025, sum(correct) + 0.5, n - sum(correct) + 0.5),
            hi = qbeta(0.975, sum(correct) + 0.5, n - sum(correct) + 0.5),
            .groups = "drop"
        )
}

#' Smooth ECE (Blasiewicz et al. 2023): kernel-smoothed residuals with a reflected
#' Gaussian kernel on [0, 1]; bandwidth is the fixed point smECE(sigma) = sigma.
smooth_ece <- function(conf, correct, grid_n = 1001) {
    t <- seq(0, 1, length.out = grid_n)
    # Aggregate residuals by distinct confidence value (exact; Jev has <= ~101 values)
    key <- round(conf, 6)
    u <- sort(unique(key))
    r <- as.vector(tapply(correct - conf, factor(match(key, u), levels = seq_along(u)), sum))
    n <- length(conf)
    sm_at <- function(sigma) {
        k <- function(x) dnorm(outer(t, x, "-"), sd = sigma)
        K <- k(u) + k(-u) + k(2 - u) # reflection at 0 and 1
        sum(abs(K %*% r) / n) * (t[2] - t[1])
    }
    lo <- 1e-3
    hi <- 1
    for (i in 1:30) {
        mid <- (lo + hi) / 2
        if (sm_at(mid) > mid) lo <- mid else hi <- mid
    }
    sm_at((lo + hi) / 2)
}

#' AUROC of a score for discriminating positives (rank-based, ties averaged)
auroc <- function(score, positive) {
    r <- rank(score)
    n1 <- sum(positive)
    n0 <- sum(!positive)
    (sum(r[positive]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' Multiclass Brier score: mean over utterances of sum_k (p_k - y_k)^2
brier_multiclass <- function(P, truth) {
    Y <- outer(truth, colnames(P), "==") * 1
    mean(rowSums((P - Y)^2))
}
