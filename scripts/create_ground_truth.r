#!/usr/bin/env Rscript
# Create Ground Truth File From Browder Data
# ===========================================
# Converts numeric Tag codes to TalkMove labels

library(dplyr)
library(readr)

# Define the mapping from numeric tags to TalkMove labels
# Based on the Open-Source Talk Moves Codebook
tag_to_talkmove <- c(
    "0" = "", # No talk move / None
    "1" = "Keeping Everyone Together",
    "2" = "Getting Students to Relate to Another's Ideas",
    "3" = "Restating",
    "4" = "Revoicing",
    "5" = "Pressing for Accuracy",
    "6" = "Pressing for Reasoning"
)

# Note: The data shows Tag values like:
# 0 = No talk move (most common)
# 1 = Keeping Everyone Together
# 2 = Getting Students to Relate to Another's Ideas
# 3 = Restating
# 4 = Pressing for Accuracy
# 5 = Pressing for Reasoning
# 6 = Revoicing

# Read input data
message("Loading test_data_63.csv...")
data <- read_csv("data/inputs/ground_truth/test_data_63.csv", col_types = cols(.default = "c"))

message("Loaded ", nrow(data), " rows")

# Filter to teacher utterances only (Speaker = T)
teacher_data <- data %>%
    filter(Speaker == "T")

message("Teacher utterances: ", nrow(teacher_data))

# Create ground truth with TalkMove labels
ground_truth <- teacher_data %>%
    mutate(
        ID = as.integer(ID),
        Turn = as.integer(Turn),
        Tag = as.character(Tag),
        TalkMove_truth = case_when(
            Tag == "0" ~ "",
            Tag == "1" ~ "Keeping Everyone Together",
            Tag == "2" ~ "Getting Students to Relate to Another's Ideas",
            Tag == "3" ~ "Restating",
            Tag == "4" ~ "Revoicing",
            Tag == "5" ~ "Pressing for Accuracy",
            Tag == "6" ~ "Pressing for Reasoning",
            TRUE ~ ""
        )
    ) %>%
    select(ID, Transcript, Turn, Speaker, Sentence, TalkMove_truth)

message("Ground truth created with ", nrow(ground_truth), " rows")

# Summary of TalkMove distribution
message("\nTalkMove Distribution:")
print(table(ground_truth$TalkMove_truth, useNA = "ifany"))

# Save to ground_truth directory
output_path <- "data/inputs/ground_truth/ground_truth_TalkMoves.csv"
write_csv(ground_truth, output_path)

message("\nGround truth saved to: ", output_path)

# Count non-empty TalkMoves
n_with_moves <- sum(ground_truth$TalkMove_truth != "", na.rm = TRUE)
message(
    "Utterances with TalkMoves: ", n_with_moves, " (",
    round(100 * n_with_moves / nrow(ground_truth), 1), "%)"
)
