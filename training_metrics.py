#!/usr/bin/env python3
"""Team-deathmatch TensorBoard metrics for the Forms training pipeline (issue #469).

The standard SB3 curves (rollout/ep_rew_mean, rollout/ep_len_mean,
train/policy_loss, train/value_loss, train/entropy_loss, ...) are written by
PPO itself once ``tensorboard_log`` is set in train.py. This module adds the
custom team-deathmatch view through an SB3 ``BaseCallback`` that inspects the
rollout every step and aggregates/logs every ``metrics_every`` timesteps:

  tdm/win_rate                decided episodes won / decided episodes. A
                              decided episode is one whose terminal step
                              carried a REWARD_SPEC §2.9 ``episode_outcome``
                              component (+0.50 win / −0.50 loss); the opponent
                              is the training environment's own scripted side
                              (the Npc teams), so this is the live win rate
                              against the scripted baseline.
  tdm/timeout_frac            episodes ended WITHOUT an outcome (horizon
                              truncations) over all episode ends.
  tdm/avg_episode_length      mean VecMonitor episode length over the window.
  tdm/reward/<component>      mean per-step contribution of each REWARD_SPEC
                              §2 component (damage_dealt, enemy_killed,
                              own_figure_died, friendly_fire,
                              survival_per_turn, positioning, idling,
                              danger_tile_turn_end, episode_outcome) — the
                              per-component reward breakdown.
  tdm/action_dist/<head>/<i>  mean probability of discrete action index i on
                              head <head> (move/aim/attack/target), computed
                              from the policy distribution over a rolling
                              sample of live (VecNormalize-transformed)
                              observations.
  tdm/action_max_prob/<head>  the head's largest action_dist mean — the
                              collapse indicator: one index dominating across
                              all heads means the policy has collapsed and the
                              entropy coefficient (HYPERPARAMETERS.md,
                              ``--ent_coef``) or reward shaping needs a
                              revisit.
  tdm/action_entropy/<head>   mean per-sample entropy of the head's action
                              distribution in nats (ln(k) = perfectly uniform).

The win rate and reward breakdown ride the per-agent info dict the Godot side
fills in ``BotController.get_info()`` (``info["reward_components"]``, the
REWARD_SPEC component names) and reach the callback untouched: godot-rl
forwards the info dicts verbatim and VecNormalize/VecMonitor pass them
through. Environments that do not report them (e.g. the TrainingBot scaffold
of issue #341, whose reward is a flat step cost) are fine — those metric
families simply stay absent until the battlefield agent (BotController) is
wired into the training scene; nothing crashes, nothing logs fake zeros.

Watch the curves live with:

    tensorboard --logdir runs/           # every experiment, or
    tensorboard --logdir runs/tdm_v1     # one experiment

Verified offline (no Godot build needed) by rl_metrics_check.py.
"""

from __future__ import annotations

from collections import defaultdict
from typing import Any, Iterator, Optional

import numpy as np
import torch as th
from gymnasium import spaces
from stable_baselines3.common.callbacks import BaseCallback

# Smoothing across TensorBoard's default slider; keep the raw points dense
# enough that short smoke runs (1k steps) still show a curve per metric.
DEFAULT_METRICS_EVERY = 4096


class TeamDeathmatchMetricsCallback(BaseCallback):
    """SB3 callback logging the #469 team-deathmatch TensorBoard metrics."""

    def __init__(
        self,
        metrics_every: int = DEFAULT_METRICS_EVERY,
        head_names: Optional[list[str]] = None,
        obs_sample_size: int = 256,
        verbose: int = 0,
    ) -> None:
        super().__init__(verbose)
        if metrics_every <= 0:
            raise ValueError(f"metrics_every must be positive, got {metrics_every}")
        self.metrics_every = int(metrics_every)
        self.head_names: Optional[list[str]] = list(head_names) if head_names else None
        self.obs_sample_size = int(obs_sample_size)
        # Resolved in _on_training_start: [(head name, action count), ...].
        self._heads: list[tuple[str, int]] = []
        self._next_log_step = 0
        self._reset_interval()

    # -- interval accumulators -------------------------------------------

    def _reset_interval(self) -> None:
        self._wins = 0
        self._losses = 0
        self._timeouts = 0
        self._episode_lengths: list[float] = []
        self._reward_sums: dict[str, float] = defaultdict(float)
        self._reward_steps = 0
        self._obs_buffer: list[Any] = []

    # -- SB3 callback hooks ----------------------------------------------

    def _on_training_start(self) -> None:
        action_space = self.model.action_space
        if isinstance(action_space, spaces.MultiDiscrete):
            names = self.head_names or [
                f"head_{i}" for i in range(len(action_space.nvec))
            ]
            self._heads = [
                (str(name), int(count)) for name, count in zip(names, action_space.nvec)
            ]
        else:
            # Only MultiDiscrete (multi-head) policies get the action
            # distribution view; everything else still gets win rate,
            # episode length and the reward breakdown.
            self._heads = []
        self._next_log_step = self.metrics_every
        self._reset_interval()

    def _on_step(self) -> bool:
        infos = self.locals.get("infos")
        if infos:
            for info in infos:
                if not isinstance(info, dict):
                    continue
                episode = info.get("episode")
                components = info.get("reward_components")
                if episode is not None:
                    self._episode_lengths.append(float(episode["l"]))
                    if components is not None and "episode_outcome" in components:
                        outcome = float(components["episode_outcome"])
                        if outcome > 0.0:
                            self._wins += 1
                        elif outcome < 0.0:
                            self._losses += 1
                        else:  # an exactly-zero outcome carries no decision
                            self._timeouts += 1
                    else:
                        self._timeouts += 1
                if components:
                    for key, value in components.items():
                        self._reward_sums[str(key)] += float(value)
            self._reward_steps += len(infos)
        if len(self._obs_buffer) < self.obs_sample_size:
            new_obs = self.locals.get("new_obs")
            if new_obs is not None:
                self._obs_buffer.append(new_obs)
        if self.num_timesteps >= self._next_log_step:
            self._log_metrics()
            self._next_log_step += self.metrics_every
        return True

    # -- logging -----------------------------------------------------------

    def _log_metrics(self) -> None:
        decided = self._wins + self._losses
        if decided > 0:
            self.logger.record("tdm/win_rate", self._wins / decided)
        episode_ends = decided + self._timeouts
        if episode_ends > 0:
            self.logger.record("tdm/timeout_frac", self._timeouts / episode_ends)
        if self._episode_lengths:
            self.logger.record(
                "tdm/avg_episode_length", float(np.mean(self._episode_lengths))
            )
        if self._reward_steps > 0:
            for key in sorted(self._reward_sums):
                self.logger.record(
                    f"tdm/reward/{key}", self._reward_sums[key] / self._reward_steps
                )
        head_entropies: dict[str, float] = {}
        if self._heads and self._obs_buffer:
            for name, mean_probs, entropy in self._action_prob_stats():
                head_entropies[name] = entropy
                for idx in range(len(mean_probs)):
                    self.logger.record(
                        f"tdm/action_dist/{name}/{idx}", float(mean_probs[idx])
                    )
                self.logger.record(
                    f"tdm/action_max_prob/{name}", float(mean_probs.max())
                )
                self.logger.record(f"tdm/action_entropy/{name}", entropy)
        self.logger.dump(step=self.num_timesteps)
        if self.verbose > 0:
            decided_msg = (
                f"win_rate={self._wins}/{decided}" if decided else "no decided episodes"
            )
            print(
                f"TDM METRICS step={self.num_timesteps} {decided_msg} "
                f"episodes={episode_ends} heads={list(head_entropies)}"
            )
        self._reset_interval()

    def _action_prob_stats(self) -> Iterator[tuple[str, np.ndarray, float]]:
        """Yield (head name, mean probs, mean entropy) per action head.

        Runs the policy in eval mode over the buffered live observations —
        the same VecNormalize-transformed observations the rollout acts on —
        and reads the MultiCategorical head distributions. Unmasked logits on
        purpose: the distribution IS the policy, masking is a sampling-time
        concern, and a collapse must be visible here regardless of masks.
        """
        policy = self.model.policy
        was_training = policy.training
        policy.eval()
        try:
            with th.no_grad():
                obs = self._merge_obs_batch()
                tensor_obs, _ = policy.obs_to_tensor(obs)
                distribution = policy.get_distribution(tensor_obs)
                # SB3's MultiCategoricalDistribution keeps the per-head
                # Categorical list in .distribution (older naming in some
                # versions: .distributions).
                head_dists = getattr(distribution, "distribution", None)
                if head_dists is None:
                    head_dists = distribution.distributions
                for i, (name, _count) in enumerate(self._heads):
                    probs = head_dists[i].probs  # (batch, count)
                    mean_probs = probs.mean(dim=0).cpu().numpy()
                    entropy = float(
                        -(probs * th.log(probs + 1e-12)).sum(dim=1).mean().item()
                    )
                    yield name, mean_probs, entropy
        finally:
            policy.train(was_training)

    def _merge_obs_batch(self) -> Any:
        """Merge buffered observations into one batch the policy accepts.

        Rollout `new_obs` chunks are already VecEnv-batched (one row per
        sub-env), so concatenating along axis 0 keeps a flat (samples, …)
        batch. Handles dict observations (MultiInputPolicy — entries are
        {key: array}) and flat arrays (MlpPolicy) alike.
        """
        first = self._obs_buffer[0]
        if isinstance(first, dict):
            return {
                key: np.concatenate([obs[key] for obs in self._obs_buffer], axis=0)
                for key in first.keys()
            }
        return np.concatenate(self._obs_buffer, axis=0)
