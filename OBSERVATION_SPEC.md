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

## 1. `BotController.gd` — battlefield observation (46 floats)

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
| `rel_x` | `clampf(dx / 576.0, -1, 1)` — dx = target.global_position.x − origin.x | [-1, 1] |
| `rel_y` | `clampf(dy / 376.0, -1, 1)` — dy = same for y | [-1, 1] |
| `hp_frac` | `clampf(health / 100, 0, 1)` (`CharacterStats.MAX_HEALTH = 100`) | [0, 1] |
| `shield` | `1.0` if figure `shielded` else `0.0` (issue #221 shield fills the AP slot; Forms has no AP stat) | {0, 1} |
| `vel_x`, `vel_y` | `clampf(v / 320.0, -1, 1)` (`CharacterStats.SPEED = 320.0`) | [-1, 1] |
| `fire_frac` | `clampf(_cooldown_left / 2.0, 0, 1)` (`FIRE_CD_MAX`, Npc.gd easy AI fire pause) | [0, 1] |
| `jump_frac` | `clampf(_jump_left / 1.0, 0, 1)` (`JUMP_CD_MAX`, Npc.gd jump cooldown) | [0, 1] |

Position divisors 576.0 / 376.0 are the Level.tscn arena half-extents
(playable column 1152×752), so a figure on the opposite side of the arena
maps to ≈[-1, 1] before clamping.

### Slot semantics

- **Origin** is the controlled figure's `global_position` (the controller
  node's own position when no figure is bound).
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
| 0 | normalized x | `position.x / 1152.0` (`ARENA_W`) | ≈[0, 1] (not clamped) |
| 1 | normalized y | `position.y / 752.0` (`ARENA_H`) | ≈[0, 1] (not clamped) |

Position is the agent's **local** position in the instanced level, so
every parallel environment reports the same range regardless of its
offset in the training scene.
