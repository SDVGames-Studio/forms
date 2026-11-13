#!/usr/bin/env python3
"""Offline check for the #503 VecNormalize stats sidecar — no Godot needed.

Confirms the Definition of Done of issue #503 from the Python side: applying
the SAVED statistics to a raw observation reproduces the normalized
observation that was fed to the policy during training, i.e. the output of
SB3's own ``VecNormalize.normalize_obs``.

Two layers:

1. Synthetic round-trip (always runs): a tiny gymnasium Box env is wrapped in
   a real ``VecNormalize``, its running stats are serialized with the same
   ``serialize_stats`` used by ``export_vecnormalize_stats.py``, and the
   sidecar replay (``normalize_with_stats`` — the exact formula mirrored by
   addons/godot_native_rl/controllers/obs_normalize.gd) must match
   ``normalize_obs`` across random raw observations, including out-of-clip
   extremes. A second wrapper trained with ``norm_obs=False`` must round-trip
   as raw passthrough.
2. Shipped artifact (when present): models/vecnormalize_stats.json is
   compared against the SB3 object in runs/<...>/vecnormalize.pkl it was
   exported from — skipped on fresh checkouts without training artifacts.

Run: python3 rl_vecnormalize_check.py
Exit code 0 = pass. See DEPLOYMENT.md §4.
"""

import json
import os
import sys

import gymnasium as gym
import numpy as np
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

from export_vecnormalize_stats import (load_vecnormalize, normalize_with_stats,
                                       serialize_stats, training_path_normalize)

OBS_SIZE = 4
SEED = 503


class TinyBoxEnv(gym.Env):
    """Minimal Box-obs env so VecNormalize can be built offline."""

    metadata = {}
    observation_space = gym.spaces.Box(-5.0, 5.0, shape=(OBS_SIZE,), dtype=np.float32)
    action_space = gym.spaces.Discrete(2)

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        return self.observation_space.sample(), {}

    def step(self, action):
        return self.observation_space.sample(), 0.0, False, False, {}


def make_vec_normalize(norm_obs: bool, clip_obs: float, epsilon: float) -> VecNormalize:
    rng = np.random.default_rng(SEED)
    vn = VecNormalize(DummyVecEnv([TinyBoxEnv]), norm_obs=norm_obs, norm_reward=False,
                      clip_obs=clip_obs, epsilon=epsilon)
    if norm_obs:  # a norm_obs=False wrapper has no obs_rms at all (SB3)
        rms = vn.obs_rms
        rms.mean = rng.uniform(-1.0, 1.0, size=OBS_SIZE)
        rms.var = rng.uniform(0.05, 2.0, size=OBS_SIZE)
        rms.count = 1234.0
    return vn


def check_synthetic() -> bool:
    ok = True
    for norm_obs in (True, False):
        vn = make_vec_normalize(norm_obs, clip_obs=3.0, epsilon=1e-8)
        # Same serialization path export_vecnormalize_stats.py takes; a
        # stats-less (inactive) wrapper exports inert zeros of the obs width.
        stats = serialize_stats(vn.obs_rms if norm_obs else None,
                                vn.epsilon, vn.clip_obs, norm_obs, obs_size=OBS_SIZE)
        rng = np.random.default_rng(SEED)
        raws = [rng.uniform(-30.0, 30.0, size=OBS_SIZE) for _ in range(64)]
        raws.append(np.full(OBS_SIZE, 1e4))  # far past clip_obs -> must clamp
        worst = 0.0
        for raw in raws:
            expected = np.asarray(vn.normalize_obs(raw))
            got = normalize_with_stats(raw, stats)
            if norm_obs:
                # SB3 normalizes in float64 then casts to float32 (the dtype
                # the VecEnv fed the policy); the replay does the identical
                # math, so after the same cast the match must be exact. With
                # norm_obs=False SB3 returns the raw obs unchanged (float64).
                got = got.astype(np.float32)
            worst = max(worst, float(np.max(np.abs(got - expected))))
        matches = worst == 0.0
        print(f"synthetic norm_obs={norm_obs}: {len(raws)} obs, max abs diff "
              f"{worst:.3e} -> {'OK' if matches else 'MISMATCH'}")
        ok = ok and matches
    return ok


def check_shipped_artifact() -> bool:
    json_path = "models/vecnormalize_stats.json"
    if not os.path.exists(json_path):
        print(f"shipped artifact: {json_path} not found — skipped (generate it "
              "with export_vecnormalize_stats.py)")
        return True
    with open(json_path) as fh:
        stats = json.load(fh)
    if not stats.get("norm_obs", True):
        print("shipped artifact: norm_obs=false — raw passthrough contract; "
              "nothing to reproduce against SB3")
        return True
    pkl_path = "runs/issue471_check/vecnormalize.pkl"
    if not os.path.exists(pkl_path):
        print(f"shipped artifact: {pkl_path} not found — formula check only")
        # Still verify the JSON is self-consistent (sizes, epsilon, clip).
        sizes_ok = (stats["obs_size"] == len(stats["mean"]) == len(stats["var"])
                    and stats["epsilon"] > 0.0 and stats["clip_obs"] > 0.0)
        print(f"shipped artifact self-consistent={sizes_ok}")
        return sizes_ok
    vn, rms, clip_obs, norm_obs, epsilon = load_vecnormalize(pkl_path)
    source_ok = (np.allclose(stats["mean"], rms.mean, rtol=0, atol=0)
                 and np.allclose(stats["var"], rms.var, rtol=0, atol=0)
                 and stats["epsilon"] == epsilon and stats["clip_obs"] == clip_obs
                 and stats["norm_obs"] == norm_obs)
    print(f"shipped artifact matches {pkl_path}: {source_ok}")
    rng = np.random.default_rng(SEED)
    raws = [rng.uniform(-20.0, 20.0, size=stats["obs_size"]) for _ in range(64)]
    raws.append(np.full(stats["obs_size"], 1e3))
    worst = 0.0
    for raw in raws:
        expected = training_path_normalize(vn, raw)  # float32 (VecEnv cast)
        got = normalize_with_stats(raw, stats).astype(np.float32)
        worst = max(worst, float(np.max(np.abs(got - expected))))
    matches = source_ok and worst == 0.0
    print(f"shipped artifact replay: {len(raws)} obs, max abs diff {worst:.3e} "
          f"-> {'OK' if matches else 'MISMATCH'}")
    return matches


def main() -> int:
    ok = check_synthetic() and check_shipped_artifact()
    print("VERIFICATION OK" if ok else "VERIFICATION FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
