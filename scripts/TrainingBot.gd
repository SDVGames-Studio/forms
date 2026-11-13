extends NcnnAIController2D

## Training scaffold agent for training_scene.tscn (issue #341).
##
## Implements the minimal NcnnAIController2D contract (observation, reward,
## action space, action application) so the training scene can step against
## the Python trainer out of the box. Game-specific signals (sensors, real
## reward shaping, gameplay actions) are layered on in follow-up issues.

const MOVE_PER_STEP := 8.0
## Level.tscn playfield extents (ground rect 1152x448 centered at y=752).
const ARENA_W := 1152.0
const ARENA_H := 752.0

func get_obs() -> Dictionary:
	# Normalized own position in the instanced level (local space, so every
	# environment reports the same range regardless of its offset in the
	# training scene). Issue #420: STRICT bounds — the scaffold walk has no
	# wall check (set_action keeps applying MOVE_PER_STEP), so the raw
	# position can drift past the arena rect; both fractions are clamped
	# to keep every value inside the documented [0, 1] (OBSERVATION_SPEC.md),
	# the same policy BotController.gd already enforces.
	return {"obs": [
		clampf(position.x / ARENA_W, 0.0, 1.0),
		clampf(position.y / ARENA_H, 0.0, 1.0),
	]}

func get_reward() -> float:
	# Flat per-step cost: a non-degenerate signal until real reward shaping
	# lands. Episode-terminal rewards are added later.
	return -0.001

## Multi-discrete action space for the turn-based team deathmatch (issues
## #382, #422). A dictionary of discrete action heads in the godot_rl_agents
## contract: each key is an independent decision dimension and the Python
## handshake builds one spaces.Discrete(size) object per head, which the
## SB3 wrapper composes into a single spaces.MultiDiscrete input — the
## policy learns an independent sub-policy per dimension instead of one
## fused Discrete over all 6*3*10*4 = 720 joints. Issue #422 re-grounds
## every size in the ACTUAL number of legal options in the game (as small
## as the game itself allows):
##   "move":   0 hold | 1 walk right | 2 walk left | 3 jump | 4 backflip | 5 skip turn
##   "aim":    0 hold | 1 aim up | 2 aim down
##   "attack": 0 hold fire | 1-9 select+fire weapon slot 1-9 — the InputMap
##             has exactly weapon_1..weapon_9 and WeaponInventory.WEAPONS
##             has 9 entries (the baseball bat joined as slot 9, #527)
##   "target": 0 keep/no target | 1-3 the k-th alive opposing figure within
##             ATTACK_REACH (GameConfig.MAX_TEAM_MEMBERS == 3 caps the enemy
##             team, so 1+3 = 4 is the whole legal option set)
## Sizes are literals, not runtime lookups: get_action_mask() re-reads this
## dict every decision step. tests/test_issue422.gd and
## rl_action_space_check.py pin the literals to WeaponInventory.WEAPONS and
## GameConfig.MAX_TEAM_MEMBERS so a game change can't drift past the space.
## Issue #410 adds the action-mask half: get_action_mask() marks the firing
## actions illegal while no alive opposing figure stands within ATTACK_REACH.
func get_action_space() -> Dictionary:
	return {
		"move": {"size": 6, "action_type": "discrete"},
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 10, "action_type": "discrete"},
		"target": {"size": 4, "action_type": "discrete"},
	}

## Issue #410: the weapon slots don't name weapons yet, so the scaffold's
## attack reach is the game's widest AI weapon band — Npc.gd's per-weapon
## ranges (issues #66/#430): spear 90, shotgun 450, rocket 620. Any firing
## action is legal while at least one alive opposing figure stands inside it.
const ATTACK_REACH := 620.0

## Issue #410: per-decision-step legality mask — one boolean array per
## discrete head (true = legal), the same shape as get_action_space().
## "move" and "aim" have no legality constraints in the scaffold (every
## index is always legal). On "attack" (#410), index 0 (hold fire) is always
## legal while indices 1-8 (select+fire a weapon slot) are legal only when
## at least one alive opposing figure is within ATTACK_REACH. On "target"
## (#422), index k is legal exactly while the k-th VISIBLE enemy (alive,
## opposing side, within ATTACK_REACH, stable group order) exists — one
## legal index per visible enemy, the smallest target set the game offers.
## The mask is consumed three ways: NcnnAIController2D.get_info() ships it
## in info["action_mask"] on every training step (for the Python wrapper to
## mask logits before sampling), and the ncnn inference path applies it to
## the logits before argmax/softmax (ActionMask). Without a bound figure
## the opposing side is "player_team" — the same figure-less default view
## BotController uses (issue #381).
func get_action_mask() -> Dictionary:
	var visible := _visible_enemies()
	var mask := {}
	for key in get_action_space().keys():
		var size: int = get_action_space()[key]["size"]
		var legal: Array = []
		legal.resize(size)
		legal.fill(true)
		if key == "attack":
			for i in range(1, size):
				legal[i] = visible.size() > 0
		elif key == "target":
			for k in range(1, size):
				legal[k] = k <= visible.size()
		mask[key] = legal
	return mask

## Issue #410/#422: alive opposing figures within ATTACK_REACH, in stable
## get_nodes_in_group() (tree) order — the k-th entry is the figure
## "target" index k selects. Alive is duck-typed on `health` (both
## Player.gd and Npc.gd report it), mirroring BotController.
func _visible_enemies() -> Array:
	if not is_inside_tree():
		return []
	var visible := []
	for fig in get_tree().get_nodes_in_group("player_team"):
		if fig is Node2D and fig.get("health") != null \
				and float(fig.get("health")) > 0.0 \
				and global_position.distance_to(fig.global_position) <= ATTACK_REACH:
				visible.append(fig)
	return visible

func set_action(action) -> void:
	# Applied once per decision step; the trainer's action_repeat controls how
	# often that happens. The scaffold actuates the walk deltas for now —
	# jump/backflip/skip, aim and weapon actuation are the gameplay follow-ups
	# layered on top of this contract (see the file header).
	var move_idx := int(action["move"])
	if move_idx == 1:
		position.x += MOVE_PER_STEP
	elif move_idx == 2:
		position.x -= MOVE_PER_STEP
