"""Test-mode diagnostic: is Von's collapse on the per-chunk request a formatting issue?

Variants on the same test chunk (all 20 teacher utterances):
  chunk_json   - the Jev request as sent (JSON state, question names target by ID)
  chunk_text   - same, but the dialogue rendered as plain "ID [T]: sentence" lines
  marked_text  - per-utterance request: plain-text context with the target line marked
  target_only  - per-utterance request: state is just the target sentence
  shuffled     - chunk_text with option order reversed (checks position bias)
"""
import csv
import json
import os

os.environ.setdefault("VON_DEVICE", "mps")
import von

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data/outputs/SystemOne_Jev_Von/test_mode")
CHUNK = "TalkBack.Year1.Benson.Fall.121019_chunk_16_37.json"


def main():
    body = json.load(open(os.path.join(OUT, "test_request.json")))
    utts = json.load(open(os.path.join(ROOT, "data/inputs/stratified_samples/representative_800_chunks", CHUNK)))["utterances"]
    gt = {int(r["ID"]): (r["TalkMove_truth"] or "None") for r in csv.DictReader(open(os.path.join(ROOT, "data/inputs/ground_truth/ground_truth_TalkMoves.csv")))}
    criteria = next(iter(body["questions"].values()))["criteria"]
    teacher = [u for u in utts if u["Speaker"] == "T"]
    lines = [f"{u['ID']} [{u['Speaker']}]: {u['Sentence']}" for u in utts]

    def q(u, crit=criteria):
        return {"type": "choice", "instructions": f"Which Talk Move is teacher utterance ID {u['ID']} ('{u['Sentence']}')?", "criteria": crit}

    def per_utt(state_fn):
        out = {}
        for u in teacher:
            r = von.system_one(state=state_fn(u), questions={"x": {"type": "choice", "instructions": "Which Talk Move is the teacher's target utterance?", "criteria": criteria}})
            out[str(u["ID"])] = r.answers["x"]
        return out

    variants = {
        "chunk_json": lambda: von.system_one(state=body["state"], questions=body["questions"]).answers,
        "chunk_text": lambda: von.system_one(state="\n".join(lines), questions={str(u["ID"]): q(u) for u in teacher}).answers,
        "marked_text": lambda: per_utt(lambda t: "\n".join((">>> TARGET " if u["ID"] == t["ID"] else "") + l for u, l in zip(utts, lines))),
        "target_only": lambda: per_utt(lambda t: f"Teacher: {t['Sentence']}"),
        "shuffled": lambda: von.system_one(state="\n".join(lines), questions={str(u["ID"]): q(u, dict(reversed(list(criteria.items())))) for u in teacher}).answers,
    }
    summary = {}
    for name, run in variants.items():
        ans = run()
        preds = [ans[str(u["ID"])].choice for u in teacher]
        maxp = [max(ans[str(u["ID"])].probabilities.values()) for u in teacher]
        summary[name] = {
            "correct": sum(p == gt[u["ID"]] for p, u in zip(preds, teacher)),
            "distinct_labels": sorted(set(preds)),
            "mean_max_p": round(sum(maxp) / len(maxp), 3),
        }
        print(name, json.dumps(summary[name]))
    json.dump(summary, open(os.path.join(OUT, "diag_von_format.json"), "w"), indent=2)


if __name__ == "__main__":
    main()
