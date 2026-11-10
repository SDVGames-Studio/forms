# ACTION_SPEC.md — Python → Godot action contract

This file locks down the action half of the I/O contract between the
Python training pipeline and the Godot environment (issues #411, #424).
It is the **single source of truth** for three consumers:

- the Godot-side `set_action()` / `get_action_mask()` implementations,
- the Python-side action-masking wrapper (`rl_action_mask.py`), and
- any future ncnn inference wrapper (`ActionMask` on the deploy path).

**Update this file whenever an action space changes** — the
integer-to-command mapping and per-index masking rules below are what the
policy's output indices mean. §3 is written so a new contributor can
implement a compatible action-masking wrapper using **only this file**.

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
`info["action_mask"]` on every training step by
`NcnnAIController2D.get_info()` and applied to the logits before
sampling/argmax on the ncnn inference path. A controller that does not
implement `get_action_mask()` ships **no** `action_mask` key — consumers
must treat a missing mask (or a missing head inside it) as
**all indices legal**.

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

The dict's key order (`move`, `aim`, `attack`, `target`) is the wire
order: masks and actions are arrays of exactly these heads, in exactly
this order.

### Integer → command → mask mapping

The **masking condition** column is the per-index rule
`get_action_mask()` (issues #410, #422, #423) enforces; "visible enemy"
is defined once, below the tables.

**`move` (6):**

| Index | Game command (`set_action()`) | Masking condition (legal when) | Actuated today |
|---|---|---|---|
| 0 | hold position (no-op) | always legal | yes |
| 1 | walk right — `position.x += 8.0` (`MOVE_PER_STEP`) | always legal | yes |
| 2 | walk left — `position.x -= 8.0` (`MOVE_PER_STEP`) | always legal | yes |
| 3 | jump | always legal | not yet (scaffold; gameplay follow-up) |
| 4 | backflip | always legal | not yet |
| 5 | skip turn | always legal | not yet |

**`aim` (3):**

| Index | Game command (`set_action()`) | Masking condition (legal when) | Actuated today |
|---|---|---|---|
| 0 | hold aim | always legal | not yet (scaffold) |
| 1 | aim up | always legal | not yet |
| 2 | aim down | always legal | not yet |

**`attack` (8):**

| Index | Game command (`set_action()`) | Masking condition (legal when) | Actuated today |
|---|---|---|---|
| 0 | hold fire (no shot) | always legal | not yet (scaffold) |
| 1 | select + fire weapon slot 1 (Shotgun) | ≥ 1 visible enemy | not yet |
| 2 | select + fire weapon slot 2 (Rocket) | ≥ 1 visible enemy | not yet |
| 3 | select + fire weapon slot 3 (Grenade) | ≥ 1 visible enemy | not yet |
| 4 | select + fire weapon slot 4 (Spear) | ≥ 1 visible enemy | not yet |
| 5 | select + fire weapon slot 5 (Mine) | ≥ 1 visible enemy | not yet |
| 6 | select + fire weapon slot 6 (Jackhammer) | ≥ 1 visible enemy | not yet |
| 7 | select + fire weapon slot 7 (Railgun) | ≥ 1 visible enemy | not yet |

(The slot names follow `WeaponInventory.WEAPONS` order; #382's
"keys 1-4"/size-5 grounding predated the 7-slot inventory — #422 fixed
the size to the real option count.)

**`target` (4):**

| Index | Game command (`set_action()`) | Masking condition (legal when) | Actuated today |
|---|---|---|---|
| 0 | keep/no target | always legal | not yet (scaffold) |
| 1 | target the 1st visible enemy | 1 ≤ visible enemy count | not yet |
| 2 | target the 2nd visible enemy | 2 ≤ visible enemy count | not yet |
| 3 | target the 3rd visible enemy | 3 ≤ visible enemy count | not yet |

**"Visible enemy"** (the predicate every masking condition above uses) =
a figure that is (a) **alive** — `health > 0.0`, duck-typed on both
`Player.gd` and `Npc.gd`; (b) on the **opposing side** — in group
`"player_team"` (the figure-less default view, issue #381); and
(c) **within `ATTACK_REACH = 620.0` px** of the acting figure's
`global_position` (the widest AI weapon band — Npc.gd rocket 620; the
scaffold's slots don't name weapons yet). The visible set is ordered by
`get_nodes_in_group()` (stable tree order), so **visible enemy k** is
well-defined and identical between the `attack` and `target` rules; the
fixed width 4 (not "one per enemy on screen") keeps the tensor shape
constant for the trainer.

`set_action()` reads `int(action["move"])` and applies the walk delta for
indices 1/2 only; the other heads are part of the declared contract the
trainer trains against, with gameplay actuation layered on in follow-up
issues (see the TrainingBot.gd header).

### Mask application (issue #423)

Both consumption paths overwrite the logits of illegal actions with
**`ILLEGAL_LOGIT = -1e9`** before selection — Godot deploy via
`ActionMask.apply_to_logits` (before `ActionDecode`'s argmax/softmax),
Python training wrapper via `rl_action_mask.py` (`mask_logits`/
`apply_action_masks` per head; `sample_masked` draws from the masked
softmax, `argmax_masked` is the deterministic twin). The constant is
pinned across languages by `rl_action_mask_check.py`, which parses
`ActionMask.ILLEGAL_LOGIT` out of the .gd source and asserts it equals
`rl_action_mask.ILLEGAL_LOGIT`; the same check proves the DoD — with no
enemy in reach, 20000 sampled joints never select an attack action. The
mask arrays are **logged alongside the chosen actions** on both sides:
the `inference_step` payload ships `action_mask` next to `action` and
the Policy Debugger overlay renders one compact mask row per discrete
head (`mask 1 0 0 0 0 0 0 0`), while the Python side emits
`rl_action_mask.format_decision` lines (`attack=0 mask=10000000 | …`).
In-trainer PPO distribution masking (MaskablePPO-style, so SB3's own
sampler consumes the masks live) is the training-pipeline follow-up.

## 2. `BotController.gd` — battlefield controller (`Level*.tscn`)

`get_action_space()` is still a **declared stub** (pushes an error and
returns `{}` — its own issue is pending), and the controller does not
implement `get_action_mask()`, so no `action_mask` key is shipped:
**every index of both heads below is always legal** until that issue
lands. `set_action()` is implemented and consumes two discrete heads:

| Head | Effective size (per `set_action`) | Mask |
|---|---|---|
| `move` | 3 | all indices always legal (no mask shipped) |
| `action` | 4 | all indices always legal (no mask shipped) |

**`move` (3, `MoveCommand`):**

| Index | Game command (`set_action()`) | Masking condition (legal when) | `move_dir` |
|---|---|---|---|
| 0 | `HOLD` — stand still | always legal | `Vector2.ZERO` |
| 1 | `RIGHT` — walk right for the turn | always legal | `Vector2.RIGHT` |
| 2 | `LEFT` — walk left for the turn | always legal | `Vector2.LEFT` |

**`action` (4, `ActionCommand`):**

| Index | Game command (`set_action()`) | Masking condition (legal when) |
|---|---|---|
| 0 | `IDLE` — pass | always legal |
| 1 | `ATTACK_ENEMY_A` — attack the **nearest** alive enemy (the same nearest-first order the observation vector reports figures in) | always legal |
| 2 | `ATTACK_ENEMY_B` — attack the **second nearest** alive enemy | always legal |
| 3 | `USE_ABILITY` — the figure's special | always legal |

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

## 3. Implementing a compatible action-masking wrapper (issue #424)

Everything needed to build a wrapper (Python trainer side or ncnn
inference side) from this file alone:

1. **Enumerate the heads** from the §1 head table (and §2 for
   `BotController`): name, wire order, and integer size. The wire order
   is the `get_action_space()` dict order. For `TrainingBot.gd` that is
   `move(6), aim(3), attack(8), target(4)` — 21 integer slots per step.
2. **Mask format**: `info["action_mask"]` (shipped every training step)
   is a `Dictionary` mapping each head name to an `Array` of `size`
   booleans, `true` = legal, positions aligned with the index tables in
   §1. A missing mask, or a missing head inside it, means **all indices
   of that head are legal** (`BotController.gd` today).
3. **Per-index rules** (recomputed independently only if the environment
   does not ship a mask; otherwise consume the shipped mask):
   - `move`, `aim`: all indices legal, unconditionally.
   - `attack`: index 0 always legal; indices 1–7 legal iff the visible
     enemy count (§1 predicate) is ≥ 1.
   - `target`: index 0 always legal; index k (1–3) legal iff
     k ≤ visible enemy count.
   - A joint action is legal iff **every** head index is legal; heads
     are masked independently.
4. **Apply before selection**: overwrite the logits of illegal indices
   with `ILLEGAL_LOGIT = -1e9` (never delete/renormalize them), then
   sample from the masked softmax (`rl_action_mask.sample_masked`) or
   take the deterministic masked argmax (`argmax_masked`). The constant
   is language-pinned: `ActionMask.ILLEGAL_LOGIT` (GDScript) ==
   `rl_action_mask.ILLEGAL_LOGIT` (Python) == `-1e9`.
5. **Stay verifiable**: `rl_action_space_check.py` parses §1's head
   table and fails if it drifts from `TrainingBot.gd` name/order/size;
   `rl_action_mask_check.py` pins the `ILLEGAL_LOGIT` constant across
   languages and proves masked sampling never picks an illegal attack.
   Any change to either side must keep those checks green.

## Maintenance

Both spec files live at the project root by design (issue #411): anyone
changing `get_obs()`, `get_action_space()`, `get_action_mask()` or
`set_action()` in `BotController.gd` / `TrainingBot.gd` must update
`OBSERVATION_SPEC.md` / `ACTION_SPEC.md` in the same change (issue
#424: the per-index tables in §1/§2 and the wrapper recipe in §3 are
part of that obligation — an index, command, or masking-rule change is
a spec change).
