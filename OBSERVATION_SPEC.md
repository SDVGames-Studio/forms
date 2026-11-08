# OBSERVATION_SPEC.md — Godot → Python observation contract

This file locks down the observation half of the I/O contract between the
Godot environment and the Python training pipeline (godot-rl
`StableBaselinesGodotEnv`). **Update this file whenever an observation
space changes** — a silent dimension or range change breaks the trained
policy without any error.

## Wire format

Every agent extends `NcnnAIController2D` (addon
`godot_native_rl/controllers/ncnn_ai_controller_2d.gd`) and returns a
`Dictionary` from `get_obs()`. The trainer reads exactly **one key,
`"obs"`**, whose value is a flat `Array` of floats. The base class
derives the observation space declaration
`{"obs": {"size": [len], "space": "box"}}` from `get_obs()` output, so
**the flat length must never change between steps** — pad, never drop.

Two controllers implement the contract today:

| Controller | Scene | Flat length |
|---|---|---|
| `BotController.gd` | battlefield levels (`Level*.tscn`) | **46** |
| `TrainingBot.gd` | `training_scene.tscn` | **2** |

## Normalization policy (issue #420)

Every float returned by any `get_obs()` implementation is **strictly
bounded**: signed slots (relative positions, velocities) are clamped to
[-1, 1], fraction/flag slots (HP, shield, cooldowns, arena position
fractions) to [0, 1], and booleans are exactly `0.0`/`1.0`. Raw world
coordinates or unscaled HP values never leave a controller — ONNX/ncnn
inference does not replicate training-framework preprocessing, so the
normalization is baked into the environment itself. The bounds are
enforced by `tests/test_issue420.gd`, which sweeps both controllers
across multiple game states (extreme offsets, overspeed velocities,
over-max HP, saturated cooldowns, overflow teams, the no-figure
fallback, and the scaffold bot drifting off the arena).
Issue #421 adds `tests/test_issue421.gd`: it drives a running episode for
both controllers, reconstructs each full vector from world state using
only the formulas in this file — the same construction a Python-side
wrapper performs — and compares field by field (structure, key set,
data types, lengths, order, and values); the sampled vectors are printed
on pass.

## 1. `BotController.gd` — battlefield observation (46 floats)

**Frame (issue #419):** every positional and velocity value is expressed
in the **agent's local frame** — the controlled figure's own coordinate
space, where local **+X is its facing direction**. Positions go through
Godot's `to_local()`; velocities are rotated by the inverse of the
figure's rotation (2D equivalent of
`global_transform.basis.orthonormalized().inverse() * linear_velocity`).
The observation is therefore **translation- and rotation-invariant**: an
enemy straight ahead always reports `rel_x > 0`, moving forward always
reports `vel_x > 0`, whatever the agent's world position and rotation.
With `rotation == 0` the local frame equals the world frame (issue #381
behavior). When no figure is bound, the controller node itself is the
frame.

Layout: `own (4) + enemies (4×5) + allies (4×5) + cooldowns (2) = 46`,
flattened in exactly this key order: `"own"`, `"enemies"`, `"allies"`,
`"cooldowns"`.

| Indices | Group | Values |
|---|---|---|
| 0–3 | own | `hp_frac`, `shield`, `vel_x`, `vel_y` |
| 4–23 | enemies (4 slots, nearest first) | `rel_x`, `rel_y`, `hp_frac`, `vel_x`, `vel_y` per slot |
| 24–43 | allies (4 slots, nearest first) | same 5 values per slot |
| 44–45 | cooldowns | `fire_frac`, `jump_frac` |

### Per-value normalization (all values pre-normalized; no raw stats leave the controller)

| Value | Formula | Range |
|---|---|---|
| `rel_x` | `clampf(local.x / 576.0, -1, 1)` — `local = frame.to_local(target.global_position)` (issue #419; `local.x` = component along the agent's facing direction) | [-1, 1] |
| `rel_y` | `clampf(local.y / 376.0, -1, 1)` — same `local`; `local.y` is the lateral (local up/down) component | [-1, 1] |
| `hp_frac` | `clampf(health / 100, 0, 1)` (`CharacterStats.MAX_HEALTH = 100`) | [0, 1] |
| `shield` | `1.0` if figure `shielded` else `0.0` (issue #221 shield fills the AP slot; Forms has no AP stat) | {0, 1} |
| `vel_x`, `vel_y` | `clampf(v_local / 320.0, -1, 1)`, `v_local = velocity.rotated(-frame.global_rotation)` (`CharacterStats.SPEED = 320.0`); applies to the `own` block too | [-1, 1] |
| `fire_frac` | `clampf(_cooldown_left / 2.0, 0, 1)` (`FIRE_CD_MAX`, Npc.gd easy AI fire pause) | [0, 1] |
| `jump_frac` | `clampf(_jump_left / 1.0, 0, 1)` (`JUMP_CD_MAX`, Npc.gd jump cooldown) | [0, 1] |

Position divisors 576.0 / 376.0 are the Level.tscn arena half-extents
(playable column 1152×752), so a figure on the opposite side of the arena
maps to ≈[-1, 1] before clamping.

### Slot semantics

- **Origin & frame** is the controlled figure's global transform
  (`to_local()` of it yields the reported offsets; the controller node's
  own when no figure is bound). The nearest-first sort still uses plain
  world-space distance, which is frame-independent.
- **Enemy/ally slots**: `OBS_SLOTS = 4` each, sorted nearest-first by
  squared distance (ties broken by node name). Unused slots are padded
  with five `0.0`s — the length is constant whatever happens on the
  battlefield. The own figure never appears in the allies block.
- **Sides**: the controller fights for the side its figure is NOT in —
  a `player_team` figure observes `enemy_team` figures as enemies, and
  vice versa. Without a bound figure the default enemy-side view is
  `player_team`.
- **Visibility**: every alive figure (`health > 0`) counts; Forms has no
  fog or line-of-sight occlusion. `Player.gd` has no cooldown stat, so
  its cooldown slots read 0.
- **No-figure fallback** (all figures down/dead): the vector stays
  well-formed — `own = [1.0, 0.0, 0.0, 0.0]` (fully-healed stationary
  bot), `cooldowns = [0.0, 0.0]`.

## 2. `TrainingBot.gd` — training scaffold observation (2 floats)

The minimal scaffold agent for `training_scene.tscn` (issue #341):

| Index | Value | Formula | Range |
|---|---|---|---|
| 0 | normalized x | `clampf(position.x / 1152.0, 0, 1)` (`ARENA_W`) | [0, 1] (strict) |
| 1 | normalized y | `clampf(position.y / 752.0, 0, 1)` (`ARENA_H`) | [0, 1] (strict) |

Position is the agent's **local** position in the instanced level, so
every parallel environment reports the same range regardless of its
offset in the training scene. Issue #420 clamps both fractions: the
scaffold's `set_action` walk has no wall check, so the raw position can
drift past the arena rect; the clamp keeps the vector inside the
documented bounds (the same strict policy as `BotController.gd`).
