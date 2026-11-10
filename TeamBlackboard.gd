class_name TeamBlackboard
extends RefCounted
## Issue #446: static blackboard centralizing TEAM-level state that allied
## bots share — the assigned focus target, team average HP, living ally /
## enemy counts and the known enemy positions. The boards are keyed by the
## TurnController team id ("player", "enemy", "enemy:<color>" — issue #191),
## so every AI team keeps its OWN shared state. Game logic (TurnController)
## refreshes the acting team's board once per TURN, never per physics
## frame; BotController.reset() — the environment's episode reset
## (issue #409) — clears every board via reset_blackboard() so stale data
## never leaks between episodes. The class queries no world itself:
## update_team() receives plain alive-figure arrays from the game logic,
## and an agent reads the statics from its OWN team id alone — no direct
## reference to any other bot, which keeps the AI decision code decoupled
## from world queries and easy to test.

## Record keys of one team's board.
const FOCUS_TARGET := "focus_target"
const TEAM_HP_AVG := "team_hp_avg"
const LIVING_ALLIES := "living_allies"
const LIVING_ENEMIES := "living_enemies"
const KNOWN_ENEMY_POSITIONS := "known_enemy_positions"

## Issue #446: team id -> record Dictionary. A static var, so every bot of
## a team reads and writes the SAME board without any wiring between them.
static var _boards: Dictionary = {}


## Issue #446: refresh one team's record — called by TurnController at the
## START of the team's turn (once per turn, not per frame). `allies` and
## `enemies` are that team's alive figures; this class never touches the
## scene tree. The focus target is TEAM-shared: it is kept while it is
## still one of the living enemies, otherwise the living enemy nearest to
## the ally centroid is assigned (deterministic — scene-name tie-break),
## so the whole team converges on one opponent.
static func update_team(team_id: String, allies: Array, enemies: Array) -> void:
	var hp_sum := 0.0
	var centroid := Vector2.ZERO
	var ally_count := 0
	for ally in allies:
		if not (ally is Node2D):
			continue
		ally_count += 1
		var hp = ally.get("health")
		if hp != null:
			hp_sum += float(hp)
		centroid += ally.global_position
	if ally_count > 0:
		centroid /= float(ally_count)

	var positions: Array[Vector2] = []
	for enemy in enemies:
		if enemy is Node2D and _alive(enemy):
			positions.append(enemy.global_position)

	var focus := get_focus_target(team_id)
	if not (focus != null and _alive(focus) and enemies.has(focus)):
		focus = _nearest_to_centroid(centroid, enemies)

	_boards[team_id] = {
		FOCUS_TARGET: focus,
		TEAM_HP_AVG: (hp_sum / float(ally_count)) if ally_count > 0 else 0.0,
		LIVING_ALLIES: ally_count,
		LIVING_ENEMIES: positions.size(),
		KNOWN_ENEMY_POSITIONS: positions,
	}


## Issue #446: the team's shared focus target, or null when the board has
## no entry (or its target has since been freed) — an agent reads this
## with only its team id, holding no reference to any other bot.
static func get_focus_target(team_id: String) -> Node2D:
	var focus = _record(team_id).get(FOCUS_TARGET)
	if focus is Node2D and is_instance_valid(focus):
		return focus
	return null


## Issue #446: average HP over the team's LIVING allies (0.0 with none).
static func get_team_hp_avg(team_id: String) -> float:
	return float(_record(team_id).get(TEAM_HP_AVG, 0.0))


## Issue #446: how many of the team's allies were alive at the last update.
static func get_living_allies(team_id: String) -> int:
	return int(_record(team_id).get(LIVING_ALLIES, 0))


## Issue #446: how many enemies were alive at the team's last update.
static func get_living_enemies(team_id: String) -> int:
	return int(_record(team_id).get(LIVING_ENEMIES, 0))


## Issue #446: world positions of the living enemies known at the team's
## last update — a snapshot per turn, not a per-frame tracker.
static func get_known_enemy_positions(team_id: String) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	var positions: Array[Vector2] = _record(team_id).get(
			KNOWN_ENEMY_POSITIONS, empty)
	return positions


## Issue #446: clear every team's board — BotController.reset() (the
## environment's episode reset, issue #409) calls this so no focus target
## or HP snapshot leaks into the next episode. Idempotent: whatever
## controller resets first, the shared state goes back to empty.
static func reset_blackboard() -> void:
	_boards.clear()


static func _record(team_id: String) -> Dictionary:
	return _boards.get(team_id, {})


## Duck-typed alive check, same convention as TurnController._alive —
## a missing `health` counts as alive (stand-ins without the property).
static func _alive(figure: Node) -> bool:
	var hp = figure.get("health")
	return hp == null or float(hp) > 0.0


static func _nearest_to_centroid(centroid: Vector2, enemies: Array) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for enemy in enemies:
		if not (enemy is Node2D) or not _alive(enemy):
			continue
		var d: float = centroid.distance_squared_to(enemy.global_position)
		if best == null or d < best_distance \
				or (d == best_distance and String(enemy.name) < String(best.name)):
			best = enemy
			best_distance = d
	return best
