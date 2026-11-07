extends NcnnAIController2D

## Bot controller for the Forms battlefield, created from the editor's
## "NCNN AI Controller" script template (issue #355).
##
## Issue #381 implements the observation half of the contract: get_obs()
## gathers the bot's own vitals, the visible enemy and ally figures, and
## the active cooldown timers — normalized to stable ranges ([-1, 1] for
## relative positions and velocities, [0, 1] for HP/cooldown fractions).
## No raw coordinates or HP values ever leave this script. Reward shaping,
## the action space and action application land in follow-up issues (the
## stubs below stay loud until then).

const Stats := preload("res://scripts/CharacterStats.gd")

## Issue #381: fixed observation layout. OBS_SLOTS enemies and OBS_SLOTS
## allies are reported every step — nearest first, missing figures pad
## with zeros — so the flat vector length never changes
## (4 + 4*5 + 4*5 + 2 = 46 floats), whatever happens on the battlefield.
const OBS_SLOTS := 4
const FEATURES_PER_FIGURE := 5

## Issue #381: normalization scales — the Level.tscn arena half-extents
## (playable column 1152x752, same convention as TrainingBot.gd), so a
## figure on the opposite side of the arena maps to ~[-1, 1]. Velocities
## divide by the shared run speed (CharacterStats.SPEED).
const NORM_HALF_W := 576.0
const NORM_HALF_H := 376.0
const VEL_NORM := Stats.SPEED
## Issue #381: cooldown ceilings for the [0, 1] fractions — the slowest AI
## fire pause (Npc.gd FIRE_PAUSE, easy difficulty, 2.0 s) and the jump
## cooldown (Npc.gd JUMP_COOLDOWN, 1.0 s).
const FIRE_CD_MAX := 2.0
const JUMP_CD_MAX := 1.0

## Issue #381: the figure this controller plays (Player.gd or Npc.gd).
## Optional — when unset (or the linked figure is down) the controller
## speaks for the nearest alive figure in the current level.
@export var figure_path: NodePath

func get_obs() -> Dictionary:
	# Issue #381: the NcnnAIController2D contract wants ONE flat float
	# array under "obs" (the trainer reads only that key); the named
	# normalized groups live in _collect_obs_parts() for humans and tests.
	return {"obs": _flatten_parts(_collect_obs_parts())}

## Issue #381: named observation groups, each a float Array with every
## value already normalized:
##   "own"       [hp_frac, shield, vel_x, vel_y]                 (4)
##   "enemies"   OBS_SLOTS x [rel_x, rel_y, hp, vel_x, vel_y]   (20)
##   "allies"    OBS_SLOTS x [rel_x, rel_y, hp, vel_x, vel_y]   (20)
##   "cooldowns" [fire_frac, jump_frac]                          (2)
## Forms has no AP stat, so the shield flag (issue #221: it blocks one
## hit) fills the protection slot next to HP. Every alive figure in the
## level counts as visible — Forms has no fog or line-of-sight occlusion.
func _collect_obs_parts() -> Dictionary:
	var figure := _resolve_figure()
	var origin: Vector2 = figure.global_position if figure != null else global_position
	return {
		"own": _own_features(figure),
		"enemies": _team_features(_enemy_group(figure), origin, figure),
		"allies": _team_features(_ally_group(figure), origin, figure),
		"cooldowns": _cooldown_features(figure),
	}

## Issue #381: the linked figure, or the nearest alive figure in the tree.
## Duck-typed on `health` — both Player.gd and Npc.gd report it, so no
## type coupling to either script.
func _resolve_figure() -> Node2D:
	if not figure_path.is_empty():
		var linked := get_node_or_null(figure_path)
		if linked != null and linked is Node2D and _alive(linked):
			return linked
	if not is_inside_tree():
		return null
	var best: Node2D = null
	var best_d := INF
	for side in ["player_team", "enemy_team"]:
		for fig in get_tree().get_nodes_in_group(side):
			if not (fig is Node2D and _alive(fig)):
				continue
			var d: float = global_position.distance_squared_to(fig.global_position)
			if d < best_d:
				best_d = d
				best = fig
	return best

## Issue #381: the controller fights for the side its figure is NOT in.
## Player figures and "player"-side NPCs share "player_team"; everything
## else fights under "enemy_team" (Npc.gd issue #121). Without a figure
## the default enemy-side view matches the Npc default team.
func _enemy_group(figure: Node2D) -> String:
	if figure != null and figure.is_in_group("player_team"):
		return "enemy_team"
	return "player_team"

func _ally_group(figure: Node2D) -> String:
	return "player_team" if _enemy_group(figure) == "enemy_team" else "enemy_team"

## Issue #381: nearest-first figure block with zero padding to a constant
## length; `exclude` drops the own figure from its allies (it is already
## reported by "own", and its position IS the observation origin).
func _team_features(group_name: String, origin: Vector2, exclude: Node2D) -> Array:
	var rows: Array = []
	var figs: Array = []
	if is_inside_tree():
		figs = get_tree().get_nodes_in_group(group_name).filter(
			func(f): return f is Node2D and f != exclude and _alive(f))
		figs.sort_custom(func(a, b):
			var da := origin.distance_squared_to(a.global_position)
			var db := origin.distance_squared_to(b.global_position)
			if da == db:
				return String(a.name) < String(b.name)
			return da < db)
	for i in OBS_SLOTS:
		if i < figs.size():
			rows.append_array(_figure_features(figs[i], origin))
		else:
			for _j in FEATURES_PER_FIGURE:
				rows.append(0.0)
	return rows

## Issue #381: one figure = [rel_x, rel_y, hp_frac, vel_x, vel_y] —
## relative offset normalized by the arena half-extents, HP as a [0, 1]
## fraction, velocity by the shared run speed; all clamped to [-1, 1].
func _figure_features(fig: Node2D, origin: Vector2) -> Array:
	var rel := _norm_rel(fig.global_position - origin)
	var vel := _norm_vel(fig.get("velocity"))
	return [rel.x, rel.y, _hp_frac(fig), vel.x, vel.y]

## Issue #381: own vitals — HP fraction (never the raw value), the shield
## flag in the AP slot, and the current velocity in [-1, 1]. Without a
## figure the slots report a fully-healed stationary bot so the vector
## stays well-formed.
func _own_features(figure: Node2D) -> Array:
	if figure == null:
		return [1.0, 0.0, 0.0, 0.0]
	var vel := _norm_vel(figure.get("velocity"))
	var shield := 1.0 if bool(figure.get("shielded")) else 0.0
	return [_hp_frac(figure), shield, vel.x, vel.y]

## Issue #381: active cooldown timers as [0, 1] fractions of their
## ceilings — fire pause (_cooldown_left / FIRE_CD_MAX) and jump cooldown
## (_jump_left / JUMP_CD_MAX). Figures without a cooldown stat (Player.gd
## has none) read as 0.
func _cooldown_features(figure: Node2D) -> Array:
	if figure == null:
		return [0.0, 0.0]
	return [
		_cd_frac(figure.get("_cooldown_left"), FIRE_CD_MAX),
		_cd_frac(figure.get("_jump_left"), JUMP_CD_MAX),
	]

## Issue #381: fixed key order -> a deterministic flat layout (46 floats).
func _flatten_parts(parts: Dictionary) -> Array:
	var flat: Array = []
	for key in ["own", "enemies", "allies", "cooldowns"]:
		flat.append_array(parts[key])
	return flat

func _norm_rel(offset: Vector2) -> Vector2:
	# Issue #381: scaled by the arena half-extents, clamped to [-1, 1] so
	# larger levels stay inside the stable range.
	return Vector2(
		clampf(offset.x / NORM_HALF_W, -1.0, 1.0),
		clampf(offset.y / NORM_HALF_H, -1.0, 1.0))

func _norm_vel(value) -> Vector2:
	if value == null:
		return Vector2.ZERO
	var v: Vector2 = value
	return Vector2(
		clampf(v.x / VEL_NORM, -1.0, 1.0),
		clampf(v.y / VEL_NORM, -1.0, 1.0))

func _hp_frac(fig: Node2D) -> float:
	var hp = fig.get("health")
	if hp == null:
		return 0.0
	return clampf(float(hp) / float(Stats.MAX_HEALTH), 0.0, 1.0)

func _cd_frac(value, ceiling: float) -> float:
	if value == null or ceiling <= 0.0:
		return 0.0
	return clampf(float(value) / ceiling, 0.0, 1.0)

func _alive(fig) -> bool:
	var hp = fig.get("health")
	return hp != null and float(hp) > 0.0

func get_reward() -> float:
	# Return the reward accumulated since the last step — e.g. a RewardBuilder total,
	# or a hand-computed shaping term (distance delta, goal bonus, time penalty).
	push_error("get_reward() not implemented")
	return 0.0

func get_action_space() -> Dictionary:
	# Describe each action head. Examples:
	#     "move": {"size": 4, "action_type": "discrete"}     # one of 4 choices
	#     "steer": {"size": 2, "action_type": "continuous"}  # 2 floats in [-1, 1]
	push_error("get_action_space() not implemented")
	return {}

func set_action(_action) -> void:
	# Apply the chosen action to your agent, e.g.:
	#     var idx := int(action["move"])
	#     velocity = DIRECTIONS[idx] * speed
	push_error("set_action() not implemented")

#func get_obs_space() -> Dictionary:
#	# Override only for complex obs (images, multiple keys). The base class derives
#	# {"obs": {"size": [len], "space": "box"}} from get_obs() automatically.
#	return super.get_obs_space()
