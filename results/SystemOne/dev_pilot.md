# Dev-set pilot (design step, not a result)

Jev `typesafe/jev-1.14-20261014`, 58 dev chunks / 1,265 teacher utterances, run 2026-10-25. Dev transcripts are excluded from every reported metric. Outputs: `data/outputs/SystemOne_Jev_Von/dev_pilot/`.

## 1. Few-shot example placement

| Condition | κ, examples in state | κ, examples in question | Input tokens (state / question) |
|---|---|---|---|
| OneShot | 0.404 | 0.426 | 405k / 523k |
| FewShot_3 | 0.431 | 0.453 | 419k / 834k |
| FewShot_ALL | 0.471 | 0.467 | 433k / 1,138k |
| **Mean** | **0.435** | **0.449** | |

ZeroShot reference (no examples): κ 0.393.

The pre-registered rule picks the placement with the higher mean κ, with a tie margin of 0.01. The gap is 0.014, so the choice is **question**. Question placement costs up to 2.6× the input tokens; the full FewShot_ALL run is about $0.40.

## 2. Per-chunk questions vs. per-utterance requests with a marked target

10 seeded dev chunks (204 teacher utterances), ZeroShot.

- Label agreement between the two designs: **96.6%**.
- κ vs. ground truth: per-chunk 0.376, per-utterance with `target_id` 0.395.

Per-chunk questions (one request per chunk) give nearly the same labels as per-utterance requests, at about 1/20 of the request count. The main design is unchanged.
