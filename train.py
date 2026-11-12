#!/usr/bin/env python3
"""PPO training entrypoint for the exported training build (issue #466).

Trains against the exported "Training (Linux)" build from issue #465
(builds/training/forms_training.x86_64) using godot-rl's
StableBaselinesGodotEnv and Stable-Baselines3 PPO — the same stack already
validated end to end by rl_connectivity_test.py (godot-rl 0.8.2 + SB3 2.4.0,
PR #371), but against the real exported binary and with parallel
environment processes instead of a single launcher shim.

Definition of Done (issue #466): running

    python train.py --env_path=builds/training/MyEnv.x86_64 \
        --n_parallel=4 --speedup=20 --timesteps=10000

completes a short training run without socket errors, and the experiment
directory contains a TensorBoard event file (inspect with
`tensorboard --logdir runs/tdm_v1`).

Arguments:
  --env_path        exported training executable. The wrapper appends the
                    platform-specific suffix (.x86_64 / .exe / .app) if the
                    path lacks one, so "builds/training/forms_training"
                    works as well as the suffixed form.
  --n_parallel      number of parallel Godot environment processes, each on
                    its own port (DEFAULT_PORT + index); 4–8 suits a 2D game.
  --speedup         physics timestep multiplier; 20–100 runs the game faster
                    than real time.
  --experiment_dir  dedicated log directory so TensorBoard logs are organized
                    per experiment; the trained model is saved here too.
  --timesteps       total PPO timesteps. 10k proves the plumbing end to end;
                    start with 500k–1M for a smoke training run, then scale
                    to 10M+ for full training.
"""

import argparse
import os
import pathlib
import sys

from stable_baselines3 import PPO
from stable_baselines3.common.vec_env.vec_monitor import VecMonitor

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv

# Mirrors GodotEnv._set_platform_suffix: the suffix godot-rl appends to a
# suffix-less --env_path per platform.
_PLATFORM_SUFFIXES = {"linux": ".x86_64", "win32": ".exe", "darwin": ".app"}


def resolve_env_path(env_path: str) -> str:
    """Return an existing executable path for --env_path, or exit with a
    helpful message. Accepts the path with or without the platform suffix;
    the training build is exported by the "Training (Linux)" preset
    (issue #465)."""
    path = pathlib.Path(env_path).expanduser()
    if path.is_file():
        return str(path)
    suffix = _PLATFORM_SUFFIXES.get(sys.platform)
    if suffix:
        with_suffix = path.with_suffix(suffix)
        if with_suffix.is_file():
            return str(with_suffix)
    sys.exit(
        f"train.py: exported training executable not found: {env_path}\n"
        f"  (also tried the platform-suffixed form). Export the project with\n"
        f"  the \"Training (Linux)\" preset first (issue #465) — it produces\n"
        f"  builds/training/forms_training.x86_64 next to its .pck and the\n"
        f"  libncnn_runner shared library."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--env_path",
        default="builds/training/forms_training.x86_64",
        help="path to the exported training executable; the platform suffix is appended if missing",
    )
    parser.add_argument(
        "--n_parallel",
        type=int,
        default=4,
        help="number of parallel environment processes (4-8 for a 2D game)",
    )
    parser.add_argument(
        "--speedup",
        type=int,
        default=20,
        help="physics timestep multiplier (20-100 to run faster than real time)",
    )
    parser.add_argument(
        "--experiment_dir",
        default="runs/tdm_v1",
        help="dedicated log directory for TensorBoard logs and the final model",
    )
    parser.add_argument(
        "--timesteps",
        type=int,
        default=500_000,
        help="total training timesteps (10k = plumbing check; 500k-1M smoke run; 10M+ full)",
    )
    args = parser.parse_args()

    # Be gentle on shared machines: the nets here are tiny (mirrors
    # rl_connectivity_test.py).
    os.environ.setdefault("OMP_NUM_THREADS", "1")

    env_path = resolve_env_path(args.env_path)
    experiment_dir = pathlib.Path(args.experiment_dir).expanduser()
    experiment_dir.mkdir(parents=True, exist_ok=True)

    # n_parallel Godot processes on consecutive ports; every in-scene agent of
    # every process becomes one SB3 sub-env (VecEnv of n_parallel * agents).
    env = StableBaselinesGodotEnv(
        env_path=env_path,
        n_parallel=args.n_parallel,
        speedup=args.speedup,
    )
    env = VecMonitor(env)

    # PPO hyperparameters mirror godot-rl's stable_baselines3_example and the
    # already-validated connectivity test: MultiInputPolicy over the dict
    # observation space, short rollouts (n_steps=32) for fast learning
    # iterations. tensorboard_log points SB3 at the experiment directory; it
    # writes a runs/<experiment>/PPO_1/events.out.tfevents.* file as it trains.
    model = PPO(
        "MultiInputPolicy",
        env,
        ent_coef=0.0001,
        verbose=2,
        n_steps=32,
        tensorboard_log=str(experiment_dir),
    )
    try:
        model.learn(total_timesteps=args.timesteps)
    finally:
        env.close()

    model_path = experiment_dir / "final_model"
    model.save(str(model_path))
    print(
        f"TRAINING OK: {args.timesteps} timesteps over {args.n_parallel} parallel "
        f"environment(s) at speedup {args.speedup}, no socket errors."
    )
    print(f"MODEL: {model_path}.zip")
    print(f"TENSORBOARD: {experiment_dir} (inspect with: tensorboard --logdir {experiment_dir})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
