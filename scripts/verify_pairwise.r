# Verification of pairwise test vs CI overlap
library(readr)
library(dplyr)

# Load data
boot_cis <- read_csv("results/stratified_467_chunks/bootstrap_cis.csv", show_col_types = FALSE)
pvals <- read_csv("results/stratified_467_chunks/pairwise_pvalues.csv", show_col_types = FALSE)

cat("=== Checking Claude: OneShot vs ZeroShot ===\n\n")

# Individual CIs
claude_zero <- boot_cis %>% filter(grepl("claude", Model), grepl("ZeroShot", Prompt))
claude_one <- boot_cis %>% filter(grepl("claude", Model), grepl("OneShot", Prompt))

cat("ZeroShot Kappa CI: [", sprintf("%.3f, %.3f", claude_zero$Kappa_CI_Lower, claude_zero$Kappa_CI_Upper), "]\n")
cat("OneShot Kappa CI:  [", sprintf("%.3f, %.3f", claude_one$Kappa_CI_Lower, claude_one$Kappa_CI_Upper), "]\n")
cat("Do CIs overlap?", claude_one$Kappa_CI_Lower < claude_zero$Kappa_CI_Upper, "\n\n")

# Pairwise test
comp <- pvals %>% filter(
    grepl("claude", Model),
    grepl("OneShot", Prompt1) | grepl("OneShot", Prompt2),
    grepl("ZeroShot", Prompt1) | grepl("ZeroShot", Prompt2)
)

cat("Pairwise bootstrap test:\n")
cat("  Observed difference:", sprintf("%.6f", comp$Kappa_Diff_Observed), "\n")
cat("  P-value:", sprintf("%.6f", comp$P_Value), "\n")
cat("  Significant:", comp$P_Value < 0.05, "\n\n")

cat("CONCLUSION:\n")
cat("CIs overlap, but pairwise test shows p <", comp$P_Value, "\n")
cat("This is CORRECT! Overlapping CIs do NOT imply non-significant difference.\n")
cat("The pairwise test accounts for correlation between measurements.\n")
