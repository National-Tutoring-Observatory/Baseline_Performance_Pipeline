"""Fix the dev / evaluation split and grouped CV folds before any full model run.

Dev set: 6 transcripts, drawn with a fixed seed, rejection-sampled until every class has
at least MIN_DEV_POS positives. Evaluation set: the other transcripts, assigned to 5 folds
by a seeded greedy balancer on rare-class counts. Writes results/SystemOne/splits.json.
"""
import csv
import glob
import json
import os
import random
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHUNK_DIR = os.path.join(ROOT, "data/inputs/stratified_samples/representative_800_chunks")
GT = os.path.join(ROOT, "data/inputs/ground_truth/ground_truth_TalkMoves.csv")
OUT = os.path.join(ROOT, "results/SystemOne/splits.json")
SEED = 20261025
N_DEV = 6
MIN_DEV_POS = 3
N_FOLDS = 5
CLASSES = [
    "Keeping Everyone Together", "Getting Students to Relate to Another's Ideas", "Restating",
    "Pressing for Accuracy", "Revoicing", "Pressing for Reasoning", "None",
]
RARE = ["Getting Students to Relate to Another's Ideas", "Restating", "Revoicing", "Pressing for Reasoning"]


def main():
    gt = {}
    with open(GT, newline="") as f:
        for row in csv.DictReader(f):
            gt[int(row["ID"])] = (row["TalkMove_truth"] or "None").replace("’", "'")

    chunks_by_tx = defaultdict(list)
    counts = defaultdict(Counter)
    n_teacher = 0
    for path in sorted(glob.glob(os.path.join(CHUNK_DIR, "*.json"))):
        name = os.path.basename(path)
        tx = name.split("_chunk_")[0]
        chunks_by_tx[tx].append(name)
        for u in json.load(open(path))["utterances"]:
            if u["Speaker"] == "T":
                n_teacher += 1
                counts[tx][gt.get(u["ID"], "None")] += 1

    txs = sorted(chunks_by_tx)
    rng = random.Random(SEED)
    for attempt in range(1, 10001):
        dev = sorted(rng.sample(txs, N_DEV))
        dev_counts = sum((counts[t] for t in dev), Counter())
        if all(dev_counts[c] >= MIN_DEV_POS for c in CLASSES):
            break
    else:
        raise SystemExit("No dev draw met the class minimum")

    # Greedy balance: largest rare-class transcripts first, each to the fold with the
    # smallest running rare-class total (ties broken by seeded shuffle order).
    evals = [t for t in txs if t not in dev]
    rng.shuffle(evals)
    evals.sort(key=lambda t: -sum(counts[t][c] for c in RARE))
    folds = [[] for _ in range(N_FOLDS)]
    fold_counts = [Counter() for _ in range(N_FOLDS)]
    for t in evals:
        k = min(range(N_FOLDS), key=lambda i: (sum(fold_counts[i][c] for c in RARE), len(folds[i])))
        folds[k].append(t)
        fold_counts[k] += counts[t]

    out = {
        "seed": SEED,
        "rule": f"dev = {N_DEV} transcripts, seeded rejection sampling until every class has >= {MIN_DEV_POS} "
                f"teacher-utterance positives; eval folds = greedy balance on rare-class counts",
        "dev_draw_attempts": attempt,
        "n_transcripts": len(txs), "n_chunks": sum(map(len, chunks_by_tx.values())), "n_teacher_utterances": n_teacher,
        "dev_transcripts": dev,
        "dev_chunks": sorted(c for t in dev for c in chunks_by_tx[t]),
        "dev_class_counts": {c: dev_counts[c] for c in CLASSES},
        "eval_folds": {str(i + 1): sorted(f) for i, f in enumerate(folds)},
        "eval_fold_class_counts": {str(i + 1): {c: fold_counts[i][c] for c in CLASSES} for i in range(N_FOLDS)},
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w"), indent=2)
    print(json.dumps({k: v for k, v in out.items() if k not in ("dev_chunks", "eval_folds")}, indent=2))
    print("dev chunks:", len(out["dev_chunks"]))


if __name__ == "__main__":
    main()
