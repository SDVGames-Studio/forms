# REWARD_SPEC.md — per-step reward contract for the training pipeline

This file is the **single source of truth** for every reward component of
the RL training environment (issue #432). It is written *before*
implementation, and the three follow-up issues consume it directly:

- **#433** — accumulate the combat components (damage, kills, deaths,
  friendly fire) on the agent controller,
- **#434** — cover / influence positioning, survival, danger-tile and
  idling terms,
- **#436** — normalize, clip, and log the final per-step reward using the
  magnitude budget in §3.

Any change to a component below is a spec change: update this file in the
same PR, exactly like `OBSERVATION_SPEC.md` / `ACTION_SPEC.md`.

## 1. Design principles

- **One float per decision step.** The environment evaluates its
  `Reward` (addon `godot_native_rl/reward/`) once per `NcnnSync` decision
  step for each agent; that summed value is the step reward the Python
  trainer sees. All components are ordinary floats — no integers, no
  dictionaries on the wire.
- **Events vs. shaping vs. per-turn upkeep.** Discrete game events
  (damage, kills, deaths, friendly fire, idle turn, danger-tile turn
  end) are `event_bonus` terms fired through signals; positioning is a
  potential-based `progress_shaping` term (path-invariant, no camping
  reward); survival is an `alive_bonus` credited once per own turn.
- **No double counting.** Survival (+) replaces a generic step penalty
  (−): rewarding both would tax staying alive twice. Idling is punished
  only on turns the agent actually chose commands on (a turn that expires
  while the controller has no command slot is not "idling" — the agent
  had no choice).
- **Everything is computable from game state the environment already
  owns.** Components never read the observation vector; they read the
  scene. §5 records which of them the *policy* can also see (learnability
  cross-check against Phase 3).

## 2. Components

Every planned component, with the five required fields. `MAX_HEALTH`
is `CharacterStats.MAX_HEALTH = 100`; the [0, 1] damage fraction is
`damage / 100.0`.

### 2.1 `damage_dealt` — combat

| Field | Value |
|---|---|
| Triggering event | a projectile/explosion the controlled agent owns deals `damage > 0` to an enemy figure (`health` drops before → after) |
| Magnitude | `+0.15 × damage_fraction`, capped at **+0.30 per step** (several hits in one step amortize into the cap) |
| Sign | positive |
| Frequency | per event (cap per step) |
| Rationale | rewards attacking enemies proportionally to damage; the cap keeps a multi-hit step from drowning every other signal |

### 2.2 `enemy_killed` — combat

| Field | Value |
|---|---|
| Triggering event | an enemy figure's `health` crosses ≤ 0 while the killing damage is attributed to the agent |
| Magnitude | **+0.50** flat |
| Sign | positive |
| Frequency | per event |
| Rationale | a removal is worth more than the raw damage that caused it — empty slots shrink the enemy's future action budget. The killing blow pays this bonus INSTEAD of the §2.1 damage tick (no stacking, issue #433), so a kill always outscores the same damage dealt non-lethally |

### 2.3 `own_figure_died` — combat

| Field | Value |
|---|---|
| Triggering event | the controlled figure's `health` crosses ≤ 0 |
| Magnitude | **−0.50** flat |
| Sign | negative |
| Frequency | per event (at most once per figure) |
| Rationale | the controlled figure is the agent's only means of acting; losing it is the single worst non-terminal outcome. After it fires, all further per-step components read 0 (no-figure fallback state) |

### 2.4 `survival_per_turn` — upkeep

| Field | Value |
|---|---|
| Triggering event | the agent's own turn starts while its controlled figure is alive |
| Magnitude | **+0.02 × hp_fraction** (≤ +0.02; issue #434) |
| Sign | positive |
| Frequency | per turn |
| Rationale | small constant pressure against suicidal play; deliberately tiny so camping is never more profitable than fighting (a full idle turn nets +0.02 − 0.05 idling < 0). Since #434 the bonus scales with the remaining HP fraction (issue DoD): a battered figure keeps only part of it, rewarding cautious play without raising the ceiling |

### 2.5 `positioning` — cover / influence (shaping)

| Field | Value |
|---|---|
| Triggering event | every decision step of the agent's own turn: potential difference of the tile-quality score Φ ∈ [0, 1] (cover from line-of-fire + influence-map strength of the figure's current tile) |
| Magnitude | **±0.10 × ΔΦ** per step (the shaped term is `0.10 × (Φ_now − Φ_turn_start)`, rebased at turn start) |
| Sign | either (gains +, losses −) |
| Frequency | per step (potential-based, so the total over a turn depends only on start and end tiles — repositioning smarter, not moving more) |
| Rationale | teaches taking cover and contested ground without rewarding motion itself; Φ's definition (line-of-sight occlusion + influence map) landed with #434 as the minimal cover term: the fraction of alive enemies within ATTACK_REACH whose straight fire line to the figure is occluded by world geometry (collision layer 1 ground, destructible and indestructible alike); a tile no enemy can reach scores Φ = 1.0. The influence-map half (Phase 1 optional / Phase 3 dependent, does not exist yet) stays deferred — Φ is pure cover until that map lands. `get_reward_affordances()` exposes `tile_quality` + `rebase_on` = own-turn start since #434 |

### 2.6 `friendly_fire` — combat

| Field | Value |
|---|---|
| Triggering event | a projectile/explosion the agent owns damages a figure on its own team |
| Magnitude | `−0.10 × damage_fraction`, floored at **−0.30 per step** |
| Sign | negative |
| Frequency | per event (floor per step) |
| Rationale | blast-radius weapons (grenade, rocket, mine) make careless shots near allies possible; the penalty scales with the damage actually caused |

### 2.7 `idling` — tempo

| Field | Value |
|---|---|
| Triggering event | the agent's own turn ends with every command slot neutral (`HOLD`/`IDLE`-only) while ≥ 1 enemy is visible (`ACTION_SPEC` §1 predicate: alive + opposing side + within `ATTACK_REACH = 620`) |
| Magnitude | **−0.05** |
| Sign | negative |
| Frequency | per turn |
| Rationale | with a visible enemy every attack index is legal, so passing is a choice, not a constraint; punishes passive stalling without touching legitimate repositioning turns (movement ≠ neutral) |

### 2.8 `danger_tile_turn_end` — positioning

| Field | Value |
|---|---|
| Triggering event | the agent's own turn ends while its figure stands on a danger tile (inside an enemy's current line-of-fire band, or on blast-danger ground — the tile set #434 formalizes as: an alive enemy within ATTACK_REACH holds a clear, unoccluded fire line onto the figure's tile, i.e. danger ⟺ Φ < 1) |
| Magnitude | **−0.05** |
| Sign | negative |
| Frequency | per turn |
| Rationale | exposes the figure to free damage during the enemy turn; distinct from §2.5 (a one-shot end-state penalty, not a shaped gradient) |

### 2.9 `episode_outcome` — termination (the one extra category)

| Field | Value |
|---|---|
| Triggering event | episode ends: own team is the only side with alive figures (+) / own side is wiped or the controlled figure's team loses (−) |
| Magnitude | **±0.50** flat |
| Sign | win +, loss − |
| Frequency | per episode (terminal step only) |
| Rationale | anchors credit assignment to the objective; the only terminal-only component — exempt from the steady-state budget in §3 |

## 3. Total expected per-step magnitude (normalization target for #436)

| Situation | Sum |
|---|---|
| Quiet step (own turn, no combat events) | +0.02×hp survival ± 0.10·ΔΦ positioning → **\|r\| ≤ 0.12**, typically ≈ 0.02–0.06 |
| Best non-terminal combat step | +0.30 damage cap + 0.50 kill + 0.02 + 0.10 = **+0.92** |
| Worst non-terminal step | −0.30 friendly-fire floor − 0.05 idle − 0.05 danger = **−0.40**; with own death **−0.90** |
| Terminal step | ±0.50 outcome on top of the above (e.g. −0.50 death − 0.50 loss = −1.00; +0.50 win + 0.50 kill ≤ +1.50) |

Target for #436: **every non-terminal per-step reward is already inside
[−1, +1] by construction** — no clipping needed outside terminal steps;
terminal steps clip to ±1.0 before logging. Expected steady-state
magnitude is ≈ 0.05, so a running-return normalizer sees a healthy
event/baseline contrast (events are 10–20× the upkeep signal). If a
component magnitude is ever retuned, re-derive this table in the same
change.

## 4. Implementation mapping (the `RewardBuilder` vocabulary)

| Component | Term type (`reward_builder.gd`) | Wiring |
|---|---|---|
| `damage_dealt` | `event_bonus("damage_dealt", …)` | signal emitted by the damage attribution path (#433) |
| `enemy_killed` | `event_bonus("enemy_killed", 0.5)` | signal on enemy death with agent attribution (#433) |
| `own_figure_died` | `event_bonus("own_figure_died", -0.5)` | signal on controlled-figure death (#433) |
| `survival_per_turn` | `alive_bonus(0.02)` | credited at own-turn start, HP-scaled (≤ +0.02) since #434 |
| `positioning` | `progress_shaping(value_fn = tile_quality Φ, scale = 0.10, rebase_on = ["own_turn_start"])` | Φ = minimal cover check on the level since #434 (influence half deferred); TurnController → notify_own_turn_* |
| `friendly_fire` | `event_bonus("friendly_fire", …)` | same attribution path, own-side victim (#433) |
| `idling` | `event_bonus("idle_turn", -0.05)` | signal at turn end after command audit (#434) |
| `danger_tile_turn_end` | `event_bonus("danger_tile_turn_end", -0.05)` | signal at turn end from the #434 tile set (TurnController → BotController) |
| `episode_outcome` | `event_bonus("episode_won"/"episode_lost", ±0.5)` | signals from the episode-end handler |

The four combat signals (`damage_dealt`, `enemy_killed`, `own_figure_died`,
`friendly_fire`) are declared and emitted since #433. The survival,
positioning (Φ — minimal cover-only definition), idle and danger-tile
signals/value functions are declared and emitted since #434; the
`episode_outcome` signals are declared and emitted since #437 (TurnController
→ notify_episode_outcome → game_over()). Recipes built from this
spec are validated against the manifest by `RewardRecipe.validate()`:
an unemitted signal fails loud, so the spec and the code cannot drift
apart silently.

## 5. Phase 3 review — observability & choosability (DoD)

Every rewarded event must be **observable** in `OBSERVATION_SPEC.md`
(the policy can only learn to predict rewards it can see) and every
penalized behavior must be **choosable** in `ACTION_SPEC.md` (punishing
an unchoosable action is noise).

| Component | Observable? (50-float `BotController` vector; team block since #447) | Choosable? |
|---|---|---|
| `damage_dealt` / `enemy_killed` | yes — enemy slots report `hp_frac` (idx 4–23), drops are visible | yes — `attack` 1–7 (7 weapon slots), `target` 1–3, `ATTACK_ENEMY_A/B` |
| `own_figure_died` | yes — `own.hp_frac` (idx 0) → 0, then the no-figure fallback vector | indirect — the agent avoids it via movement and cover; that is the point |
| `survival_per_turn` | yes — own `hp_frac`/`shield` | n/a (upkeep, not an action) |
| `positioning` | **partial** — enemy/ally relative positions (idx 4–43) make distance-based influence inferable, but cover/line-of-fire occlusion is **not** in the vector | yes — `move` walk/jump indices; note: walk is ±8 px/step and jump/backflip are declared-not-yet-actuated (ACTION_SPEC §1), so repositioning authority is limited today |
| `friendly_fire` | yes — ally slots report `hp_frac` (idx 24–43) | yes — every weapon can be fired; nothing masks shots near allies (by design: it must remain a choosable mistake) |
| `idling` | yes — enemy slots non-zero ⇒ "visible enemy" is derivable from obs exactly as the mask computes it | yes — `move` 0 hold / `action` 0 `IDLE` / `skip turn` 5 are always legal |
| `danger_tile_turn_end` | **gap** — enemy positions/velocities (idx 4–23) bound the line-of-fire band, but the danger-tile set itself is env-side (#434) | yes — movement + skip turn end the turn on a chosen tile |
| `episode_outcome` | yes — team HP distribution across all slots | n/a (termination) |

**Two flagged gaps** (both already scoped to #434, recorded here so the
review is honest): a cover/occlusion channel and a danger-tile channel
are absent from the 46-float observation. Until they land, positioning
and danger-tile components are still *correct* rewards (they shape real
behavior) but only partially *learnable* from observations; #434 chose
to accept the proxy signal from enemy relative positions (no
observation-vector change in that slice — extending it stays a spec
change to `OBSERVATION_SPEC.md`).

## Maintenance

This file travels with the code: anyone adding, retuning, or removing a
reward term must update §2 (the five fields), re-derive §3 (the budget),
and re-run the §5 cross-check against the current
`OBSERVATION_SPEC.md` / `ACTION_SPEC.md` — in the same change (#436's
clipping constants are derived from §3, not chosen freely).
