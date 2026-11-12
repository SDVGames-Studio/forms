# HYPERPARAMETERS.md — PPO configuration for the turn-based multi-discrete action space

These are the hyperparameters `train.py` (issue #466) feeds to
Stable-Baselines3 PPO for the Forms training environment, tuned for the
**discrete multi-action space** of issues #422/#467: one
`MultiDiscrete` observation → action mapping with several independent
discrete heads (e.g. `move | aim | attack | target`, see ACTION_SPEC.md §1).
Every value below is overridable on the command line so hyperparameter
sweeps need no code changes, e.g.

```bash
python train.py --learning_rate 3e-4 --ent_coef 0.005 \
    --net_arch 256,256 --n_steps 4096 --batch_size 512
```

## Chosen hyperparameters (issue #467)

| Hyperparameter | Value | CLI argument | Rationale |
|---|---|---|---|
| policy class | `MultiInputPolicy` | — | The environment exposes a dict observation space (OBSERVATION_SPEC.md) with a MultiDiscrete action space; MultiInputPolicy handles the dict input and multi-head output natively. |
| `learning_rate` | `5e-4` | `--learning_rate` | Discrete action spaces tolerate and often benefit from a slightly higher rate than PPO's 3e-4 default (which targets continuous control); 5e-4 speeds head specialization without destabilising the multi-head policy. |
| `ent_coef` | `0.01` | `--ent_coef` | Entropy bonus that keeps exploration alive across **all** action heads simultaneously, so the joint policy does not collapse to one deterministic action per head early in training. |
| `net_arch` (pi and vf) | `[128, 128]` | `--net_arch` | A small two-layer MLP for both policy and value nets; the observation vector is compact (OBSERVATION_SPEC.md) and does not need a large architecture — bigger nets only slow the update loop. |
| `n_steps` | `2048` | `--n_steps` | Rollout length per environment per update; long rollouts give stabler advantage estimates and rarer, more meaningful updates for a turn-based game with sparse shooting rewards. |
| `batch_size` | `256` | `--batch_size` | Minibatch size per gradient step; large enough for low-variance gradients yet small enough for several update epochs per rollout (rollout buffer ÷ 256 minibatches). Must divide `n_steps × n_envs`. |

## Environment / rollout plumbing (issue #466, kept as-is)

| Hyperparameter | Value | CLI argument | Rationale |
|---|---|---|---|
| `n_parallel` | `4` | `--n_parallel` | 4 parallel exported Godot processes; the recommended 4–8 band for a 2D game balances throughput against gateway RAM (~4 GB). |
| `speedup` | `20` | `--speedup` | Physics timestep multiplier; 20 runs the env faster than real time without starving the godot-rl socket loop. |
| `timesteps` | `500000` | `--timesteps` | Default run length: enough for early reward shaping to show; 10k = plumbing check, 10M+ = full training. |
| rollout buffer size | `n_steps × n_envs` | derived | With the defaults and 3 in-scene agents × 4 processes (12 sub-envs) each rollout collects 24576 samples; `train.py` exits early if `batch_size` does not divide it. |

## Values left at SB3 defaults (deliberately)

| Hyperparameter | Value | Rationale |
|---|---|---|
| `gamma` | `0.99` | Turns resolve in tens of steps; a near-1 discount already spans multiple turns. Revisit only if credit assignment across turns proves too long-range. |
| `gae_lambda` | `0.95` | Standard bias/variance compromise; no evidence yet that Forms needs it different. |
| `clip_range` | `0.2` | Conservative updates protect the multi-head policy from destroying one head while another improves. |
| `n_epochs` | `10` | Standard PPO reuse; with 2048-step rollouts this yields ~10 gradient passes per minibatch split. |
| `vf_coef` | `0.5` | Even policy/value weighting; the value head sees the same compact observations. |
| `max_grad_norm` | `0.5` | Guards the multi-head output layer against rare spiky gradients. |
| optimizer | `Adam` (SB3 default) | Default betas/eps are fine for these tiny MLPs. |

## Health check: NaN / policy collapse

A short run with the configured values (issue #467 DoD):

```bash
python train.py --n_parallel=2 --speedup=20 --timesteps=24576 \
    --experiment_dir runs/hp_smoke
```

is expected to finish with `TRAINING OK`, `entropy_loss` staying clearly
negative (heads keep exploring, no collapse to near-zero entropy) and no
`nan` in `ep_rew_mean`/losses. Entropy collapse shows up as `entropy_loss`
approaching 0 for every head while `ep_rew_mean` stagnates — if that
happens, sweep `--ent_coef` upward (0.02) or `--learning_rate` downward.
