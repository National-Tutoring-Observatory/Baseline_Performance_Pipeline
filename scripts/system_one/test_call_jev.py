"""One Jev test call via OpenRouter on a single chunk (test mode).

Writes the raw request, raw response, and HTTP metadata to
data/outputs/SystemOne_Jev_Von/test_mode/. Stdlib only, so it runs before the uv venv exists.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHUNK = "TalkBack.Year1.Benson.Fall.121019_chunk_16_37.json"
MODEL = "typesafe/jev-1.14-20261014"
URL = "https://openrouter.ai/api/v1/systemone"
OUT = os.path.join(ROOT, "data/outputs/SystemOne_Jev_Von/test_mode")


def load_key():
    with open(os.path.join(ROOT, ".env")) as f:
        for line in f:
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("OPENROUTER_API_KEY not found in .env")


def norm(s):
    # Prompt JSONs use a curly apostrophe; ground truth and the R scripts use a straight one.
    return s.replace("’", "'")


def build_request():
    prompt = json.load(open(os.path.join(ROOT, "prompts/TalkMoves_NoReasoningRequested/TalkMoves_Teacher_ZeroShot.json")))
    utts = json.load(open(os.path.join(ROOT, "data/inputs/stratified_samples/representative_800_chunks", CHUNK)))["utterances"]

    criteria = {norm(k): v for k, v in prompt["moveDefinitions"].items()}
    criteria["None"] = "No talk move: off-topic, evaluative, administrative, or student-directed talk."

    state = {
        "task": "Classroom math dialogue. Label teacher utterances with Talk Moves.",
        "guidance": prompt["workflow"][2:] + prompt["clarifications"][1:],
        "dialogue": [{k: u[k] for k in ("ID", "Turn", "Speaker", "Sentence")} for u in utts],
    }
    questions = {
        str(u["ID"]): {
            "type": "choice",
            "instructions": f"Which Talk Move is teacher utterance ID {u['ID']} ('{u['Sentence']}')?",
            "criteria": criteria,
        }
        for u in utts if u["Speaker"] == "T"
    }
    return {"model": MODEL, "state": json.dumps(state, ensure_ascii=False), "questions": questions}


def main():
    os.makedirs(OUT, exist_ok=True)
    body = build_request()
    json.dump(body, open(os.path.join(OUT, "test_request.json"), "w"), indent=2, ensure_ascii=False)
    req = urllib.request.Request(
        URL, data=json.dumps(body).encode(), method="POST",
        headers={"Authorization": f"Bearer {load_key()}", "Content-Type": "application/json"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            status, headers, raw = r.status, dict(r.headers), r.read().decode()
    except urllib.error.HTTPError as e:
        status, headers, raw = e.code, dict(e.headers), e.read().decode()
    latency_ms = round((time.time() - t0) * 1000)
    meta = {
        "status": status, "latency_ms": latency_ms, "timestamp": datetime.now(timezone.utc).isoformat(),
        "chunk": CHUNK, "n_questions": len(body["questions"]), "state_bytes": len(body["state"].encode()),
        "headers": {k: v for k, v in headers.items() if k.lower().startswith(("x-", "content-type"))},
    }
    json.dump(meta, open(os.path.join(OUT, "test_meta.json"), "w"), indent=2)
    open(os.path.join(OUT, "test_response.json"), "w").write(raw)
    print(json.dumps(meta, indent=2))
    print(raw[:4000])


if __name__ == "__main__":
    main()
