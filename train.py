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

The PPO hyperparameters for the discrete multi-action space are tuned per
issue #467 (learning_rate 5e-4, ent_coef 0.01, [128, 128] MLP, n_steps 2048,
batch_size 256); every value and its rationale is documented in
HYPERPARAMETERS.md and each is overridable on the command line for sweeps.

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
  --learning_rate   PPO learning rate (issue #467: 5e-4 suits the discrete
                    multi-action space; SB3's 3e-4 default targets continuous
                    control).
  --ent_coef        entropy coefficient (issue #467: 0.01 keeps every action
                    head exploring instead of collapsing to one action).
  --net_arch        policy/value MLP hidden widths, comma-separated
                    ("128,128" or "256,256") — the observation vector is
                    compact and needs no large network.
  --n_steps         rollout steps per environment per update (2048 balances
                    sample efficiency and update stability).
  --batch_size      minibatch size per gradient step (256; must divide
                    n_steps × n_envs).
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


def parse_net_arch(spec: str) -> list[int]:
    """Parse a comma-separated MLP width spec like "128,128" into [128, 128]."""
    try:
        arch = [int(width.strip()) for width in spec.split(",")]
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"net arch must be comma-separated ints, got {spec!r} (e.g. 128,128)"
        ) from None
    if not arch or any(width <= 0 for width in arch):
        raise argparse.ArgumentTypeError(
            f"net arch widths must be positive, got {spec!r}"
        )
    return arch


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
    parser.add_argument(
        "--learning_rate",
        type=float,
        default=5e-4,
        help="PPO learning rate (discrete multi-action spaces benefit from slightly above the 3e-4 default)",
    )
    parser.add_argument(
        "--ent_coef",
        type=float,
        default=0.01,
        help="entropy coefficient; keeps all action heads exploring instead of collapsing to a single action",
    )
    parser.add_argument(
        "--net_arch",
        type=parse_net_arch,
        default=parse_net_arch("128,128"),
        help="policy+value MLP hidden widths, comma-separated (e.g. 128,128 or 256,256)",
    )
    parser.add_argument(
        "--n_steps",
        type=int,
        default=2048,
        help="rollout steps per environment per update (balances sample efficiency and update stability)",
    )
    parser.add_argument(
        "--batch_size",
        type=int,
        default=256,
        help="minibatch size per gradient step (must divide n_steps * n_envs)",
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

    # PPO configuration for the MultiDiscrete action space (issue #467, full
    # rationale in HYPERPARAMETERS.md): 5e-4 learning rate and 0.01 entropy
    # coefficient for the discrete heads, a small [128, 128] MLP for both
    # policy and value nets (the observation vector is compact), and long
    # 2048-step rollouts cut into 256-sample minibatches. tensorboard_log
    # points SB3 at the experiment directory; it writes a
    # runs/<experiment>/PPO_1/events.out.tfevents.* file as it trains.
    rollout_size = args.n_steps * env.num_envs
    if rollout_size % args.batch_size != 0:
        sys.exit(
            f"train.py: batch_size {args.batch_size} does not divide the rollout "
            f"buffer (n_steps {args.n_steps} x n_envs {env.num_envs} = "
            f"{rollout_size}); pick a batch_size that divides {rollout_size}."
        )
    policy_kwargs = {"net_arch": {"pi": args.net_arch, "vf": args.net_arch}}
    model = PPO(
        "MultiInputPolicy",
        env,
        learning_rate=args.learning_rate,
        ent_coef=args.ent_coef,
        n_steps=args.n_steps,
        batch_size=args.batch_size,
        policy_kwargs=policy_kwargs,
        verbose=2,
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
    print(
        f"CONFIG: lr={args.learning_rate} ent_coef={args.ent_coef} "
        f"net_arch={args.net_arch} n_steps={args.n_steps} "
        f"batch_size={args.batch_size} (see HYPERPARAMETERS.md)"
    )
    print(f"MODEL: {model_path}.zip")
    print(f"TENSORBOARD: {experiment_dir} (inspect with: tensorboard --logdir {experiment_dir})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
