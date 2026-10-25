"""Quick 7-class accuracy / Cohen's kappa for probabilities.csv files (design checks only;
reported metrics come from the R analysis). Usage: score_quick.py <probabilities.csv> ..."""
import csv
import os
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def ground_truth():
    with open(os.path.join(ROOT, "data/inputs/ground_truth/ground_truth_TalkMoves.csv"), newline="") as f:
        return {r["ID"]: (r["TalkMove_truth"] or "None").replace("’", "'") for r in csv.DictReader(f)}


def kappa(pairs):
    n = len(pairs)
    po = sum(a == b for a, b in pairs) / n
    ca, cb = Counter(a for a, _ in pairs), Counter(b for _, b in pairs)
    pe = sum(ca[k] * cb[k] for k in ca) / n ** 2
    return po, (po - pe) / (1 - pe)


def score(path, gt, ids=None):
    rows = {r["ID"]: r["choice"] for r in csv.DictReader(open(path))}
    pairs = [(gt[i], c) for i, c in rows.items() if ids is None or i in ids]
    return len(pairs), *kappa(pairs)


if __name__ == "__main__":
    gt = ground_truth()
    for path in sys.argv[1:]:
        n, acc, k = score(path, gt)
        print(f"n={n:5d} acc={acc:.3f} kappa={k:.3f}  {os.path.relpath(path, ROOT)}")
