#!/usr/bin/env python3
"""PPO learning-rate / entropy-coefficient sweep (issue #470).

Runs a small grid over the two most impactful PPO hyperparameters for the
discrete multi-action space — learning rate (3e-4, 5e-4, 1e-3) x entropy
coefficient (0.001, 0.01, 0.05) — as short same-seed trainings against the
exported training build, then ranks the runs by the #469 team-deathmatch
TensorBoard metrics and writes the comparison to runs/sweep/summary.json.

Every combination trains with the SAME seed, parallel-environment count and
speedup, so the only difference between two experiment directories is the
hyperparameter pair. Runs land under runs/sweep/<name>/ (distinct experiment
names — open them together with `tensorboard --logdir runs/sweep` for the
multi-experiment view the issue asks for).

The sweep is a diagnostic step (issue #470): if no combination meaningfully
improves on the scripted baseline, the problem lives in the reward signal
(Phase 4) or observation design (Phase 3), not in these hyperparameters.

Resumable: a combination whose runs/sweep/<name>/final_model.zip already
exists is skipped, so a crashed sweep (or a truncated budget — see
--timesteps) simply continues where it stopped.

Selection metrics (per run):
  win_rate_last   mean of the last tdm/win_rate points (decided episodes
                  won vs the env's scripted Npc side — the scripted baseline)
  ep_rew_last     mean of the last rollout/ep_rew_mean points (sample
                  efficiency proxy: the area under the ep_rew_mean curve,
                  `ep_rew_auc`, rewards curves that climb EARLY)
  collapsed       any head's final tdm/action_max_prob >= 0.98 — a collapsed
                  head disqualifies a combination regardless of its curves

Best combination = highest win_rate_last among non-collapsed runs,
ties broken by ep_rew_auc then ep_rew_last.

Definition of Done (issue #470): >= 6 sweep runs under runs/sweep/ with
distinct names, best combination identified, results + rationale recorded in
HYPERPARAMETERS.md (this script prints the table to paste there).

Usage:
    python sweep_hparams.py                     # full 3x3 grid, 200k steps
    python sweep_hparams.py --summarize_only    # re-rank existing runs only
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import subprocess
import sys

# Same seed, parallel envs and speedup for EVERY combination (issue #470):
# only lr/ent_coef may differ between runs. n_parallel=2 (6 sub-envs with
# the 3 in-scene agents) is the configuration the gateway's 2-CPU / 4 GB
# box sustained through issues #466-#469 verification runs.
GRID_LEARNING_RATES = [3e-4, 5e-4, 1e-3]
GRID_ENT_COEFS = [0.001, 0.01, 0.05]
SWEEP_SEED = 0
SWEEP_N_PARALLEL = 2
SWEEP_SPEEDUP = 20
SWEEP_TIMESTEPS = 200_000  # inside the issue's 200k-500k band

REPO_ROOT = pathlib.Path(__file__).resolve().parent
SWEEP_DIR = REPO_ROOT / "runs" / "sweep"
# A collapsed head's dominant-action probability at/above which a run is
# flagged (training_metrics.py logs tdm/action_max_prob/<head> per dump).
COLLAPSE_MAX_PROB = 0.98


def run_name(learning_rate: float, ent_coef: float) -> str:
    """Distinct, sortable experiment name: lr3e-04_ent0.001 style."""
    return f"lr{learning_rate:.0e}_ent{ent_coef:g}".replace("e-0", "e-")


def train_one(learning_rate: float, ent_coef: float, timesteps: int) -> bool:
    """Train one grid point into runs/sweep/<name>/. True when it completed
    (or had completed before — resumable), False when train.py failed."""
    name = run_name(learning_rate, ent_coef)
    experiment_dir = SWEEP_DIR / name
    if (experiment_dir / "final_model.zip").is_file():
        print(f"SWEEP {name}: final_model.zip exists — skipping (resume)")
        return True
    print(f"SWEEP {name}: training {timesteps} steps "
          f"(seed {SWEEP_SEED}, n_parallel {SWEEP_N_PARALLEL}, speedup {SWEEP_SPEEDUP})")
    result = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "train.py"),
            "--learning_rate", repr(learning_rate),
            "--ent_coef", repr(ent_coef),
            "--seed", str(SWEEP_SEED),
            "--n_parallel", str(SWEEP_N_PARALLEL),
            "--speedup", str(SWEEP_SPEEDUP),
            "--timesteps", str(timesteps),
            "--experiment_dir", str(experiment_dir),
        ],
        cwd=REPO_ROOT,
    )
    ok = result.returncode == 0 and (experiment_dir / "final_model.zip").is_file()
    print(f"SWEEP {name}: {'OK' if ok else 'FAILED'}")
    return ok


def _last_mean(values: list[float], points: int) -> float | None:
    """Mean of the last `points` scalar values; None when no data."""
    if not values:
        return None
    tail = values[-points:]
    return sum(tail) / len(tail)


def summarize_run(experiment_dir: pathlib.Path) -> dict:
    """Read one experiment's TensorBoard event file into a metrics record."""
    from tensorboard.backend.event_processing import event_accumulator

    events = sorted(experiment_dir.glob("PPO_*/events.out.tfevents.*"))
    if not events:
        return {"name": experiment_dir.name, "ok": False, "reason": "no event file"}
    accumulator = event_accumulator.EventAccumulator(str(events[-1]))
    accumulator.Reload()
    scalars = accumulator.Tags().get("scalars", [])

    def series(tag: str) -> list[float]:
        return [point.value for point in accumulator.Scalars(tag)] if tag in scalars else []

    win_rate = series("tdm/win_rate")
    ep_rew = series("rollout/ep_rew_mean")
    entropy_loss = series("train/entropy_loss")
    explained_var = series("train/explained_variance")
    value_loss = series("train/value_loss")
    max_prob_tags = [t for t in scalars if t.startswith("tdm/action_max_prob/")]
    final_max_probs = {
        tag.rsplit("/", 1)[1]: series(tag)[-1] for tag in max_prob_tags if series(tag)
    }
    collapsed_heads = sorted(
        head for head, prob in final_max_probs.items() if prob >= COLLAPSE_MAX_PROB
    )
    # Sample-efficiency proxy: mean ep_rew_mean over the whole run (area
    # under the curve / duration) — early climbers score higher than runs
    # that reach the same final return late.
    ep_rew_auc = (sum(ep_rew) / len(ep_rew)) if ep_rew else None
    return {
        "name": experiment_dir.name,
        "ok": True,
        "timesteps": max(
            (accumulator.Scalars(t)[-1].step for t in scalars), default=0
        ),
        "win_rate_last": _last_mean(win_rate, 3),
        "win_rate_final": win_rate[-1] if win_rate else None,
        "ep_rew_last": _last_mean(ep_rew, 3),
        "ep_rew_auc": ep_rew_auc,
        "entropy_loss_final": entropy_loss[-1] if entropy_loss else None,
        "explained_variance_final": explained_var[-1] if explained_var else None,
        "value_loss_final": value_loss[-1] if value_loss else None,
        "final_max_prob": final_max_probs,
        "collapsed_heads": collapsed_heads,
        "collapsed": bool(collapsed_heads),
    }


def rank_runs(records: list[dict]) -> list[dict]:
    """Best first: win_rate_last (higher), then ep_rew_auc, then ep_rew_last,
    then explained_variance_final (did the value head learn anything).
    Collapsed runs rank below every non-collapsed run. With no decided
    episodes (timeout_frac=1.0 — no run beats the scripted baseline) the
    win rate is None for every run and the tie-breaks decide; that
    flat-sweep outcome is itself the #470 diagnostic signal."""
    def key(record: dict):
        win = record.get("win_rate_last")
        auc = record.get("ep_rew_auc")
        rew = record.get("ep_rew_last")
        ev = record.get("explained_variance_final")
        return (
            record.get("collapsed", True),
            -(win if win is not None else -math.inf),
            -(auc if auc is not None else -math.inf),
            -(rew if rew is not None else -math.inf),
            -(ev if ev is not None else -math.inf),
        )

    return sorted((r for r in records if r.get("ok")), key=key)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--timesteps",
        type=int,
        default=SWEEP_TIMESTEPS,
        help="training steps per combination (issue suggests 200k-500k)",
    )
    parser.add_argument(
        "--summarize_only",
        action="store_true",
        help="skip training; only re-rank existing runs/sweep/* experiment dirs",
    )
    args = parser.parse_args()

    if not args.summarize_only:
        for learning_rate in GRID_LEARNING_RATES:
            for ent_coef in GRID_ENT_COEFS:
                if not train_one(learning_rate, ent_coef, args.timesteps):
                    print(f"sweep_hparams.py: run {run_name(learning_rate, ent_coef)} "
                          "failed; continuing with the remaining grid points")

    records = [summarize_run(d) for d in sorted(SWEEP_DIR.iterdir()) if d.is_dir()]
    records = [r for r in records if r.get("ok")]
    if not records:
        sys.exit("sweep_hparams.py: no completed runs found under runs/sweep/")
    ranked = rank_runs(records)
    best = ranked[0]

    summary = {
        "issue": 470,
        "grid": {
            "learning_rates": GRID_LEARNING_RATES,
            "ent_coefs": GRID_ENT_COEFS,
            "seed": SWEEP_SEED,
            "n_parallel": SWEEP_N_PARALLEL,
            "speedup": SWEEP_SPEEDUP,
            "timesteps_requested": args.timesteps,
        },
        "selection_rule": (
            "highest win_rate_last (mean of last 3 tdm/win_rate dumps) among "
            "non-collapsed runs; ties broken by ep_rew_auc then ep_rew_last"
        ),
        "best": best["name"],
        "runs": ranked,
    }
    summary_path = SWEEP_DIR / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")

    print("\n=== sweep results (best first) ===")
    header = (f"{'run':<18} {'steps':>7} {'win_rate':>9} {'ep_rew':>9} "
              f"{'auc':>9} {'ent_loss':>9} {'ev':>7}  flags")
    print(header)
    print("-" * len(header))
    for record in ranked:
        win = record["win_rate_last"]
        rew = record["ep_rew_last"]
        auc = record["ep_rew_auc"]
        ent = record["entropy_loss_final"]
        ev = record["explained_variance_final"]
        flags = "collapsed:" + ",".join(record["collapsed_heads"]) if record["collapsed"] else ""
        print(f"{record['name']:<18} {record['timesteps']:>7} "
              f"{('%0.3f' % win) if win is not None else '-':>9} "
              f"{('%0.1f' % rew) if rew is not None else '-':>9} "
              f"{('%0.1f' % auc) if auc is not None else '-':>9} "
              f"{('%0.3f' % ent) if ent is not None else '-':>9} "
              f"{('%0.2f' % ev) if ev is not None else '-':>7}  {flags}")
    print(f"\nBEST: {best['name']}  (selection rule: {summary['selection_rule']})")
    print(f"SUMMARY: {summary_path}")
    print("TENSORBOARD: tensorboard --logdir runs/sweep  (multi-experiment view)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
