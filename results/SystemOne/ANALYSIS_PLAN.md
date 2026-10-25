# System One replication: analysis plan

Fixed on 2026-10-25, before any full run. Changes after this commit are listed at the bottom with a date and reason.

## Models
- **Jev** `typesafe/jev-1.14-20261014` via OpenRouter (`/api/v1/systemone`). All conditions.
- **Jev** `typesafe/jev-1.13-20260917`: Condition A ZeroShot only.
- **Von** (`wfzyx/von` @ `3a34cbd`, final weights 1.2, archived 2026-10-19): **on hold.** In test mode it collapsed to one label when the state had dialogue context (κ ≈ 0) and was near chance with target-only states.
- **LLMs:** the six models in `data/outputs/Baseline_Experiments/`, with metrics recomputed on the evaluation set from the existing raw outputs.

## Request design
- One request per chunk. State = the chunk dialogue as JSON (ID, Turn, Speaker, Sentence), plus the workflow and clarification guidance from the prompt JSON. One `choice` question per teacher utterance, keyed by utterance ID. Each question names its target by ID and quotes its text.
- 7 options: the six moves (ground-truth strings, straight apostrophe) plus `None`. Each option's description comes from `moveDefinitions`. Option order is the order of `allowedMoves`, with None last.
- Few-shot examples (`moveExamples`) are placed in the state or the question text, decided by the dev pilot (below). The same placement is used for every few-shot condition.
- A chunk is split into multiple requests when it exceeds 100 questions. Splits are logged.

## Splits (`results/SystemOne/splits.json`, seed 20261025)
- **Dev:** 6 transcripts / 58 chunks. Used only for design decisions and never in a reported metric.
- **Evaluation:** 54 transcripts in 5 grouped folds. Every reported comparison uses exactly these utterances.
- **Appendix:** paper-comparable full-sample (467 chunks) numbers for unfitted Condition A, labeled as including dev.
- Anything fitted (temperature, None threshold, gating threshold, decomposition LR, feature standardization) is fitted on 4 folds and predicted on the 5th. Metrics are computed on the pooled out-of-fold predictions. The spread across folds is reported too.

## Dev-set design decisions (decision rules fixed in advance)
1. **Example placement:** run OneShot, FewShot_3 and FewShot_ALL on all 58 dev chunks with examples in the state vs. in the questions. Choose the placement with the higher mean 7-class κ across the three conditions. If the difference is < 0.01, choose state (cheaper).
2. **Per-chunk vs. per-utterance:** on 10 seeded dev chunks (ZeroShot), compare per-chunk questions with per-utterance requests whose state marks the target (`target_id`). Report label agreement and κ for each. This is reported as a design check and does not change the main design.
3. **Decomposition wording:** the 6 move `noul` questions and 6 indicator questions use the wording from the spec as given. No wording search.

## Conditions
- **A (direct):** the 4 prompt conditions on all 467 chunks.
- **B (decomposition):** per teacher utterance, 6 move `noul` questions ("Is teacher utterance ID n ('…') an instance of <move>: <definition>?") and 6 indicators (word-for-word repeat; repeat with changed wording; asks for explanation or justification; asks for a correct answer, procedure or math term; directs students to respond to a classmate; checks listening or following). At most 100 questions per request, with whole utterances kept together. Combined as:
  - (i) argmax over the 6 move probabilities, with None if the max is below a threshold. The threshold is chosen in-fold to maximize 7-class κ over a 0.01 grid.
  - (ii) L2 multinomial LR on all 12 noul probabilities.
  - (iii) the same LR on deterministic repetition features only.
  - (iv) the same LR on (ii) + (iii) features.
  - The LR settings are fixed in advance: λ via `cv.glmnet` within the training folds (grouped by transcript, lambda.1se), inverse-frequency class weights, and in-fold standardization.
- **Deterministic repetition features**, computed against the most recent prior student turn and as the max over the last 3 student turns:
  - token Jaccard;
  - containment (|T∩S|/|S|);
  - normalized word-level edit distance;
  - longest common substring length (in words);
  - exact copy;
  - near-exact copy (normalized edit distance ≤ 0.2).
  - Tokens are lowercased with punctuation stripped.
- **C (robustness)** on 50 seeded evaluation chunks, ZeroShot:
  - shuffled option order (one seeded permutation per question);
  - options renamed to letters A–G with descriptions kept;
  - 5 repeats of the base requests.
  - Reported: argmax flip rate vs. the Condition A run, and the mean and 95th-percentile absolute change in the probability of the A-run label.
- **Run-to-run noise:** the full ZeroShot condition is repeated on a separate day with the same pinned version. Reported: κ, per-code κ, ECE, the difference between runs, and the label-flip rate. The difference is treated as a noise floor.

## Metrics
- 7-class accuracy and Cohen's κ (blank/NA → None); macro and per-code precision, recall and F1; per-code binary κ; confusion matrices.
- **CIs:** 95% transcript-clustered bootstrap (R = 1,000, resampling evaluation transcripts). Paired tests between prompt conditions, Jev vs. LLMs, and A vs. B variants use the same resamples. The appendix uses the paper's existing bootstrap scripts unchanged for comparability.
- **Calibration** against human labels, both top-label (7-class) and per-code one-vs-rest. Reported for each:
  - **ECE, equal-width:** 15 bins.
  - **ECE, equal-mass:** 15 target bins. Each distinct probability value is assigned to exactly one bin, never split, so bins merge where ties force it. The realized bin count is reported.
  - **Binning-free metrics:** Brier score and smooth ECE (Gaussian-kernel, Błasiewicz et al. 2023).
  - **Temperature scaling:** per question type, fitted in-fold on log-probabilities. Probabilities of exactly 0 are floored at 0.005, half the rounding unit. ECE is reported before and after.
- **Confidence-gated automation:** for each target error (5%, 10%), choose in-fold the lowest max-probability threshold whose in-fold error among automated items is ≤ target. Report pooled out-of-fold automation rate, realized error, and per-code breakdown.
  - LLM comparison gate: k-of-6 agreement on the modal label, and leave-one-out k-of-5 for each model, with thresholds chosen in-fold the same way.
  - One figure plots automation rate vs. realized error for all gates.
- **Error overlap:** the rate at which Jev's errors match Opus, Gemini 2.5 Pro and Gemini 3 Pro errors (same wrong label), and Jev's max-probability on the `universal_failures.csv` items vs. all other items (Wilcoxon test).
- **Cost and latency:** input tokens, `usage.cost`, median and p95 latency per condition, and cost per correct label.

## Changes after commit
(none)
