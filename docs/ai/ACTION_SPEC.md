# ACTION_SPEC.md — Python → Godot action contract

This file locks down the action half of the I/O contract between the
Python training pipeline and the Godot environment (issues #411, #424).
It is the **single source of truth** for three consumers:

- the Godot-side `set_action()` / `get_action_mask()` implementations,
- the Python-side action-masking wrapper (`rl_action_mask.py`), and
- the ncnn inference deploy path (`InferenceBot` + `ActionMask`, #507).

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
output is one flat integer per head — `move 6 | aim 3 | attack 12 |
target 4` = 25 slots, a joint space of only 6·3·12·4 = 864 combinations
instead of one fused `Discrete(864)`.

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
| `attack` | 12 | discrete | hold fire + the 11 weapon slots (`weapon_1`..`weapon_11`, `WeaponInventory.WEAPONS`; the baseball bat joined as slot 9, #527; the circular saw as slot 10, #570; the entrenching shovel as slot 11, #656) |
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

**`attack` (12):**

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
| 8 | select + fire weapon slot 8 (Pistol) | ≥ 1 visible enemy | not yet |
| 9 | select + fire weapon slot 9 (Baseball Bat) | ≥ 1 visible enemy | not yet |
| 10 | select + fire weapon slot 10 (Circular Saw) | ≥ 1 visible enemy | not yet |
| 11 | select + fire weapon slot 11 (Entrenching Shovel) | ≥ 1 visible enemy | not yet |

(The slot names follow `WeaponInventory.WEAPONS` order; #382's
"keys 1-4"/size-5 grounding predated the smaller inventory — #422 fixed
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
head (`mask 1 0 0 0 0 0 0 0 0 0`), while the Python side emits
`rl_action_mask.format_decision` lines (`attack=0 mask=100000000000 | …`).
In-trainer PPO distribution masking (MaskablePPO-style, so SB3's own
sampler consumes the masks live) is the training-pipeline follow-up.

### Deploy-path fallback (issue #507)

The deployed ncnn bot (`InferenceBot.gd`, `inference_scene.tscn`, issue
#506) applies the SAME per-index rules on its inference path — recomputed
from live battlefield state at **every decision step**, per head, exactly
as §1 defines them — before the per-head argmax/softmax accepts the
network's choice. The deployed net re-orders the same four heads to the
trained policy's SB3 `MultiDiscrete([3,8,6,4])` output layout
(`aim, attack, move, target`), so the mask (keyed by head name) is applied
to the flat 21-value output in that order. (#526/#527 note: the deployed
net was trained on the pre-pistol 7-weapon space, so its `attack` head is
FROZEN at 8 while the training scaffold grew to 12 — `InferenceBot.gd`
keeps the deployed sizes until the policy is retrained; the deployed bot
never selects the pistol, the baseball bat, the circular saw or the
entrenching shovel.)

**Fallback behavior** (what #507 orders documented): if the network's
chosen action for a head is illegal, it is **overridden by the
highest-scoring legal action of that head** — `ActionMask.apply_to_logits`
inspects the raw output scores, overwrites the illegal slots with
`ILLEGAL_LOGIT`, and the subsequent argmax lands on the best legal slot.
No heuristic "idle" default is ever needed: index 0 of every head is
always legal (hold position / hold aim / hold fire / keep target) and
`ActionMask.validate` enforces that at least one index per head stays
legal, so a deterministic legal fallback always exists. An **invalid**
mask (wrong head, wrong size, or an all-illegal head) fails loud instead:
the decision step is skipped — no action is applied that step — because a
silently mis-applied mask is worse than no action.

**Logging**: the `inference_step` debug payload (consumed by the Policy
Debugger overlay) ships the mask application alongside the **raw network
output**: `raw_output` (the net's unmasked scores), `logits` (the
effective post-mask scores that drove the choice, illegal slots at
`ILLEGAL_LOGIT`), `action_mask`, and the decoded `action` — so an
override like "net preferred attack slot 4.3 → held fire" is auditable
per decision step.

## 2. `BotController.gd` — battlefield controller (`Level*.tscn`)

Issue #607 widened the controller to the **FULL repertoire**: five
discrete heads — every movement command (jump and backflip included),
aiming, all 10 weapon slots and all 4 tools. `get_action_space()` and
`get_action_mask()` are both implemented, so the mask ships in
`info["action_mask"]` on every training step.

### `get_action_space()` — the declared heads (issue #607)

| Head | Size | Type | Grounded in |
|---|---|---|---|
| `move` | 6 | discrete | hold + the 5 movement commands (walk right/left, jump, backflip, skip turn) — the §1 scaffold set (`TrainingBot.gd`, #422) |
| `aim` | 3 | discrete | hold + aim up/down |
| `attack` | 11 | discrete | hold fire + the 10 weapon slots (`WeaponInventory.WEAPONS`) |
| `target` | 4 | discrete | no target + the enemy team cap (`GameConfig.MAX_TEAM_MEMBERS` = 3) |
| `tool` | 5 | discrete | no tool + the 4 tools (`ToolInventory.TOOLS`: Switch, Teleport, Shield, Rock) |

The dict's key order (`move`, `aim`, `attack`, `target`, `tool`) is the
wire order. 29 integer slots per step; the joint space is
6·3·11·4·5 = 3960 combinations.

### Integer → command → mask mapping

**`move` (6, `MoveCommand`):** 0 `HOLD`, 1 walk right, 2 walk left,
3 `JUMP`, 4 `BACKFLIP`, 5 `SKIP_TURN` — always legal. `move_dir` is
`Vector2.RIGHT`/`LEFT` for 1/2 and `Vector2.ZERO` otherwise (jump,
backflip and skip-turn are discrete orders the game loop reads off the
`move` index, not walk directions).

**`aim` (3, `AimCommand`):** 0 hold aim, 1 aim up, 2 aim down — always
legal.

**`attack` (11, `AttackCommand`):** 0 `HOLD_FIRE`; index i+1 selects +
fires `WeaponInventory.WEAPONS[i]` (1 Shotgun … 10 Circular Saw) —
index 0 always legal, indices 1–10 legal iff ≥ 1 visible enemy.

**`target` (4, `TargetCommand`):** 0 `NONE`; index k targets the k-th
visible enemy (`ENEMY_1`…`ENEMY_3`) — legal iff k ≤ visible enemy
count.

**`tool` (5, `ToolCommand`):** 0 `NONE`; index i+1 spends
`ToolInventory.TOOLS[i]` (1 `USE_SWITCH`, 2 `USE_TELEPORT`,
3 `USE_SHIELD`, 4 `USE_ROCK`) — always legal in the mask: the
once-per-turn / per-team quota is spent at EXECUTION by
`ToolInventory`, not by the mask.

**"Visible enemy"** = a figure that is (a) **alive** (duck-typed on
`health`), (b) on the **opposing side** of the controller's figure, and
(c) **within `ATTACK_REACH = 620.0` px** — the controller's own
`_enemies_in_reach` predicate — ordered **nearest-first** (distance
ties broken by node name), the same order the observation vector
reports enemies in (issue #381), so `target` k and the k-th observation
enemy slot always name the same figure. Without a bound figure the
opposing side defaults to `"player_team"` (the figure-less default
view, issue #381).

### Execution model and robustness

- `set_action()` does not actuate directly: it translates the five
  heads and stores `pending_command = {"move": <int>,
  "move_dir": <Vector2>, "aim": <int>, "attack": <int>,
  "target": <int>, "tool": <int>}`. The turn-based game loop executes
  it when the bot's turn comes and fetches it via
  `consume_pending_command()`, which hands the order over and
  immediately resets the bot to the all-neutral command so a stale
  command can never fire twice. Actuating jump/backflip/skip/aim,
  threading weapon fire through the selected target and spending tool
  quotas are the game-loop follow-up layered on this contract.
- Defended input — garbage degrades per head to the neutral index,
  never a script error: a non-Dictionary `action` → full idle command; a
  missing head, a non-integer-coercible value, an
  array/dictionary/object, or an index outside `[0, size-1]` → that
  head falls back to index 0 (hold) with a `push_warning`. Unknown
  heads (a stale #407-era trainer still emitting `"action"`) are
  ignored — their slot stays neutral.

## 3. Implementing a compatible action-masking wrapper (issue #424)

Everything needed to build a wrapper (Python trainer side or ncnn
inference side) from this file alone:

1. **Enumerate the heads** from the §1 head table (and §2 for
   `BotController`): name, wire order, and integer size. The wire order
   is the `get_action_space()` dict order. For `TrainingBot.gd` that is
   `move(6), aim(3), attack(10), target(4)` — 23 integer slots per step
   (the deployed ncnn net still emits the frozen 21-value pre-#526
   layout; see "Deploy-path fallback").
2. **Mask format**: `info["action_mask"]` (shipped every training step)
   is a `Dictionary` mapping each head name to an `Array` of `size`
   booleans, `true` = legal, positions aligned with the index tables in
   §1. A missing mask, or a missing head inside it, means **all indices
   of that head are legal** (any controller that does not implement
   `get_action_mask()`).
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
