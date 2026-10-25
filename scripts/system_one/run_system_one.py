"""Run Condition A (direct choice) for Jev or Von over a set of chunks.

Writes, per chunk, `<chunk>.json_raw.txt` in the {"records": [...]} format that
scripts/functions/json_parser.r parses, so analyze_results.r runs unchanged. Also appends
the full probability vector per utterance to probabilities.csv and every request/response
to calls.jsonl. Resumable: chunks whose raw file exists are skipped.

Usage (from scripts/system_one/):
  uv run python run_system_one.py --model jev --prompt ZeroShot --chunks dev:5 --tag test_mode
"""
import argparse
import concurrent.futures as cf
import csv
import json
import os
import random
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
PROB_COLS = ["ID", "chunk", "prompt", "model", "request_id", "split_part"] + [f"p_{o}" for o in OPTIONS] + [
    "choice", "confidence", "latency_ms", "input_tokens", "request_cost", "n_questions", "state_bytes", "timestamp"]
_write_lock = threading.Lock()


def norm(s):
    # Prompt JSONs use a curly apostrophe; ground truth and the R scripts use a straight one.
    return s.replace("’", "'")


def p(path):
    return os.path.join(ROOT, path)


def load_prompt(name):
    return json.load(open(p(f"{CFG['prompt_dir']}/TalkMoves_Teacher_{name}.json")))


def build_requests(chunk_name, prompt_name):
    """Return a list of (state, questions, part) for one chunk, split if over the question cap."""
    prompt = load_prompt(prompt_name)
    rq = CFG["request"]
    utts = json.load(open(p(f"{CFG['chunk_dir']}/{chunk_name}")))["utterances"]
    criteria = {norm(k): v for k, v in prompt["moveDefinitions"].items()}
    criteria["None"] = rq["none_description"]
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
        s["dialogue"] = [{k: u[k] for k in ("ID", "Turn", "Speaker", "Sentence")} for u in utts]
        return json.dumps(s, ensure_ascii=False)

    def question(u):
        return {"type": "choice", "criteria": criteria,
                "instructions": f"Which Talk Move is teacher utterance ID {u['ID']} ('{u['Sentence']}')?{instr_suffix}"}

    teacher = [u for u in utts if u["Speaker"] == "T"]
    if rq["state_mode"] == "target_only":
        return [(state_for(u), {str(u["ID"]): question(u)}, i) for i, u in enumerate(teacher)], utts
    cap = CFG["jev"]["max_questions_per_request"]
    parts = [teacher[i:i + cap] for i in range(0, len(teacher), cap)] or [[]]
    return [(state_for(), {str(u["ID"]): question(u) for u in part}, i) for i, part in enumerate(parts)], utts


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

def run_chunk(chunk, prompt_name, model, out_dir):
    raw_path = os.path.join(out_dir, f"{chunk}_raw.txt")
    if os.path.exists(raw_path):
        return "skipped"
    reqs, utts = build_requests(chunk, prompt_name)
    call = jev_call if model == "jev" else von_call
    by_id = {u["ID"]: u for u in utts}
    answers, rows, logs = {}, [], []
    for state, questions, part in reqs:
        if not questions:
            continue
        resp, latency, retries = call(state, questions)
        ts = datetime.now(timezone.utc).isoformat()
        state_bytes = len(state.encode())
        usage = resp.get("usage", {})
        logs.append({"chunk": chunk, "prompt": prompt_name, "part": part, "timestamp": ts, "latency_ms": latency,
                     "retries": retries, "state_bytes": state_bytes, "long_context": state_bytes > CFG["jev"]["long_context_flag_bytes"],
                     "request": {"state": state, "questions": questions}, "response": resp})
        for qid, a in resp["answers"].items():
            answers[qid] = a
            rows.append({"ID": qid, "chunk": chunk, "prompt": prompt_name, "model": resp.get("model"),
                         "request_id": resp.get("id"), "split_part": part,
                         **{f"p_{o}": a["probabilities"].get(o) for o in OPTIONS},
                         "choice": a["choice"], "confidence": a["confidence"], "latency_ms": latency,
                         "input_tokens": usage.get("input_tokens"), "request_cost": usage.get("cost"),
                         "n_questions": len(questions), "state_bytes": state_bytes, "timestamp": ts})
    records = [{"ID": u["ID"], "Speaker": "T", "Turn": u["Turn"],
                "TalkMove": None if answers[str(u["ID"])]["choice"] == "None" else answers[str(u["ID"])]["choice"]}
               for u in utts if u["Speaker"] == "T"]
    with _write_lock:
        with open(os.path.join(out_dir, "calls.jsonl"), "a") as f:
            for entry in logs:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        prob_path = os.path.join(out_dir, "probabilities.csv")
        new = not os.path.exists(prob_path)
        with open(prob_path, "a", newline="") as f:
            w = csv.DictWriter(f, fieldnames=PROB_COLS)
            if new:
                w.writeheader()
            w.writerows(rows)
        # Raw file last, so an interrupted chunk is retried rather than half-recorded.
        with open(raw_path, "w") as f:
            json.dump({"records": records}, f, ensure_ascii=False)
    return f"{len(records)} utts / {len(reqs)} req"


def select_chunks(spec):
    splits = json.load(open(p(CFG["splits_file"])))
    which, _, n = spec.partition(":")
    if which == "dev":
        pool = splits["dev_chunks"]
    elif which == "eval":
        dev = set(splits["dev_chunks"])
        pool = sorted(c for c in os.listdir(p(CFG["chunk_dir"])) if c.endswith(".json") and c not in dev)
    else:
        return spec.split(",")
    if not n:
        return pool
    # Test-mode selection: the largest chunk in the pool (exercises the question cap) + seeded sample.
    size = {c: sum(u["Speaker"] == "T" for u in json.load(open(p(f"{CFG['chunk_dir']}/{c}")))["utterances"]) for c in pool}
    largest = max(pool, key=size.get)
    rest = random.Random(splits["seed"]).sample([c for c in pool if c != largest], int(n) - 1)
    return [largest] + rest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=["jev", "von"], required=True)
    ap.add_argument("--prompt", default="ZeroShot", choices=["ZeroShot", "OneShot", "FewShot_3", "FewShot_ALL"])
    ap.add_argument("--chunks", default="dev:5", help="dev[:n] | eval[:n] | comma-separated chunk names")
    ap.add_argument("--tag", default=None, help="subdirectory under output_base, e.g. test_mode")
    ap.add_argument("--state-mode", default=None, choices=["chunk", "target_only"])
    ap.add_argument("--placement", default=None, choices=["state", "question"])
    args = ap.parse_args()
    if args.state_mode:
        CFG["request"]["state_mode"] = args.state_mode
    if args.placement:
        CFG["request"]["example_placement"] = args.placement

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
    t0 = time.time()
    with cf.ThreadPoolExecutor(workers) as ex:
        futs = {ex.submit(run_chunk, c, args.prompt, args.model, out_dir): c for c in chunks}
        for fut in cf.as_completed(futs):
            try:
                print(f"{futs[fut]}: {fut.result()}", flush=True)
            except Exception as e:  # keep going; the chunk stays un-done and is retried next run
                print(f"{futs[fut]}: ERROR {e}", flush=True)
    print(f"done in {time.time() - t0:.1f}s -> {os.path.relpath(out_dir, ROOT)}")


if __name__ == "__main__":
    main()
