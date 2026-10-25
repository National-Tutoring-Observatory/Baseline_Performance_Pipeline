"""Run System One conditions for Jev (or Von) over a set of chunks.

Condition A (direct choice) writes, per chunk, `<chunk>.json_raw.txt` in the {"records": [...]}
format that scripts/functions/json_parser.r parses, so analyze_results.r runs unchanged, plus
probabilities.csv (full 7-option vector per utterance). Condition B (decomposition nouls)
writes noul_probabilities.csv (one row per utterance x question). Every request/response goes
to calls.jsonl. Resumable: chunks with a done-marker (raw file) are skipped.

Usage (from scripts/system_one/):
  uv run python run_system_one.py --model jev --prompt ZeroShot --chunks dev:5 --tag test_mode
  uv run python run_system_one.py --model jev --condition B --chunks all --tag Condition_B
  uv run python run_system_one.py --model jev --variant letters --chunks robust:50 --tag Condition_C/letters
"""
import argparse
import concurrent.futures as cf
import csv
import json
import os
import random
import string
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CFG = yaml.safe_load(open(os.path.join(ROOT, "config/system_one_config.yaml")))
MOVES = [
    "Keeping Everyone Together", "Getting Students to Relate to Another's Ideas", "Restating",
    "Pressing for Accuracy", "Revoicing", "Pressing for Reasoning",
]
OPTIONS = MOVES + ["None"]
PROB_COLS = ["ID", "chunk", "prompt", "model", "variant", "request_id", "split_part"] + [f"p_{o}" for o in OPTIONS] + [
    "choice", "confidence", "latency_ms", "input_tokens", "request_cost", "n_questions", "state_bytes", "timestamp"]
NOUL_COLS = ["ID", "chunk", "question", "p", "model", "request_id", "split_part", "latency_ms", "input_tokens",
             "request_cost", "n_questions", "state_bytes", "timestamp"]
INDICATORS = {
    "ind_repeat_exact": "Does teacher utterance ID {id} ('{s}') repeat a prior student utterance word for word?",
    "ind_repeat_changed": "Does teacher utterance ID {id} ('{s}') repeat a prior student utterance with added or changed wording?",
    "ind_explain": "Does teacher utterance ID {id} ('{s}') ask for an explanation or justification?",
    "ind_accuracy": "Does teacher utterance ID {id} ('{s}') ask for a correct answer, procedure, or mathematical term?",
    "ind_classmate": "Does teacher utterance ID {id} ('{s}') direct students to respond to a classmate?",
    "ind_listening": "Does teacher utterance ID {id} ('{s}') check whether students are listening or following?",
}
MOVE_KEYS = dict(zip(MOVES, ["move_together", "move_relate", "move_restating",
                             "move_accuracy", "move_revoicing", "move_reasoning"]))
_write_lock = threading.Lock()


def norm(s):
    # Prompt JSONs use a curly apostrophe; ground truth and the R scripts use a straight one.
    return s.replace("’", "'")


def p(path):
    return os.path.join(ROOT, path)


def load_prompt(name):
    return json.load(open(p(f"{CFG['prompt_dir']}/TalkMoves_Teacher_{name}.json")))


def chunk_parts(items, per_item, cap):
    """Group items so each group has <= cap questions, keeping an item's questions together."""
    k = max(1, cap // per_item)
    return [items[i:i + k] for i in range(0, len(items), k)] or [[]]


def build_requests(chunk_name, prompt_name, condition, variant):
    """Return ([(state, questions, part, decode)], utts). decode maps option key -> option name."""
    prompt = load_prompt(prompt_name)
    rq = CFG["request"]
    utts = json.load(open(p(f"{CFG['chunk_dir']}/{chunk_name}")))["utterances"]
    definitions = {norm(k): v for k, v in prompt["moveDefinitions"].items()}
    criteria = dict(definitions, **{"None": rq["none_description"]})
    examples = {norm(k): [norm(e) for e in v] for k, v in prompt.get("moveExamples", {}).items()}
    guidance = prompt["workflow"][2:] + prompt["clarifications"][1:]
    instr_suffix = ""
    if examples and rq["example_placement"] == "question":
        instr_suffix = " Examples of each move: " + json.dumps(examples, ensure_ascii=False)

    def state_for(target=None):
        if rq["state_mode"] == "target_only":
            return f"Teacher: {target['Sentence']}"
        s = {"task": "Classroom math dialogue. Label teacher utterances with Talk Moves.", "guidance": guidance}
        if examples and rq["example_placement"] == "state":
            s["move_examples"] = examples
        if target is not None:
            s["target_id"] = target["ID"]
        # One input utterance (ID 15761) has no Turn; send it as null rather than editing inputs.
        s["dialogue"] = [{k: u.get(k) for k in ("ID", "Turn", "Speaker", "Sentence")} for u in utts]
        return json.dumps(s, ensure_ascii=False)

    def choice_q(u):
        opts = list(OPTIONS)
        if variant == "shuffle":
            random.Random(f"{CFG.get('seed', 20261025)}-{u['ID']}").shuffle(opts)
        if variant == "letters":
            keys = list(string.ascii_uppercase[:len(opts)])
        else:
            keys = opts
        q = {"type": "choice", "criteria": {k: criteria[o] for k, o in zip(keys, opts)},
             "instructions": f"Which Talk Move is teacher utterance ID {u['ID']} ('{u['Sentence']}')?{instr_suffix}"}
        return q, dict(zip(keys, opts))

    def noul_qs(u):
        qs = {f"{u['ID']}__{MOVE_KEYS[m]}": {"type": "noul", "instructions":
              f"Is teacher utterance ID {u['ID']} ('{u['Sentence']}') an instance of {m}: {definitions[m]}"} for m in MOVES}
        qs.update({f"{u['ID']}__{k}": {"type": "noul", "instructions": t.format(id=u["ID"], s=u["Sentence"])}
                   for k, t in INDICATORS.items()})
        return qs

    teacher = [u for u in utts if u["Speaker"] == "T"]
    cap = CFG["jev"]["max_questions_per_request"]
    out = []
    if condition == "B":
        for i, part in enumerate(chunk_parts(teacher, len(MOVES) + len(INDICATORS), cap)):
            qs = {}
            for u in part:
                qs.update(noul_qs(u))
            out.append((state_for(), qs, i, None))
        return out, utts
    if rq["state_mode"] in ("target_only", "marked_target"):
        for i, u in enumerate(teacher):
            q, dec = choice_q(u)
            out.append((state_for(u), {str(u["ID"]): q}, i, {str(u["ID"]): dec}))
        return out, utts
    for i, part in enumerate(chunk_parts(teacher, 1, cap)):
        qs, decs = {}, {}
        for u in part:
            qs[str(u["ID"])], decs[str(u["ID"])] = choice_q(u)
        out.append((state_for(), qs, i, decs))
    return out, utts


# ---------------------------------------------------------------- callers

def jev_call(state, questions):
    jc = CFG["jev"]
    route = jc["routes"][jc["route"]]
    if not route.get("base_url"):
        raise RuntimeError(f"Jev route '{jc['route']}' is not wired up")
    key = os.environ.get(route["key_env"]) or dotenv(route["key_env"])
    body = json.dumps({"model": jc["model"], "state": state, "questions": questions}).encode()
    for attempt in range(jc["max_retries"] + 1):
        req = urllib.request.Request(route["base_url"], data=body, method="POST",
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=jc["timeout_s"]) as r:
                resp = json.loads(r.read().decode())
            return resp, round((time.time() - t0) * 1000), attempt
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:500]
            if "plan_limit" in msg:
                raise RuntimeError(f"plan_limit: {msg}")
            if e.code == 429 or e.code >= 500:
                if attempt < jc["max_retries"]:
                    time.sleep(jc["backoff_base_s"] * 2 ** attempt + random.random())
                    continue
            raise RuntimeError(f"HTTP {e.code}: {msg}")
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < jc["max_retries"]:
                time.sleep(jc["backoff_base_s"] * 2 ** attempt + random.random())
                continue
            raise RuntimeError(f"network: {e}")


_von = None


def von_call(state, questions):
    global _von
    if _von is None:
        os.environ["VON_DEVICE"] = CFG["von"]["device"]
        import torch
        import von
        if CFG["von"]["device"] == "mps" and not torch.backends.mps.is_available():
            raise RuntimeError("MPS not available; refusing CPU fallback")
        _von = von
    t0 = time.time()
    r = _von.system_one(state=state, questions=questions)
    resp = json.loads(r.model_dump_json())
    resp.update({"id": None, "hf_sha": CFG["von"]["hf_sha"], "device": CFG["von"]["device"]})
    return resp, round((time.time() - t0) * 1000), 0


def dotenv(name):
    with open(p(".env")) as f:
        for line in f:
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(f"{name} not found in .env")


# ---------------------------------------------------------------- run

def append_csv(path, cols, rows):
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        if new:
            w.writeheader()
        w.writerows(rows)


def run_chunk(chunk, prompt_name, model, out_dir, condition, variant):
    done_path = os.path.join(out_dir, f"{chunk}_raw.txt" if condition == "A" else f"{chunk}_done.json")
    if os.path.exists(done_path):
        return "skipped"
    reqs, utts = build_requests(chunk, prompt_name, condition, variant)
    call = jev_call if model == "jev" else von_call
    answers, rows, logs = {}, [], []
    for state, questions, part, decode in reqs:
        if not questions:
            continue
        resp, latency, retries = call(state, questions)
        ts = datetime.now(timezone.utc).isoformat()
        state_bytes = len(state.encode())
        usage = resp.get("usage", {})
        logs.append({"chunk": chunk, "prompt": prompt_name, "condition": condition, "variant": variant, "part": part,
                     "timestamp": ts, "latency_ms": latency, "retries": retries, "state_bytes": state_bytes,
                     "long_context": state_bytes > CFG["jev"]["long_context_flag_bytes"],
                     "request": {"model": CFG["jev"]["model"] if model == "jev" else None, "state": state, "questions": questions},
                     "response": resp})
        missing = set(questions) - set(resp["answers"])
        if missing:
            raise RuntimeError(f"{len(missing)} questions unanswered, e.g. {sorted(missing)[:3]}")
        common = {"model": resp.get("model"), "request_id": resp.get("id"), "split_part": part, "latency_ms": latency,
                  "input_tokens": usage.get("input_tokens"), "request_cost": usage.get("cost"),
                  "n_questions": len(questions), "state_bytes": state_bytes, "timestamp": ts}
        for qid, a in resp["answers"].items():
            if condition == "B":
                uid, qname = qid.split("__", 1)
                rows.append({"ID": uid, "chunk": chunk, "question": qname, "p": a["noul"], **common})
                continue
            dec = decode[qid]
            probs = {dec[k]: v for k, v in a["probabilities"].items()}
            answers[qid] = dec[a["choice"]]
            rows.append({"ID": qid, "chunk": chunk, "prompt": prompt_name, "variant": variant,
                         **{f"p_{o}": probs.get(o) for o in OPTIONS},
                         "choice": answers[qid], "confidence": a["confidence"], **common})
    with _write_lock:
        with open(os.path.join(out_dir, "calls.jsonl"), "a") as f:
            for entry in logs:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        if condition == "B":
            append_csv(os.path.join(out_dir, "noul_probabilities.csv"), NOUL_COLS, rows)
            # Done-marker last, so an interrupted chunk is retried rather than half-recorded.
            with open(done_path, "w") as f:
                json.dump({"n_rows": len(rows), "n_requests": len(reqs)}, f)
            return f"{len(rows)} nouls / {len(reqs)} req"
        append_csv(os.path.join(out_dir, "probabilities.csv"), PROB_COLS, rows)
        records = [{"ID": u["ID"], "Speaker": "T", "Turn": u.get("Turn"),
                    "TalkMove": None if answers[str(u["ID"])] == "None" else answers[str(u["ID"])]}
                   for u in utts if u["Speaker"] == "T"]
        with open(done_path, "w") as f:
            json.dump({"records": records}, f, ensure_ascii=False)
    return f"{len(records)} utts / {len(reqs)} req"


def chunk_size(c):
    return sum(u["Speaker"] == "T" for u in json.load(open(p(f"{CFG['chunk_dir']}/{c}")))["utterances"])


def select_chunks(spec):
    splits = json.load(open(p(CFG["splits_file"])))
    which, _, n = spec.partition(":")
    dev = splits["dev_chunks"]
    everything = sorted(c for c in os.listdir(p(CFG["chunk_dir"])) if c.endswith(".json"))
    pools = {"dev": dev, "eval": [c for c in everything if c not in set(dev)], "all": everything}
    if which == "robust":
        # Condition C subset: seeded sample of evaluation chunks.
        return sorted(random.Random(splits["seed"] + 1).sample(pools["eval"], int(n)))
    if which == "devsample":
        return sorted(random.Random(splits["seed"] + 2).sample(dev, int(n)))
    if which not in pools:
        return spec.split(",")
    pool = pools[which]
    if not n:
        return pool
    # Test-mode selection: the largest chunk in the pool (exercises the question cap) + seeded sample.
    largest = max(pool, key=chunk_size)
    rest = random.Random(splits["seed"]).sample([c for c in pool if c != largest], int(n) - 1)
    return [largest] + rest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=["jev", "von"], required=True)
    ap.add_argument("--jev-model", default=None, help="override the pinned Jev model id")
    ap.add_argument("--condition", default="A", choices=["A", "B"])
    ap.add_argument("--variant", default="base", choices=["base", "shuffle", "letters"])
    ap.add_argument("--prompt", default="ZeroShot", choices=["ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL"])
    ap.add_argument("--chunks", default="dev:5", help="dev|eval|all[:n] | robust:n | devsample:n | chunk names")
    ap.add_argument("--tag", default=None, help="subdirectory under output_base, e.g. test_mode")
    ap.add_argument("--state-mode", default=None, choices=["chunk", "target_only", "marked_target"])
    ap.add_argument("--placement", default=None, choices=["state", "question"])
    args = ap.parse_args()
    if args.state_mode:
        CFG["request"]["state_mode"] = args.state_mode
    if args.placement:
        CFG["request"]["example_placement"] = args.placement
    if args.jev_model:
        CFG["jev"]["model"] = args.jev_model
        CFG["jev"]["model_dir"] = args.jev_model.replace("/", ".")

    model_dir = CFG[args.model]["model_dir"]
    if CFG["request"]["state_mode"] != "chunk":
        model_dir += f"__{CFG['request']['state_mode']}"
    base = p(CFG["output_base"])
    if args.tag:
        base = os.path.join(base, args.tag)
    out_dir = os.path.join(base, f"TalkMoves_Teacher_{args.prompt}", model_dir)
    os.makedirs(out_dir, exist_ok=True)

    chunks = select_chunks(args.chunks)
    workers = CFG["jev"]["concurrency"] if args.model == "jev" else 1
    t0, errors = time.time(), 0
    with cf.ThreadPoolExecutor(workers) as ex:
        futs = {ex.submit(run_chunk, c, args.prompt, args.model, out_dir, args.condition, args.variant): c for c in chunks}
        for fut in cf.as_completed(futs):
            try:
                fut.result()
            except Exception as e:  # keep going; the chunk stays un-done and is retried next run
                errors += 1
                print(f"{futs[fut]}: ERROR {e}", flush=True)
    print(f"{len(chunks)} chunks, {errors} errors, {time.time() - t0:.1f}s -> {os.path.relpath(out_dir, ROOT)}")


if __name__ == "__main__":
    main()
