"""Run the Jev test-call request through Von locally, forcing MPS (no silent CPU fallback)."""
import json
import os
import sys
import time

os.environ.setdefault("VON_DEVICE", "mps")

import torch
import von
from huggingface_hub import model_info

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data/outputs/SystemOne_Jev_Von/test_mode")


def main():
    if not torch.backends.mps.is_available():
        sys.exit("MPS not available; refusing to fall back to CPU")
    body = json.load(open(os.path.join(OUT, "test_request.json")))

    t0 = time.time()
    resp = von.system_one(state=body["state"], questions=body["questions"])  # first call loads weights
    load_and_first_ms = round((time.time() - t0) * 1000)
    t0 = time.time()
    resp = von.system_one(state=body["state"], questions=body["questions"])
    warm_ms = round((time.time() - t0) * 1000)

    engine = von.engine.VonEngine.get_instance()
    meta = {
        "von_sdk": von.__version__ if hasattr(von, "__version__") else None,
        "engine_version": von.engine.VON_VERSION,
        "hf_repo": "wfzyx/von", "hf_sha": model_info("wfzyx/von").sha,
        "device": str(getattr(engine.backend, "device", None)), "torch": torch.__version__,
        "n_questions": len(body["questions"]), "load_and_first_ms": load_and_first_ms, "warm_ms": warm_ms,
        "mps_allocated_mb": round(torch.mps.current_allocated_memory() / 2**20),
        "truncation": resp.truncation,
    }
    json.dump(meta, open(os.path.join(OUT, "test_meta_von.json"), "w"), indent=2)
    open(os.path.join(OUT, "test_response_von.json"), "w").write(resp.model_dump_json(indent=1))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
