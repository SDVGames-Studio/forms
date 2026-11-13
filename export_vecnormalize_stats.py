#!/usr/bin/env python3
"""Export SB3 VecNormalize observation statistics for Godot inference (#503).

The policy exported by ``export_onnx.py`` (#502) was trained BEHIND SB3's
VecNormalize, so it expects normalized observations — but the running
mean/variance live in a separate ``vecnormalize.pkl``, not in the network
graph. This script serializes them into the portable JSON sidecar the
in-game ncnn wrapper replays pre-inference
(``addons/godot_native_rl/controllers/obs_normalize.gd``):

    normalized = clamp((raw - mean) / sqrt(var + epsilon), -clip_obs, +clip_obs)

    python export_vecnormalize_stats.py \
        --vecnormalize runs/issue471_check/vecnormalize.pkl \
        --out models/vecnormalize_stats.json

Output format (models/vecnormalize_stats.json, documented in DEPLOYMENT.md
§4): schema_version, norm_obs (the ACTIVE flag — false means the policy was
trained without obs normalization and the game must pass raw obs through),
obs_size, mean[], var[], epsilon, clip_obs, count (running-stat sample
count, provenance only).

Definition of Done (issue #503): the JSON exists alongside the exported
.onnx, the normalization formula and epsilon are documented, and the
built-in self-check — plus the standalone ``rl_vecnormalize_check.py`` —
confirm that applying the SAVED statistics to a raw observation reproduces
the output of SB3's own ``VecNormalize.normalize_obs`` (the exact transform
the observations went through on their way to the policy during training).

Dependencies: numpy + stable_baselines3 (only to unpickle the .pkl — this
script deliberately avoids torch/onnx so it stays cheap to run).

Arguments:
  --vecnormalize  VecNormalize stats pickle (default: the sibling
                  vecnormalize.pkl of --model's folder, else
                  runs/issue471_check/vecnormalize.pkl).
  --out           output JSON path (default models/vecnormalize_stats.json).
  --seed          RNG seed for the self-check raw observations (default 0).
"""

import argparse
import json
import os
import pickle

import numpy as np

SCHEMA_VERSION = 1
OBS_KEY = "obs"  # single-key dict observation contract (OBSERVATION_SPEC.md)


def _fallback_obs_size(vec_normalize) -> int:
    """Obs width of a stats-less (norm_obs=False) wrapper from its space."""
    space = vec_normalize.observation_space
    try:
        from gymnasium.spaces import Dict as GymDict
        if isinstance(space, GymDict):
            return int(space.spaces[OBS_KEY].shape[-1])
    except (ImportError, AttributeError, KeyError):
        pass
    return int(space.shape[-1])


def load_vecnormalize(path: str):
    """Unpickle a VecNormalize and return (wrapper, obs_rms, clip_obs, norm_obs, epsilon).

    For a dict observation space SB3 stores ``obs_rms`` keyed by observation
    key; the Forms contract has exactly one key, "obs" (same handling as
    export_onnx.load_obs_normalizer).
    """
    with open(path, "rb") as fh:
        vec_normalize = pickle.load(fh)
    norm_obs = bool(vec_normalize.norm_obs)
    obs_rms = getattr(vec_normalize, "obs_rms", None)
    # SB3 only allocates obs_rms when norm_obs=True; a norm_obs=False wrapper
    # legitimately has none — serialize zeros (the game passes raw obs through,
    # the arrays are provenance only).
    if obs_rms is None:
        if norm_obs:
            raise SystemExit(f"{path}: norm_obs=True but no obs_rms — corrupt stats pickle")
        return (vec_normalize, None, float(vec_normalize.clip_obs), norm_obs,
                float(vec_normalize.epsilon))
    if isinstance(obs_rms, dict):
        if set(obs_rms) != {OBS_KEY}:
            raise SystemExit(f"unexpected obs keys {sorted(obs_rms)}; expected ['{OBS_KEY}']")
        obs_rms = obs_rms[OBS_KEY]
    return (vec_normalize, obs_rms, float(vec_normalize.clip_obs),
            bool(vec_normalize.norm_obs), float(vec_normalize.epsilon))


def serialize_stats(obs_rms, epsilon: float, clip_obs: float, norm_obs: bool,
                    obs_size: int = 0) -> dict:
    """Build the JSON-sidecar dictionary from a RunningMeanStd.

    ``obs_rms=None`` (a norm_obs=False wrapper has no running stats) serializes
    zero mean/var of the policy's obs width — inert, since the replay is a raw
    passthrough when the active flag is false.
    """
    if obs_rms is None:
        mean = [0.0] * obs_size
        var = [0.0] * obs_size
        count = 0.0
        size = obs_size
    else:
        mean = [float(v) for v in obs_rms.mean]
        var = [float(v) for v in obs_rms.var]
        count = float(obs_rms.count)
        size = int(obs_rms.mean.size)
    return {
        "schema_version": SCHEMA_VERSION,
        "norm_obs": norm_obs,
        "obs_size": size,
        "mean": mean,
        "var": var,
        "epsilon": float(epsilon),
        "clip_obs": float(clip_obs),
        "count": count,
    }


def normalize_with_stats(raw: np.ndarray, stats: dict) -> np.ndarray:
    """Apply the saved stats exactly like the GDScript wrapper (obs_normalize.gd).

    Passthrough (raw unchanged) when ``norm_obs`` is false — matching SB3,
    which skips normalization entirely when the wrapper was created with
    ``norm_obs=False``.
    """
    if not stats.get("norm_obs", True):
        return np.asarray(raw, dtype=np.float64).copy()
    mean = np.asarray(stats["mean"], dtype=np.float64)
    var = np.asarray(stats["var"], dtype=np.float64)
    return np.clip((np.asarray(raw, dtype=np.float64) - mean)
                   / np.sqrt(var + stats["epsilon"]),
                   -stats["clip_obs"], stats["clip_obs"])


def training_path_normalize(vec_normalize, raw: np.ndarray) -> np.ndarray:
    """Run raw obs through SB3's own normalize_obs — the training-time truth."""
    if isinstance(vec_normalize.obs_rms, dict):
        return np.asarray(vec_normalize.normalize_obs({OBS_KEY: raw})[OBS_KEY])
    return np.asarray(vec_normalize.normalize_obs(raw))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vecnormalize", default=None,
                        help="VecNormalize stats pickle (vecnormalize.pkl)")
    parser.add_argument("--out", default="models/vecnormalize_stats.json",
                        help="output JSON path")
    parser.add_argument("--seed", type=int, default=0,
                        help="seed for the self-check raw observations")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.vecnormalize is None:
        default = "runs/issue471_check/vecnormalize.pkl"
        args.vecnormalize = default if os.path.exists(default) else ""
    if not args.vecnormalize or not os.path.exists(args.vecnormalize):
        raise SystemExit(f"vecnormalize stats not found: {args.vecnormalize!r}")

    vec_normalize, rms, clip_obs, norm_obs, epsilon = load_vecnormalize(args.vecnormalize)
    obs_size = int(rms.mean.size) if rms is not None else _fallback_obs_size(vec_normalize)
    stats = serialize_stats(rms, epsilon, clip_obs, norm_obs, obs_size=obs_size)
    print(f"loaded {args.vecnormalize}: obs_size={stats['obs_size']}, "
          f"norm_obs={norm_obs}, clip_obs={clip_obs}, epsilon={epsilon}, "
          f"count={rms.count:.0f}")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(stats, fh, indent=2)
        fh.write("\n")
    print(f"wrote {args.out}")

    # --- Self-check: saved stats reproduce the training-time transform ----
    # Re-load from DISK so the check exercises the shipped artifact, not the
    # in-memory dict. Raw obs drawn from a generous range (also beyond the
    # clip range, so clamping is exercised). SB3 casts the normalized obs to
    # float32 (VecEnv contract — the policy saw float32), so the replay is
    # cast the same way before comparing; the float64 math is identical, so
    # the match must be exact.
    with open(args.out) as fh:
        loaded = json.load(fh)
    rng = np.random.default_rng(args.seed)
    raws = [rng.uniform(-20.0, 20.0, size=loaded["obs_size"]) for _ in range(16)]
    raws.append(np.full(loaded["obs_size"], 1e3))  # far out of range -> clipped
    worst = 0.0
    for raw in raws:
        expected = training_path_normalize(vec_normalize, raw)
        got = normalize_with_stats(raw, loaded).astype(np.float32)
        worst = max(worst, float(np.max(np.abs(got - expected))))
    matches = worst == 0.0
    print(f"self-check: {len(raws)} raw obs, stats-vs-SB3 max abs diff {worst:.3e} "
          f"(norm_obs={loaded['norm_obs']})")
    if not matches:
        raise SystemExit("VERIFICATION FAILED: saved stats do not reproduce "
                         "VecNormalize.normalize_obs")
    if not loaded["norm_obs"]:
        print("note: norm_obs=false — the sidecar records that training used raw "
              "observations; the game passes get_obs() through unchanged")
    print("VERIFICATION OK: saved statistics reproduce the training-time "
          "normalized observations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
