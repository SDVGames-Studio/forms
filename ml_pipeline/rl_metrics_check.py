#!/usr/bin/env python3
"""Offline check for the #469 TensorBoard metrics — no Godot build needed.

Trains PPO for a few hundred steps on a miniature team-deathmatch stand-in
(same MultiDiscrete [6, 3, 8, 4] heads, per-step reward_components in the
info dict, alternating decided episode outcomes, 20-step episodes) with
TeamDeathmatchMetricsCallback attached, then reads the TensorBoard event
file back and asserts the issue's Definition of Done:

  - at least three standard SB3 metrics among rollout/* and train/*,
  - the three custom metric families present and UPDATING (>= 2 points):
    win rate (tdm/win_rate), action distribution
    (tdm/action_dist/<head>/<index>), reward breakdown (tdm/reward/<c>),
    plus episode length (tdm/avg_episode_length).

Run: python3 rl_metrics_check.py
Exit code 0 = pass. See train.py for the real-environment entrypoint.
"""

import pathlib
import shutil
import sys
import tempfile

import gymnasium as gym
import numpy as np
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv, VecMonitor
from tensorboard.backend.event_processing.event_accumulator import EventAccumulator

from training_metrics import TeamDeathmatchMetricsCallback

# The training scene's action heads (TrainingBot.get_action_space, #422).
NVEC = [6, 3, 8, 4]
HEAD_NAMES = ["move", "aim", "attack", "target"]
EPISODE_LENGTH = 20


class MiniTdmEnv(gym.Env):
    """Smallest env that speaks the #469 wire protocol.

    Flat 4-float observation, the game's multi-discrete action space, a
    20-step episode, and info dicts shaped exactly like the Godot side's:
    reward_components with REWARD_SPEC names every step (damage_dealt,
    survival_per_turn) and a decided ±0.50 episode_outcome on terminal
    steps (alternating win/loss, so the expected win rate is ~0.5).
    """

    metadata = {"render_modes": []}

    def __init__(self) -> None:
        super().__init__()
        self.observation_space = gym.spaces.Box(
            low=-1.0, high=1.0, shape=(4,), dtype=np.float32
        )
        self.action_space = gym.spaces.MultiDiscrete(NVEC)
        self._step_in_episode = 0
        self._win = True

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        self._step_in_episode = 0
        return self.observation_space.sample(), {}

    def step(self, action):
        self._step_in_episode += 1
        terminated = self._step_in_episode >= EPISODE_LENGTH
        components = {"damage_dealt": 0.03, "survival_per_turn": 0.02}
        if terminated:
            # Alternate win/loss so win_rate converges near 0.5 and the
            # timeout fraction stays 0 — both are asserted below.
            self._win = not self._win
            components["episode_outcome"] = 0.5 if self._win else -0.5
        obs = self.observation_space.sample()
        return obs, float(sum(components.values())), terminated, False, {
            "reward_components": components
        }


def main() -> int:
    run_dir = pathlib.Path(tempfile.mkdtemp(prefix="issue469_check_"))
    experiment_dir = run_dir / "mini_tdm"
    try:
        env = VecMonitor(DummyVecEnv([MiniTdmEnv for _ in range(2)]))
        model = PPO(
            "MlpPolicy",
            env,
            n_steps=64,
            batch_size=32,
            ent_coef=0.01,
            tensorboard_log=str(experiment_dir),
            verbose=0,
        )
        metrics_every = 128
        callback = TeamDeathmatchMetricsCallback(
            metrics_every=metrics_every, head_names=HEAD_NAMES
        )
        # 640 steps = 5 metric dumps + >=1 PPO update (train/* tags exist).
        model.learn(total_timesteps=640, callback=[callback])
        env.close()

        event_dirs = sorted(experiment_dir.glob("PPO_*"))
        assert event_dirs, f"no PPO_* TensorBoard run dir under {experiment_dir}"
        accumulator = EventAccumulator(str(event_dirs[-1]))
        accumulator.Reload()
        scalars = accumulator.Tags().get("scalars", [])
        points = {tag: accumulator.Scalars(tag) for tag in scalars}

        def ok(cond: bool, message: str) -> bool:
            print(("PASS " if cond else "FAIL ") + message)
            return cond

        all_ok = True

        standard = [tag for tag in scalars if tag.startswith(("rollout/", "train/"))]
        all_ok &= ok(
            len(standard) >= 3,
            f"standard SB3 metrics >= 3 (got {len(standard)}: {sorted(standard)})",
        )

        required = (
            ["tdm/win_rate", "tdm/avg_episode_length", "tdm/reward/damage_dealt",
             "tdm/reward/survival_per_turn", "tdm/reward/episode_outcome"]
            + [f"tdm/action_dist/move/{i}" for i in range(NVEC[0])]
            + [f"tdm/action_dist/target/{i}" for i in range(NVEC[3])]
            + [f"tdm/action_max_prob/{h}" for h in HEAD_NAMES]
            + [f"tdm/action_entropy/{h}" for h in HEAD_NAMES]
        )
        missing = [tag for tag in required if tag not in points]
        all_ok &= ok(not missing, f"all custom metric tags present (missing: {missing})")

        updating = [tag for tag in required if len(points.get(tag, [])) >= 2]
        static = [tag for tag in required if tag in points and len(points[tag]) < 2]
        all_ok &= ok(
            not static,
            f"every custom metric updates over training steps (static: {static})",
        )

        if "tdm/win_rate" in points:
            rates = [p.value for p in points["tdm/win_rate"]]
            all_ok &= ok(
                all(0.0 <= r <= 1.0 for r in rates),
                f"win_rate in [0, 1] (values: {[round(r, 3) for r in rates]})",
            )
        if "tdm/reward/damage_dealt" in points:
            means = [p.value for p in points["tdm/reward/damage_dealt"]]
            all_ok &= ok(
                all(abs(m - 0.03) < 0.01 for m in means),
                f"damage_dealt mean per step ~ 0.03 (values: {means})",
            )
        for head in HEAD_NAMES:
            tag = f"tdm/action_dist/{head}/0"
            if tag in points:
                probs = [
                    (tag, p.value)
                    for tag, p in (
                        (t, points[t][-1]) for t in points
                        if t.startswith(f"tdm/action_dist/{head}/")
                    )
                ]
                total = sum(value for _tag, value in probs)
                all_ok &= ok(
                    abs(total - 1.0) < 1e-3,
                    f"{head} mean action probs sum to 1.0 (got {total:.4f})",
                )

        print(f"METRICS CHECK {'OK' if all_ok else 'FAILED'} — {len(scalars)} scalar tags")
        if all_ok:
            print("Sample tags:", sorted(scalars)[:12], "...")
        return 0 if all_ok else 1
    finally:
        shutil.rmtree(run_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
