#!/usr/bin/env Rscript
# Build the evaluation-set prediction table
# =========================================
# One row per (Prompt, Model, teacher utterance) on the evaluation set (54 transcripts in
# results/SystemOne/splits.json). Reads saved outputs only; makes no model calls.
#   - Jev: data/outputs/SystemOne_Jev_Von/<Prompt>/<model>/probabilities.csv (with p_*)
#   - LLMs: results/Baseline_Experiments/bootstrap_data/*_joined.csv
# A missing prediction (utterance not returned or not parsed) is scored as "None", the
# same as a blank label, so every model is scored on the same utterances; Missing = TRUE
# marks them.
#
# Usage: Rscript scripts/system_one/build_eval_predictions.r

source("scripts/system_one/so_utils.r")

splits <- fromJSON(file.path(so_results_dir, "splits.json"))
chunk_dir <- "data/inputs/stratified_samples/representative_800_chunks"
gt <- read_csv("data/inputs/ground_truth/ground_truth_TalkMoves.csv", show_col_types = FALSE) %>%
    transmute(ID = as.integer(ID), Truth = normalize_move(TalkMove_truth))

# Evaluation-set teacher utterances, with transcript and fold
chunks <- setdiff(list.files(chunk_dir, pattern = "\\.json$"), splits$dev_chunks)
fold_of <- unlist(lapply(names(splits$eval_folds), function(f) setNames(rep(as.integer(f), length(splits$eval_folds[[f]])), splits$eval_folds[[f]])))
eval_utts <- bind_rows(lapply(chunks, function(ch) {
    u <- fromJSON(file.path(chunk_dir, ch))$utterances
    tibble(ID = as.integer(u$ID[u$Speaker == "T"]), Chunk = ch, Transcript = sub("_chunk_.*", "", ch))
})) %>%
    mutate(Fold = unname(fold_of[Transcript])) %>%
    inner_join(gt, by = "ID")
stopifnot(!anyNA(eval_utts$Fold), n_distinct(eval_utts$Transcript) == 54)
message("Evaluation set: ", nrow(eval_utts), " teacher utterances, ", n_distinct(eval_utts$Transcript), " transcripts")

prompts <- c("ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL")
p_cols <- paste0("p_", move_levels)

# Jev (and any other System One model dirs under the Condition A layout)
so_files <- Sys.glob("data/outputs/SystemOne_Jev_Von/TalkMoves_Teacher_*/*/probabilities.csv")
jev <- bind_rows(lapply(so_files, function(f) {
    read_csv(f, col_types = cols(.default = "c")) %>%
        transmute(
            Prompt = sub("TalkMoves_Teacher_", "", basename(dirname(dirname(f)))),
            Model = basename(dirname(f)), ID = as.integer(ID), Pred = normalize_move(choice),
            across(all_of(p_cols), as.numeric)
        )
}))

# LLMs from the paper's joined files
llm_files <- list.files("results/Baseline_Experiments/bootstrap_data", pattern = "_joined\\.csv$", full.names = TRUE)
llm <- bind_rows(lapply(llm_files, function(f) {
    key <- sub("^TalkMoves_Teacher_", "", sub("_joined\\.csv$", "", basename(f)))
    prompt <- prompts[startsWith(key, paste0(prompts, "_"))]
    prompt <- prompt[which.max(nchar(prompt))] # FewShot_ALL vs FewShot_3 are unambiguous, but be safe
    read_csv(f, col_types = cols(.default = "c")) %>%
        transmute(Prompt = prompt, Model = sub(paste0("^", prompt, "_"), "", key),
                  ID = as.integer(ID), Pred = normalize_move(TalkMove_Pred)) %>%
        distinct(ID, .keep_all = TRUE)
}))

preds <- bind_rows(jev, llm)
grid <- preds %>% distinct(Prompt, Model) %>% crossing(eval_utts)
out <- grid %>%
    left_join(preds, by = c("Prompt", "Model", "ID")) %>%
    mutate(Missing = is.na(Pred), Pred = ifelse(Missing, "None", Pred),
           Family = ifelse(startsWith(Model, "typesafe."), "System One", "LLM"),
           Prompt = factor(Prompt, levels = prompts)) %>%
    arrange(Prompt, Family, Model, ID)

dir.create(so_results_dir, showWarnings = FALSE, recursive = TRUE)
write_csv(out, file.path(so_results_dir, "eval_predictions.csv"))
out %>%
    group_by(Prompt, Model) %>%
    summarise(n = n(), missing = sum(Missing), .groups = "drop") %>%
    print(n = 40)
message("Saved: ", file.path(so_results_dir, "eval_predictions.csv"))
