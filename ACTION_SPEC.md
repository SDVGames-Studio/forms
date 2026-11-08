# ACTION_SPEC.md — Python → Godot action contract

This file locks down the action half of the I/O contract between the
Python training pipeline and the Godot environment. **Update this file
whenever an action space changes** — the integer-to-command mapping below
is what the policy's output indices mean.

## Wire format

In TRAINING mode `NcnnSync` calls each agent's
`set_action(action: Dictionary)` once per decision step (the trainer's
`action_repeat` controls the cadence). For **discrete** heads the decoded
value is one integer index per head, e.g. `{"move": 2, "aim": 0}`. The
head dictionary returned by `get_action_space()` is what the Python
handshake builds one `spaces.Discrete(size)` object per head from
(one independent decision dimension per key); the Stable-Baselines3
wrapper composes those per-head spaces into a single
`spaces.MultiDiscrete` input (issue #422), so the policy's per-step
output is one flat integer per head — `move 6 | aim 3 | attack 8 |
target 4` = 21 slots, a joint space of only 6·3·8·4 = 576 combinations
instead of one fused `Discrete(576)`.

Per-head legality is exposed through `get_action_mask()` (issue #410):
one boolean array per discrete head (`true` = legal), shipped as
`info["action_mask"]` on every training step and applied to the logits
before sampling/argmax on the ncnn inference path.

## 1. `TrainingBot.gd` — training scaffold (`training_scene.tscn`)

### `get_action_space()` — the declared heads (issue #422)

Every size is the actual number of legal options in the game, kept as
small as the game itself allows:

| Head | Size | Type | Grounded in |
|---|---|---|---|
| `move` | 6 | discrete | hold + the 5 movement commands (walk right/left, jump, backflip, skip turn) |
| `aim` | 3 | discrete | hold + aim up/down |
| `attack` | 8 | discrete | hold fire + the 7 weapon slots (`weapon_1`..`weapon_7`, `WeaponInventory.WEAPONS`) |
| `target` | 4 | discrete | no target + the enemy team cap (`GameConfig.MAX_TEAM_MEMBERS` = 3) |

### Integer → game-command mapping

**`move` (6):**

| Index | Command | Actuated today |
|---|---|---|
| 0 | hold position | yes (no-op) |
| 1 | walk right | yes — `position.x += 8.0` (`MOVE_PER_STEP`) |
| 2 | walk left | yes — `position.x -= 8.0` |
| 3 | jump | not yet (scaffold; gameplay follow-up) |
| 4 | backflip | not yet |
| 5 | skip turn | not yet |

**`aim` (3):**

| Index | Command | Actuated today |
|---|---|---|
| 0 | hold aim | not yet (scaffold) |
| 1 | aim up | not yet |
| 2 | aim down | not yet |

**`attack` (8):**

| Index | Command | Actuated today |
|---|---|---|
| 0 | hold fire (no shot) | not yet (scaffold) |
| 1 | select + fire weapon slot 1 (Shotgun) | not yet |
| 2 | select + fire weapon slot 2 (Rocket) | not yet |
| 3 | select + fire weapon slot 3 (Grenade) | not yet |
| 4 | select + fire weapon slot 4 (Spear) | not yet |
| 5 | select + fire weapon slot 5 (Mine) | not yet |
| 6 | select + fire weapon slot 6 (Jackhammer) | not yet |
| 7 | select + fire weapon slot 7 (Railgun) | not yet |

(The slot names follow `WeaponInventory.WEAPONS` order; #382's
"keys 1-4"/size-5 grounding predated the 7-slot inventory — #422 fixed
the size to the real option count.)

**`target` (4):**

| Index | Command | Actuated today |
|---|---|---|
| 0 | keep/no target | not yet (scaffold) |
| 1 | target the 1st visible enemy | not yet |
| 2 | target the 2nd visible enemy | not yet |
| 3 | target the 3rd visible enemy | not yet |

"Visible" = alive, on the opposing side, and within `ATTACK_REACH`, in
stable group (tree) order — exactly the enemies the action mask
legalizes, so the head carries one selectable index per enemy that can
actually be attacked; the fixed width 4 (not "one per enemy on screen")
keeps the tensor shape constant for the trainer.

`set_action()` reads `int(action["move"])` and applies the walk delta for
indices 1/2 only; the other heads are part of the declared contract the
trainer trains against, with gameplay actuation layered on in follow-up
issues (see the TrainingBot.gd header).

### Action mask (issues #410, #422)

- `move` and `aim`: every index always legal.
- `attack`: index 0 always legal; indices 1–7 legal **only while at least
  one alive opposing figure stands within `ATTACK_REACH = 620.0` px**
  (the widest AI weapon band — Npc.gd rocket 620; the scaffold's slots
  don't name weapons yet). Without a bound figure the opposing side is
  `player_team`.
- `target`: index 0 always legal; index k legal **exactly while the k-th
  visible enemy exists** (alive, opposing side, within `ATTACK_REACH`),
  so the policy can only pick a target it could actually attack.

## 2. `BotController.gd` — battlefield controller (`Level*.tscn`)

`get_action_space()` is still a **declared stub** (pushes an error and
returns `{}` — its own issue is pending), but `set_action()` is
implemented and consumes two discrete heads:

| Head | Effective size (per `set_action`) |
|---|---|
| `move` | 3 |
| `action` | 4 |

### Integer → game-command mapping

**`move` (3, `MoveCommand`):**

| Index | Command | `move_dir` |
|---|---|---|
| 0 | `HOLD` — stand still | `Vector2.ZERO` |
| 1 | `RIGHT` — walk right for the turn | `Vector2.RIGHT` |
| 2 | `LEFT` — walk left for the turn | `Vector2.LEFT` |

**`action` (4, `ActionCommand`):**

| Index | Command |
|---|---|
| 0 | `IDLE` — pass |
| 1 | `ATTACK_ENEMY_A` — attack the **nearest** alive enemy (the same nearest-first order the observation vector reports figures in) |
| 2 | `ATTACK_ENEMY_B` — attack the **second nearest** alive enemy |
| 3 | `USE_ABILITY` — the figure's special |

### Execution model and robustness

- `set_action()` does not actuate directly: it translates the indices and
  stores `pending_command = {"move": <int>, "action": <int>,
  "move_dir": <Vector2>}`. The turn-based game loop executes it when the
  bot's turn comes and fetches it via `consume_pending_command()`, which
  hands the order over and immediately resets the bot to idle/hold so a
  stale command can never fire twice.
- Defended input — garbage degrades to the neutral index, never a script
  error: a non-Dictionary `action` → full idle/hold command; a missing
  head, a non-integer-coercible value, an array/dictionary/object, or an
  index outside `[0, size-1]` → that head falls back to index 0
  (`HOLD`/`IDLE`) with a `push_warning`.

## Maintenance

Both spec files live at the project root by design (issue #411): anyone
changing `get_obs()`, `get_action_space()`, `get_action_mask()` or
`set_action()` in `BotController.gd` / `TrainingBot.gd` must update
`OBSERVATION_SPEC.md` / `ACTION_SPEC.md` in the same change.
