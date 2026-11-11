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
##
## Issue #449: the focus target is assigned by the shared FOCUS-FIRE
## HEURISTIC — a deterministic scored rule that runs inside every
## update_team() call (i.e. once per team turn, TurnController's _begin_turn)
## and writes its pick to the board. See _pick_focus_target() for the
## scoring; there is no per-agent override and no retention state — the
## same inputs always produce the same target, and a team that focus-
## fires a target keeps re-selecting it because its HP only drops.

const Stats := preload("res://scripts/CharacterStats.gd")

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
## scene tree.
## Issue #449: the focus target is the focus-fire heuristic's pick —
## RE-ASSIGNED on every call (every team turn), never retained: a wounded
## enemy stays the pick while the team shoots it (its HP term only rises),
## and once it dies the next turn's update re-targets deterministically.
## Deterministic — identical inputs give the identical pick (scene-name
## tie-break), so the whole team converges on one opponent.
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

	# Issue #449: the shared focus target is the heuristic's pick for THIS
	# turn — no retention, no world query, deterministic.
	var focus := _pick_focus_target(centroid, enemies)

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


## Issue #449: the focus-fire heuristic — which living enemy the whole
## team shoots at this turn. A deterministic, cheap score over the
## OBSERVABLE state only (each candidate's HP and its distance to the
## team's own centroid — the "key position" the issue names):
##
##   score = FOCUS_WEIGHT_HP * (1 - hp_fraction)
##         + FOCUS_WEIGHT_PROXIMITY * proximity_fraction
##
##   hp_fraction        — health / CharacterStats.MAX_HEALTH, clamped to
##                        [0, 1]; a missing `health` (nothing observable)
##                        scores like a fully-healed enemy and never wins
##                        the HP term.
##   proximity_fraction — the candidate's distance to the ally centroid,
##                        normalized across the living candidates so the
##                        closest reads 1.0 and the farthest 0.0 (all
##                        equidistant candidates read 1.0).
##
## The HP term dominates by weight: an enemy at ≤ ~33% HP outranks even a
## full-HP enemy right next to the team, while at even HP the proximity
## term decides. Equal scores fall to the deterministic scene-name
## tie-break, so identical inputs always pick the identical target.
## O(living enemies), no world queries — a heuristic that seeds
## coordination, not a learned component. The issue's optional per-agent
## override is deliberately NOT implemented (nothing overrides the team
## pick); the cover/exposure criterion stays future work until a cover
## score exists (Phase 3 — see BotController._tile_quality's fallback).
const FOCUS_WEIGHT_HP := 0.6
const FOCUS_WEIGHT_PROXIMITY := 0.4

static func _pick_focus_target(centroid: Vector2, enemies: Array) -> Node2D:
	var candidates: Array = []
	for enemy in enemies:
		if enemy is Node2D and _alive(enemy):
			candidates.append(enemy)
	if candidates.is_empty():
		return null
	# Proximity normalization band across the living candidates.
	var min_d := INF
	var max_d := -INF
	for enemy in candidates:
		var d: float = centroid.distance_squared_to(enemy.global_position)
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
	var best: Node2D = null
	var best_score := -INF
	for enemy in candidates:
		var hp = enemy.get("health")
		var hp_term := 0.0
		if hp != null:
			hp_term = 1.0 - clampf(float(hp) / float(Stats.MAX_HEALTH), 0.0, 1.0)
		var d: float = centroid.distance_squared_to(enemy.global_position)
		var prox_term := 1.0
		if max_d > min_d:
			prox_term = (max_d - d) / (max_d - min_d)
		var score: float = FOCUS_WEIGHT_HP * hp_term \
				+ FOCUS_WEIGHT_PROXIMITY * prox_term
		if best == null or score > best_score \
				or (is_equal_approx(score, best_score) \
					and String(enemy.name) < String(best.name)):
			best = enemy
			best_score = score
	return best
