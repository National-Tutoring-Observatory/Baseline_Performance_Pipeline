library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(fs)

# Config
input_dir <- "results/Baseline_Experiments/bootstrap_data"
output_dir <- "results/Baseline_Experiments"

# Get all joined files
files <- dir_ls(input_dir, glob = "*_joined.csv")

# Parse filenames to extract metadata
file_info <- data.frame(path = as.character(files), stringsAsFactors = FALSE) %>%
    mutate(
        filename = basename(path),
        # Remove suffix
        base = str_remove(filename, "_joined\\.csv"),
        # Split into Prompt and Model
        # Known prompts: "TalkMoves_Teacher_ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL"
        # Everything after the known prompt prefix is the model
        Prompt = case_when(
            str_detect(base, "TalkMoves_Teacher_ZeroShot") ~ "TalkMoves_Teacher_ZeroShot",
            str_detect(base, "TalkMoves_Teacher_OneShot") ~ "TalkMoves_Teacher_OneShot",
            str_detect(base, "TalkMoves_Teacher_FewShot_3") ~ "TalkMoves_Teacher_FewShot_3",
            str_detect(base, "TalkMoves_Teacher_FewShot_ALL") ~ "TalkMoves_Teacher_FewShot_ALL",
            TRUE ~ "Unknown"
        ),
        Model = str_remove(base, paste0(Prompt, "_"))
    )

# Process each prompt group
prompts <- unique(file_info$Prompt)

for (p in prompts) {
    message("Consolidating predictions for prompt: ", p)

    prompt_files <- file_info %>% filter(Prompt == p)

    # Initialize with the first model to establish the base (ID, Sentence, Truth)
    # We use the first one found
    base_file <- prompt_files$path[1]
    base_df <- read_csv(base_file, show_col_types = FALSE) %>%
        select(ID, Transcript, Turn, Sentence, TalkMove_Truth)

    # Check for duplicate IDs in base (using distinct key info)
    base_df <- base_df %>% distinct(ID, .keep_all = TRUE)

    # Now join all models
    final_df <- base_df

    for (i in 1:nrow(prompt_files)) {
        m_name <- prompt_files$Model[i]
        f_path <- prompt_files$path[i]

        # Read model data
        m_df <- read_csv(f_path, show_col_types = FALSE) %>%
            select(ID, TalkMove_Pred) %>%
            rename(!!sym(m_name) := TalkMove_Pred) %>%
            # Deduplicate by ID to avoid explosion (taking first prediction if dupes exist)
            distinct(ID, .keep_all = TRUE)

        # Join
        final_df <- left_join(final_df, m_df, by = "ID")
    }

    # Save
    out_file <- file.path(output_dir, paste0(p, "_consolidated_predictions.csv"))
    write_csv(final_df, out_file)
    message("  Saved to: ", out_file)
}
