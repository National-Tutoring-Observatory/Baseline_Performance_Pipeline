library(jsonlite)
library(readr)
library(dplyr)
library(stringr)

# Paths
base_output <- "data/outputs"
targets <- c("full_sample", "stratified_sample")

# Map old prompt names to new ZeroShot variants
prompt_map <- c(
    "TalkMoves_Teacher_OneShot" = "TalkMoves_Teacher_ZeroShot_Var2",
    "TalkMoves_Teacher_FewShot_3" = "TalkMoves_Teacher_ZeroShot_Var3",
    "TalkMoves_Teacher_FewShot_ALL" = "TalkMoves_Teacher_ZeroShot_Var4"
    # Keeping TalkMoves_Teacher_ZeroShot as is (or implying Var1)
)

relabel_directory <- function(target_dir) {
    full_path <- file.path(base_output, target_dir)
    if (!dir.exists(full_path)) {
        cat("Directory not found:", full_path, "\n")
        return()
    }
    cat("Processing:", full_path, "\n")

    # 1. Rename Folders
    dirs <- list.dirs(full_path, recursive = FALSE, full.names = FALSE)
    for (old_name in names(prompt_map)) {
        if (old_name %in% dirs) {
            new_name <- prompt_map[[old_name]]
            old_path <- file.path(full_path, old_name)
            new_path <- file.path(full_path, new_name)

            if (dir.exists(new_path)) {
                cat("  Skipping rename: Target ", new_name, " already exists.\n")
            } else {
                file.rename(old_path, new_path)
                cat("  Renamed:", old_name, "->", new_name, "\n")
            }
        }
    }

    # 2. Update run_metadata.json
    meta_path <- file.path(full_path, "run_metadata.json")
    if (file.exists(meta_path)) {
        meta <- fromJSON(meta_path)

        # Update prompts list
        meta$prompts <- ifelse(meta$prompts %in% names(prompt_map),
            prompt_map[meta$prompts],
            meta$prompts
        )

        # Update specific_prompts if relevant (though they are filenames)
        # Assuming filenames didn't change, just the logical prompt names in the pipeline

        write_json(meta, meta_path, pretty = TRUE, auto_unbox = TRUE)
        cat("  Updated run_metadata.json\n")
    }

    # 3. Update analysis_results.csv
    csv_path <- file.path(full_path, "analysis_results.csv")
    if (file.exists(csv_path)) {
        df <- read_csv(csv_path, show_col_types = FALSE)

        # Iterate over prompt map
        for (old_p in names(prompt_map)) {
            new_p <- prompt_map[[old_p]]
            # Replace full matches in Prompt column
            df$Prompt[df$Prompt == old_p] <- new_p
        }

        write_csv(df, csv_path)
        cat("  Updated analysis_results.csv\n")
    }
}

# Execute
for (t in targets) {
    relabel_directory(t)
}
cat("Done.\n")
