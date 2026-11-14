#!/usr/bin/env python3
"""Python-inference baseline for the ncnn deployment evaluation (issue #508).

Replays every decision recorded by the exported-build eval run
(``scenes/testing/eval_scene.tscn`` → ``eval_results.json``) through the ORIGINAL
Python-inference path — the SB3 PPO policy (``final_model.zip`` + its
``vecnormalize.pkl``) and, as a cross-check, the ONNX logits graph via
onnxruntime — and measures how often the Python path picks the SAME action
the deployed ncnn path picked on the SAME raw observation:

  agreement overall + per head (aim/attack/move/target),
  the Python action distribution per head vs the ncnn one,
  the training-time TensorBoard reference curves (when readable).

Deterministic on both sides (SB3 ``deterministic=True`` argmax / ncnn
``deterministic_inference``), so any disagreement is a real pipeline
discrepancy — exactly what #508 wants surfaced (missing VecNormalize stats,
blob/shape drift, masking mismatches), not sampling noise.

Usage (train venv — has SB3, onnxruntime, tensorboard):

  .venv-train/bin/python eval_baseline.py \
      --results builds/eval/eval_results.json \
      --model runs/issue471_check/final_model.zip \
      --vecnormalize runs/issue471_check/vecnormalize.pkl \
      --onnx models/policy-logits.onnx \
      --out builds/eval/eval_baseline.json
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--results", default="builds/eval/eval_results.json",
                   help="eval_results.json written by the exported run")
    p.add_argument("--model", default="runs/issue471_check/final_model.zip",
                   help="SB3 checkpoint the deployed ncnn model was exported from")
    p.add_argument("--vecnormalize", default="runs/issue471_check/vecnormalize.pkl",
                   help="SB3 VecNormalize pickle co-located with the checkpoint")
    p.add_argument("--onnx", default="models/policy-logits.onnx",
                   help="logits ONNX graph (the pnnx input) for the ORT cross-check")
    p.add_argument("--out", default="builds/eval/eval_baseline.json",
                   help="where to write the comparison JSON")
    p.add_argument("--max-decisions", type=int, default=0,
                   help="cap the replayed decisions (0 = all; debug knob)")
    return p.parse_args()


def load_vecnormalize(path: str):
    import pickle

    with open(path, "rb") as f:
        return pickle.load(f)


def training_reference(run_dir: str) -> dict | None:
    """Last rollout/ep_rew_mean + ep_len_mean from the run's TensorBoard events."""
    try:
        from tensorboard.backend.event_processing import event_accumulator
    except ImportError:
        return {"error": "tensorboard not installed"}
    event_dirs = sorted(glob.glob(os.path.join(run_dir, "*", "events.out.tfevents.*")))
    if not event_dirs:
        return None
    try:
        ea = event_accumulator.EventAccumulator(os.path.dirname(event_dirs[-1]))
        ea.Reload()
        out = {}
        for tag in ("rollout/ep_rew_mean", "rollout/ep_len_mean"):
            if tag in ea.Tags().get("scalars", []):
                events = ea.Scalars(tag)
                out[tag] = {"last": events[-1].value, "steps": events[-1].step,
                            "points": len(events)}
        return out or None
    except Exception as exc:  # noqa: BLE001 - reference is best-effort
        return {"error": f"{type(exc).__name__}: {exc}"}


def main() -> int:
    args = parse_args()
    with open(args.results, "r", encoding="utf-8") as f:
        results = json.load(f)

    episodes = results.get("episodes", [])
    decisions = []
    for ep in episodes:
        # "decision_stream" is the full (raw obs -> action) record (#508
        # harness); "decisions" kept list-compat for older captures.
        stream = ep.get("decision_stream")
        if stream is None:
            legacy = ep.get("decisions", [])
            stream = legacy if isinstance(legacy, list) else []
        decisions.extend((ep["index"], d) for d in stream)
    if args.max_decisions > 0:
        decisions = decisions[: args.max_decisions]
    if not decisions:
        print("baseline: no decisions recorded in", args.results)
        return 1

    import numpy as np
    from stable_baselines3 import PPO

    vn = load_vecnormalize(args.vecnormalize)
    # godot-rl's VecNormalize keys obs_rms by obs channel ("obs"); the stock
    # SB3 object exposes the RunningMeanStd directly. Unwrap either shape.
    obs_rms = vn.obs_rms
    if isinstance(obs_rms, dict):
        obs_rms = obs_rms.get("obs", next(iter(obs_rms.values())))
    mean = np.asarray(obs_rms.mean, dtype=np.float64)
    var = np.asarray(obs_rms.var, dtype=np.float64)
    epsilon = float(getattr(vn, "epsilon", 1e-8))
    clip_obs = float(getattr(vn, "clip_obs", 10.0))

    def normalize(raw: np.ndarray) -> np.ndarray:
        # SB3 VecNormalize._normalize_obs math: float64, then float32 cast —
        # the exact transform the game replays via the JSON sidecar (#503).
        scaled = (raw.astype(np.float64) - mean) / np.sqrt(var + epsilon)
        return np.clip(scaled, -clip_obs, clip_obs).astype(np.float32)

    model = PPO.load(args.model, device="cpu")
    space = model.action_space
    nvec = list(space.nvec)
    # MultiInputPolicy: the checkpoint's observation space is the godot-rl
    # dict space {"obs": Box} — predict() takes the dict, not a bare vector.
    dict_obs = hasattr(model.observation_space, "spaces") \
        and "obs" in model.observation_space.spaces
    # The recorded joints are dicts; the wire order is the dict insertion
    # order (aim, attack, move, target) — SB3 composed the MultiDiscrete
    # alphabetically from the same heads, so sorted(keys) must equal nvec.
    heads = sorted(decisions[0][1]["action"].keys())
    # SB3 composed the MultiDiscrete alphabetically from the wire heads
    # (DEPLOYMENT.md §3 pins [3, 8, 6, 4] = aim, attack, move, target);
    # a mismatch here means the checkpoint is NOT the deployed policy.
    if len(nvec) != len(heads):
        print("baseline: head count mismatch — action space", nvec, "vs recorded", heads)
        return 1
    sizes = {}
    for ep_i, d in decisions:
        for k in d["action"]:
            sizes[k] = max(sizes.get(k, 0), int(d["action"][k]) + 1)

    import onnxruntime as ort

    sess = ort.InferenceSession(args.onnx, providers=["CPUExecutionProvider"])
    ort_in = sess.get_inputs()[0].name

    agree = {h: [0, 0] for h in heads}  # head -> [agree, total]
    ncnn_counts = {h: [0] * sizes[h] for h in heads}
    py_counts = {h: [0] * sizes[h] for h in heads}
    onnx_mismatch = 0
    for _ep_i, d in decisions:
        raw = np.asarray(d["obs"], dtype=np.float32)
        norm = normalize(raw)
        obs_in = {"obs": norm.reshape(1, -1)} if dict_obs else norm.reshape(1, -1)
        action, _ = model.predict(obs_in, deterministic=True)
        action = np.asarray(action).reshape(-1)
        # ORT cross-check: argmax per head straight off the logits graph.
        logits = sess.run(None, {ort_in: norm.reshape(1, -1)})[0].reshape(-1)
        ofs = 0
        for i, h in enumerate(heads):
            n = nvec[i]
            ncnn_a = int(d["action"][h])
            py_a = int(action[i])
            if int(np.argmax(logits[ofs : ofs + n])) != py_a:
                onnx_mismatch += 1
            ofs += n
            ncnn_counts[h][ncnn_a] += 1
            py_counts[h][py_a] += 1
            agree[h][1] += 1
            if ncnn_a == py_a:
                agree[h][0] += 1

    total = sum(v[1] for v in agree.values())
    hits = sum(v[0] for v in agree.values())
    summary = {
        "results_file": args.results,
        "model": args.model,
        "vecnormalize": args.vecnormalize,
        "onnx": args.onnx,
        "decisions": total,
        "episodes": len(episodes),
        "heads": heads,
        "agreement_overall": hits / total if total else None,
        "agreement_per_head": {h: (agree[h][0] / agree[h][1] if agree[h][1] else None)
                               for h in heads},
        "onnx_sb3_argmax_mismatches": onnx_mismatch,
        "ncnn_action_dist": ncnn_counts,
        "python_action_dist": py_counts,
        "ncnn_mask_violations": sum(int(ep.get("mask_violations", 0))
                                     for ep in episodes),
        "ncnn_summary": results.get("summary", {}),
        "training_reference": training_reference(os.path.dirname(args.vecnormalize.rstrip("/"))),
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    print("baseline: %d decisions over %d episodes" % (total, len(episodes)))
    print("baseline: agreement overall %.4f" % summary["agreement_overall"])
    for h in heads:
        print("baseline: agreement %-7s %.4f" % (h, summary["agreement_per_head"][h]))
    print("baseline: SB3-vs-ONNX argmax mismatches: %d" % onnx_mismatch)
    print("baseline: written to", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
