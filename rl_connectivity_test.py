#!/usr/bin/env python3
"""Connectivity test: NcnnSync bridge <-> standard godot-rl Python trainer (issue #356).

Validates that the godot_native_rl NcnnSync node speaks the stock godot-rl wire
protocol end to end:

1. Launches this project's ``training_scene.tscn`` headless under a Godot binary
   (via a tiny launcher shim — godot-rl expects an exported-style executable
   named ``*.x86_64`` on Linux).
2. Runs the standard trainer side from the ``godot-rl`` pip package with PPO from
   Stable-Baselines3, mirroring godot_rl's ``examples/stable_baselines3_example.py``
   (StableBaselinesGodotEnv -> VecMonitor -> PPO("MultiInputPolicy")).
3. Performs a short training run (a few dozen steps) and reports the number of
   observation/action exchanges.

Success criteria (issue #356 Definition of Done): the run completes without
socket errors, and the NcnnSync node stays in TRAINING mode exchanging data with
the Python trainer — visible as godot-rl's "connection established" plus the PPO
step logs below, with no NcnnSync "couldn't connect to Python server" fallback.

The non-default --port proves the command-line plumbing (--port/--env_seed) that
the trainer passes through to NcnnSync.

Usage (inside a venv with ``pip install godot-rl stable-baselines3``):

    python rl_connectivity_test.py --godot /usr/local/bin/godot --steps 96
"""

import argparse
import os
import shutil
import stat
import sys
import tempfile

from stable_baselines3 import PPO
from stable_baselines3.common.vec_env.vec_monitor import VecMonitor

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
SCENE = "res://training_scene.tscn"


def make_launcher_shim(godot_bin: str, scene: str, out_dir: str) -> str:
    """godot-rl only launches env executables with a platform suffix (.x86_64 on
    Linux). A three-line shim gives it what it expects while running the training
    scene headless from this source checkout under the local Godot binary; the
    trainer's own flags (--port/--env_seed/--action_repeat/...) are forwarded."""
    shim = os.path.join(out_dir, "forms-headless.x86_64")
    with open(shim, "w") as f:
        f.write(
            "#!/usr/bin/env bash\n"
            f"exec '{godot_bin}' --headless --path '{REPO_ROOT}' '{scene}' \"$@\"\n"
        )
    os.chmod(shim, os.stat(shim).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return shim


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", default="/usr/local/bin/godot", help="Godot binary to run the scene with")
    parser.add_argument("--scene", default=SCENE, help="Training scene resource path")
    parser.add_argument("--port", type=int, default=12008, help="TCP port for the trainer <-> NcnnSync link")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--steps", type=int, default=96, help="Total environment steps for the short PPO run")
    parser.add_argument("--n-steps", type=int, default=32, help="PPO rollout length (per env), as in the gdrl example")
    parser.add_argument(
        "--expected-policies",
        type=int,
        default=None,
        help="Assert this many distinct policy_name values in the handshake (issue #445); default: report only",
    )
    args = parser.parse_args()

    # Be gentle on shared machines: the nets here are tiny.
    os.environ.setdefault("OMP_NUM_THREADS", "1")

    out_dir = tempfile.mkdtemp(prefix="rl-connectivity-")
    shim = make_launcher_shim(args.godot, args.scene, out_dir)

    base_env = StableBaselinesGodotEnv(env_path=shim, port=args.port, seed=args.seed, speedup=1)

    # Issue #445: the handshake's agent_policy_names lists one policy_name per
    # in-scene agent. Bots of the same role share a name (one shared network);
    # distinct roles must report distinct names, and every agent sharing a name
    # must return identical obs/action spaces (guarded game-side by
    # tests/test_issue445.gd). SB3 itself trains a single shared policy over
    # all agents, so the count below is the game's declared role layout.
    policy_names = list(getattr(base_env.envs[0], "agent_policy_names", []))
    distinct_policies = sorted(set(policy_names))
    assert policy_names, "handshake carried no agent_policy_names"
    assert len(policy_names) == base_env.envs[0].num_envs, (
        f"policy names ({len(policy_names)}) do not line up with agents ({base_env.envs[0].num_envs})"
    )
    if args.expected_policies is not None:
        assert len(distinct_policies) == args.expected_policies, (
            f"expected {args.expected_policies} distinct policies, got {distinct_policies}"
        )

    # Count the actual wire exchanges (each VecEnv step == one step message with
    # observations sent and actions received for every in-scene agent).
    exchanges = {"steps": 0}
    original_step = base_env.step

    def counting_step(action):
        obs, rewards, dones, infos = original_step(action)
        exchanges["steps"] += 1
        return obs, rewards, dones, infos

    base_env.step = counting_step

    env = VecMonitor(base_env)
    model = PPO("MultiInputPolicy", env, ent_coef=0.0001, verbose=2, n_steps=args.n_steps)
    try:
        model.learn(total_timesteps=args.steps)
    finally:
        env.close()
        shutil.rmtree(out_dir, ignore_errors=True)

    n_agents = model.get_env().num_envs
    print(
        f"CONNECTIVITY OK: {exchanges['steps']} trainer steps x {n_agents} agents "
        f"({exchanges['steps'] * n_agents} observation/action exchanges) with no socket errors"
    )
    print(
        f"POLICIES OK: {len(distinct_policies)} distinct policy_name(s) across "
        f"{len(policy_names)} agents: {', '.join(distinct_policies)} — no space-mismatch errors"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
