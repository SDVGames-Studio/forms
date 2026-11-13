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

## Hyperparameter sweep (issue #470)

`sweep_hparams.py` ran the two most impactful PPO knobs for the discrete
multi-head action space as short same-seed trainings — learning rate
{3e-4, 5e-4, 1e-3} x entropy coefficient {0.001, 0.01, 0.05}, 200k steps
per combination (inside the issue's 200k-500k band), identical seed
(`--seed 0`), parallel-env config (`n_parallel=2`) and `speedup=20` for
every run, so only the hyperparameter pair differs. Six of the nine grid
points completed (both lower learning rates x all three entropy
coefficients); the three `lr=1e-3` runs were aborted repeatedly on the
shared host and the grid was already conclusive at six runs (DoD asks for
>= 6) — `python sweep_hparams.py` resumes the missing row later, skipping
completed points. Runs live under `runs/sweep/<name>/` (distinct
experiment names); compare them side by side with
`tensorboard --logdir runs/sweep`, or read `runs/sweep/summary.json`.

Results (all six runs, 208,896 steps each):

| run | win rate | `ep_rew_mean` (last) | `ep_rew_mean` (AUC) | `entropy_loss` (final) | explained var (final) | collapsed |
|---|---|---|---|---|---|---|
| lr3e-4_ent0.001 | none decided | -0.125120 | -0.125119 | -6.210 | 0.0002 | no |
| lr3e-4_ent0.01 | none decided | -0.125120 | -0.125119 | -6.249 | 0.0002 | no |
| lr3e-4_ent0.05 | none decided | -0.125120 | -0.125119 | -6.315 | 0.0002 | no |
| lr5e-4_ent0.001 | none decided | -0.125120 | -0.125119 | -6.222 | 0.0001 | no |
| lr5e-4_ent0.01 | none decided | -0.125120 | -0.125119 | -6.258 | 0.0001 | no |
| lr5e-4_ent0.05 | none decided | -0.125120 | -0.125119 | -6.317 | 0.0001 | no |

**Selection.** The pre-registered rule (highest last-window `tdm/win_rate`
among non-collapsed runs, ties broken by return AUC then final return)
picks `lr3e-4_ent0.001` — but the margins are ~1e-6, i.e. statistical
noise. **The sweep is flat**: no run produced a single decided episode
(`tdm/timeout_frac` = 1.0 on every dump of every run, episode length pegged
at its 125-step cap), episode return stayed pinned at the idle baseline
(-0.125) for every combination, no action head collapsed, and explained
variance stayed ~0 (the value head learned nothing).

**Rationale / conclusion (issue #470's diagnostic).** Within the swept
range, learning rate and entropy coefficient make no measurable
difference at 200k steps — no combination approaches the scripted
baseline, let alone beats it. Per the issue's own framing this is the
signal that the binding constraint is **not** these hyperparameters but
the reward signal (Phase 4, REWARD_SPEC.md) or the observation design
(Phase 3, OBSERVATION_SPEC.md): the policy sees no gradient toward
deciding episodes. Recommendation: keep `learning_rate=5e-4`,
`ent_coef=0.01` as documented above (nothing in the results argues for a
change), and spend the next effort on reward/observation debugging rather
than further PPO tuning.
