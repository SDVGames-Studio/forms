extends NcnnAIController2D

## Bot controller for the Forms battlefield, created from the editor's
## "NCNN AI Controller" script template (issue #355).
##
## Issue #381 implements the observation half of the contract: get_obs()
## gathers the bot's own vitals, the visible enemy and ally figures, and
## the active cooldown timers — normalized to stable ranges ([-1, 1] for
## relative positions and velocities, [0, 1] for HP/cooldown fractions).
## No raw coordinates or HP values ever leave this script. Issue #419
## re-expresses every positional and velocity slot in the agent's LOCAL
## frame — the bound figure's facing direction becomes +X (to_local() for
## positions, the inverse of the figure's rotation for velocities) — so
## the observation is translation- and rotation-invariant across the map.
## Issue #407
## implements the action-application half: set_action() translates discrete
## policy head indices into concrete game commands and stores them in
## pending_command for the turn-based game loop. Issue #408 implements
## the reward half: get_reward() returns the accumulated reward property,
## credited by game logic when this bot's figure lands a hit. Issue #409
## implements the episode lifecycle half: reset() clears the controller's
## own state (a pending order) and restores its figure to a clean start —
## spawn position, full HP, default protection, no cooldowns, revived.
## The action-space declaration remains a loud stub until its own issue.

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

## Issue #409: spawn snapshot — whose clean pose was captured, and where.
## The FIRST resolution of a figure happens at its clean starting state
## (the framework observes before any action is applied), so that pose
## becomes the position reset() restores to. A NEW figure instance (the
## old one freed by its death animation, re-instantiated by the level)
## gets a fresh snapshot at its own clean state.
var _spawn_figure: Node2D = null
var _spawn_position := Vector2.ZERO

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
## Issue #419: every offset and velocity is expressed in the agent's
## LOCAL frame (local +X = the figure's facing direction); see
## _local_position() / _local_velocity(). Forms has no AP stat, so the shield flag (issue #221: it blocks one
## hit) fills the protection slot next to HP. Every alive figure in the
## level counts as visible — Forms has no fog or line-of-sight occlusion.
func _collect_obs_parts() -> Dictionary:
	var figure := _resolve_figure()
	var origin: Vector2 = figure.global_position if figure != null else global_position
	# Issue #419: the observation frame — the bound figure's local space
	# (the controller node itself when none is bound). Positions and
	# velocities below are expressed against it, so the observation stays
	# the same wherever (and at whatever angle) the battle happens.
	var frame: Node2D = figure if figure != null else self
	return {
		"own": _own_features(figure, frame),
		"enemies": _team_features(_enemy_group(figure), origin, figure, frame),
		"allies": _team_features(_ally_group(figure), origin, figure, frame),
		"cooldowns": _cooldown_features(figure),
	}

## Issue #409: capture `figure`'s current pose as the spawn snapshot —
## once per figure instance; later calls keep the original snapshot.
func _capture_spawn(figure: Node2D) -> void:
	if figure == _spawn_figure and is_instance_valid(_spawn_figure):
		return
	_spawn_figure = figure
	_spawn_position = figure.global_position

## Issue #409: the linked-or-nearest ALIVE resolution, plus the spawn
## snapshot capture on first sight of a figure.
func _resolve_figure() -> Node2D:
	var figure := _resolve_alive_figure()
	if figure != null:
		_capture_spawn(figure)
	return figure

## Issue #381: the linked figure, or the nearest alive figure in the tree.
## Duck-typed on `health` — both Player.gd and Npc.gd report it, so no
## type coupling to either script.
func _resolve_alive_figure() -> Node2D:
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
## `origin` stays a WORLD-space point — it only feeds the nearest-first
## sort (distance is frame-independent); the reported features go through
## the agent-local `frame` (issue #419).
func _team_features(group_name: String, origin: Vector2, exclude: Node2D, frame: Node2D) -> Array:
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
			rows.append_array(_figure_features(figs[i], frame))
		else:
			for _j in FEATURES_PER_FIGURE:
				rows.append(0.0)
	return rows

## Issue #381/#419: one figure = [rel_x, rel_y, hp_frac, vel_x, vel_y] —
## offset and velocity in the agent's LOCAL frame (issue #419:
## _local_position() / _local_velocity() below), the offset normalized by
## the arena half-extents, HP as a [0, 1] fraction, velocity by the shared
## run speed; all clamped to [-1, 1]. An enemy straight ahead reads
## rel_x > 0 at any agent rotation.
func _figure_features(fig: Node2D, frame: Node2D) -> Array:
	var rel := _norm_rel(_local_position(fig, frame))
	var vel := _norm_vel(_local_velocity(fig.get("velocity"), frame))
	return [rel.x, rel.y, _hp_frac(fig), vel.x, vel.y]

## Issue #419: world → agent-local transforms. The frame's local +X is its
## facing direction; positions go through Godot's to_local() (the inverse
## of its global transform), velocities through the inverse of its
## rotation basis — for a 2D node that is the velocity rotated by
## -global_rotation, the 2D equivalent of
## global_transform.basis.orthonormalized().inverse() * linear_velocity.
## With rotation 0 the local frame equals the world frame, so scenes that
## never rotate their figures observe no change.
func _local_position(fig: Node2D, frame: Node2D) -> Vector2:
	return frame.to_local(fig.global_position)

func _local_velocity(value, frame: Node2D) -> Vector2:
	if value == null:
		return Vector2.ZERO
	var v: Vector2 = value
	return v.rotated(-frame.global_rotation)

## Issue #381: own vitals — HP fraction (never the raw value), the shield
## flag in the AP slot, and the current velocity in [-1, 1], expressed in
## the agent's own (local) frame (issue #419) — moving forward reads
## vel_x > 0 at any rotation. Without a figure the slots report a
## fully-healed stationary bot so the vector stays well-formed.
func _own_features(figure: Node2D, frame: Node2D) -> Array:
	if figure == null:
		return [1.0, 0.0, 0.0, 0.0]
	var vel := _norm_vel(_local_velocity(figure.get("velocity"), frame))
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
	# Issue #408: the accumulated reward signal — simply the inherited
	# `reward` property, never reset here. Game logic increments the
	# property at known events (Player/Npc.take_damage credits
	# HIT_REWARD when this bot's figure lands a hit); the training
	# framework clears it after each collection (NcnnSync /
	# zero_reward()), so this reports the delta since the last step.
	return reward

## Issue #408: reward per landed hit — the issue's sample magnitude.
const HIT_REWARD := 1.0

## Issue #408: does this controller play `fig`? Game logic (take_damage)
## uses it to find whose accumulator a landed hit credits. Controllers
## duck-type on this method, so foreign AGENT-group agents are skipped.
func owns_figure(fig: Node2D) -> bool:
	return _resolve_figure() == fig

## Issue #408: a landed hit is a known reward event — every controller
## in the AGENT group whose figure is the attacker earns +HIT_REWARD.
## Called by Player/Npc.take_damage after damage is applied, so every
## weapon path that threads its shooter (Projectile, ProjectileBody,
## railgun) feeds the same accumulator.
static func credit_hit_reward(attacker: Node2D) -> void:
	if attacker == null or not attacker.is_inside_tree():
		return
	for ctrl in attacker.get_tree().get_nodes_in_group("AGENT"):
		if ctrl != null and ctrl.has_method("owns_figure") \
				and ctrl.owns_figure(attacker):
			ctrl.reward += HIT_REWARD

## Issue #409: episode reset — restore the bot and its battlefield state
## to a clean start. The framework's share (step counter, needs_reset,
## recurrent memory — and the accumulated reward, cleared by the Sync's
## zero_reward()) is already handled by the base class; this override
## clears the controller's OWN custom state (a pending order must never
## fire in the new episode) and restores the controlled figure.
func reset() -> void:
	super.reset()
	pending_command = _idle_command()
	_restore_figure()

## Issue #409: the horizon auto-reset must restore the episode too — the
## base reset_if_done() only clears core bookkeeping, which would leave a
## stale command and a battered figure behind at a reset_after boundary.
func reset_if_done() -> void:
	if get_done():
		reset()

## Issue #409: which figure reset() restores — the LINKED figure even
## when down (the game-over state _resolve_figure()'s alive filter
## skips), else the spawn snapshot's owner if it still exists, else the
## alive fallback. A figure FREED by its death animation (Player/Npc._die
## queue_free()s after the shrink-out) is gone for good: a fresh episode
## re-instances it with the scene, and until then the controller observes
## the well-formed "no figure" default (issue #381).
func _resolve_reset_figure() -> Node2D:
	if not figure_path.is_empty():
		var linked := get_node_or_null(figure_path)
		if linked != null and linked is Node2D:
			return linked
	if is_instance_valid(_spawn_figure):
		return _spawn_figure
	return _resolve_figure()

## Issue #409: the state restore itself — every access duck-typed so any
## figure flavour (Player, Npc, test stand-ins) resets as far as it can:
## spawn position, at rest, full HP, default protection (Forms has no AP
## stat — the shield fills that slot, issue #381), zeroed cooldowns and
## aim, a game-over figure revived, the health bar redrawn.
func _restore_figure() -> void:
	var figure := _resolve_reset_figure()
	if figure == null:
		return
	_capture_spawn(figure)
	figure.global_position = _spawn_position
	if figure.get("velocity") != null:
		figure.set("velocity", Vector2.ZERO)
	figure.set("health", Stats.MAX_HEALTH)
	if figure.has_method("set_shielded"):
		figure.set_shielded(false)
	for cooldown in ["_cooldown_left", "_jump_left"]:
		if cooldown in figure:
			figure.set(cooldown, 0.0)
	if "view_angle" in figure:
		figure.set("view_angle", 0.0)
	if "_dead" in figure and bool(figure.get("_dead")):
		_revive_figure(figure)
	if figure.has_signal("health_changed"):
		figure.emit_signal("health_changed", Stats.MAX_HEALTH, Stats.MAX_HEALTH)
	if figure.has_method("_update_bar"):
		figure.call("_update_bar")

## Issue #409: a game-over figure is revived — the death flag comes down,
## physics resumes, and the shrink-out death tween is cancelled (killed,
## body scale restored) so the bot re-enters the next episode whole.
func _revive_figure(figure: Node2D) -> void:
	figure.set("_dead", false)
	figure.set_physics_process(true)
	var death_tween = figure.get("death_tween")
	if death_tween is Tween:
		death_tween.kill()
		figure.set("death_tween", null)
	figure.scale = Vector2.ONE

func get_action_space() -> Dictionary:
	# Describe each action head. Examples:
	#     "move": {"size": 4, "action_type": "discrete"}     # one of 4 choices
	#     "steer": {"size": 2, "action_type": "continuous"}  # 2 floats in [-1, 1]
	push_error("get_action_space() not implemented")
	return {}

## Issue #407: concrete game commands the raw policy indices translate
## into. "move" orders the turn's walk direction (HOLD = stand still);
## "action" orders the combat move — ATTACK_ENEMY_A targets the nearest
## alive enemy, ATTACK_ENEMY_B the second nearest (the same nearest-first
## order the observation vector reports them in, issue #381), USE_ABILITY
## the figure's special, IDLE passes. Resolving which node "enemy A"/"B"
## name at execution time stays with the game loop.
enum MoveCommand { HOLD, RIGHT, LEFT }
enum ActionCommand { IDLE, ATTACK_ENEMY_A, ATTACK_ENEMY_B, USE_ABILITY }

## Walk direction each MoveCommand maps to (unit vector; distance and
## timing stay with the game loop's turn logic).
const MOVE_DIRS := {
	MoveCommand.HOLD: Vector2.ZERO,
	MoveCommand.RIGHT: Vector2.RIGHT,
	MoveCommand.LEFT: Vector2.LEFT,
}

## Issue #407: the translated command the game loop executes on the bot's
## next turn — set_action() rewrites it on every policy decision step.
## Always carries "move" (MoveCommand), "action" (ActionCommand) and
## "move_dir" (Vector2); malformed policy output degrades to idle/hold.
var pending_command: Dictionary = {
	"move": MoveCommand.HOLD,
	"action": ActionCommand.IDLE,
	"move_dir": Vector2.ZERO,
}

func set_action(action) -> void:
	# Issue #407: NcnnSync (TRAINING mode) calls this once per decision step
	# with the decoded policy output — for a discrete action space a
	# dictionary of action head -> integer index, e.g. {"move": 2,
	# "action": 0}. The indices are translated into the concrete commands
	# above and STORED on the bot: actuation stays with the turn-based game
	# loop, which executes pending_command when the bot's turn comes. The
	# input is defended at the type/range level — garbage degrades to the
	# idle command with a warning, never a script error.
	if typeof(action) != TYPE_DICTIONARY:
		push_warning(
			"BotController.set_action: expected a Dictionary of action heads, "
			+ "got %s — idling" % type_string(typeof(action)))
		pending_command = _idle_command()
		return
	var move := _head_index(action, "move", MoveCommand.size())
	var order := _head_index(action, "action", ActionCommand.size())
	pending_command = {
		"move": move,
		"action": order,
		"move_dir": MOVE_DIRS[move],
	}

## Issue #407: the game loop calls this when the bot's turn starts — it
## hands over the stored order and resets the bot to idle/hold so a stale
## command can never fire twice.
func consume_pending_command() -> Dictionary:
	var command := pending_command
	pending_command = _idle_command()
	return command

## Issue #407: action-head lookup that survives any decoder — a missing
## head or a value that is out of range / not int-coercible falls back to
## index 0 (the head's neutral HOLD/IDLE value) with a warning. int()
## coerces the float/string values foreign decoders emit; containers can
## never be an index and are rejected outright.
func _head_index(action: Dictionary, head: String, size: int) -> int:
	if not action.has(head):
		return 0
	var value = action[head]
	var value_type := typeof(value)
	if value_type == TYPE_ARRAY or value_type == TYPE_DICTIONARY \
			or value_type == TYPE_OBJECT:
		push_warning(
			("BotController.set_action: head '%s' is a %s, expected an "
			+ "integer index — using 0") % [head, type_string(value_type)])
		return 0
	var index := int(value)
	if index < 0 or index >= size:
		push_warning(
			("BotController.set_action: head '%s' index %d outside [0, %d] "
			+ "— using 0") % [head, index, size - 1])
		return 0
	return index

func _idle_command() -> Dictionary:
	return {
		"move": MoveCommand.HOLD,
		"action": ActionCommand.IDLE,
		"move_dir": Vector2.ZERO,
	}

#func get_obs_space() -> Dictionary:
#	# Override only for complex obs (images, multiple keys). The base class derives
#	# {"obs": {"size": [len], "space": "box"}} from get_obs() automatically.
#	return super.get_obs_space()
