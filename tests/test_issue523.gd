extends Node
## Issue #523 regression: spawn regimes chosen in the level setup menu.
##
## - REGIME_RANDOM  — every figure moves to its own standing spot: all
##   figures stand ON a walkable surface (validated the way the sampler
##   does: clearance around the spot, floor under LOCAL gravity — the
##   slab's side faces and rounded corners are walkable too, exactly
##   like Level4's arcs), spread by at least MIN_GAP, away from the
##   authored cluster.
## - REGIME_GROUPED — teammates stay within TEAM_SPREAD*2 of each
##   other (the team anchor plus free spots around it); every figure
##   stands on a surface and keeps MIN_GAP from everyone else.
## - REGIME_DESIGNER — the level's "spawn_points" markers are filled
##   in NAME order with the figure plan (player team first, then the
##   computer teams); without markers the authored positions stay.
## - The default regime is DESIGNER (today's behavior).
##
## The slab is thick so its underside is a second walkable surface
## (local gravity pulls up below the slab, like Level4's underside
## floors); the surface check accepts every surface, not only the top.
##
## Run headless: godot --headless res://tests/test_issue523.tscn
## Exit code 0 = pass; the printed ISSUE523 ok= verdict is authoritative.

## A stand-in figure: SpawnRegime moves any Node2D in the team groups
## and groups figures by their `team_color`.
class DummyFigure extends Node2D:
	var team_color := Color.WHITE

const IndestructibleScript := preload(
	"res://scripts/IndestructibleGround.gd")

## Wide, thick floor: 3200x400, top surface at y=400.
const FLOOR_W := 3200.0
const FLOOR_TOP := 400.0
const FLOOR_H := 400.0

## Mirrors scripts/SpawnRegime.gd's constants (kept local so a change
## in tuning fails the test loudly instead of silently tracking).
const MIN_GAP := 80.0
const TEAM_SPREAD := 160.0

const TEAMS := [
	Color(1, 0.84, 0.2), Color(0.75, 0.2, 0.45), Color(0.35, 0.6, 1),
]


func _ready() -> void:
	var failed := false
	if GameConfig.spawn_regime != SpawnRegime.REGIME_DESIGNER:
		_fail("default regime is not DESIGNER (%d)"
				% GameConfig.spawn_regime)
		failed = true

	# --- Random regime: everyone on their own spot on a surface. ---
	var level := _build_level()
	add_child(level)
	var figures := SpawnRegime._live_figures(level)
	if figures.size() != 9:
		_fail("expected 9 live figures, got %d" % figures.size())
		failed = true
	GameConfig.spawn_regime = SpawnRegime.REGIME_RANDOM
	SpawnRegime.apply(level)
	await _settle()
	var positions := _positions(figures)
	var bounds: Rect2 = SpawnRegime._terrain_rect(level).grow(64.0)
	for i in positions.size():
		if not _stands(level, positions[i]):
			_fail("random: figure %d at %s does not stand on a surface"
					% [i, str(positions[i])])
			failed = true
		if not bounds.has_point(positions[i]):
			_fail("random: figure %d at %s is outside the terrain"
					% [i, str(positions[i])])
			failed = true
		if positions[i].distance_to(Vector2(60, 60)) < 200.0:
			_fail("random: figure %d stayed in the authored cluster" % i)
			failed = true
	if not _spread_apart(positions):
		_fail("random: some figure pair is closer than MIN_GAP")
		failed = true

	# --- Grouped regime: teammates together, everyone on a surface. ---
	level = _build_level()
	add_child(level)
	figures = SpawnRegime._live_figures(level)
	GameConfig.spawn_regime = SpawnRegime.REGIME_GROUPED
	SpawnRegime.apply(level)
	await _settle()
	positions = _positions(figures)
	for at in positions:
		if not _stands(level, at):
			_fail("grouped: figure at %s does not stand on a surface"
					% str(at))
			failed = true
	if not _spread_apart(positions):
		_fail("grouped: some figure pair is closer than MIN_GAP")
		failed = true
	var per_team: Dictionary = {}
	for i in figures.size():
		var color: Color = figures[i].get("team_color")
		if not per_team.has(color):
			per_team[color] = []
		per_team[color].append(positions[i])
	if per_team.size() != 3:
		_fail("grouped: expected 3 teams, got %d" % per_team.size())
		failed = true
	for team in per_team:
		var mates: Array = per_team[team]
		for i in mates.size():
			for j in range(i + 1, mates.size()):
				if (mates[i] as Vector2).distance_to(mates[j]) \
						> TEAM_SPREAD * 2.0:
					_fail("grouped: teammates %s px apart in one team"
							% str((mates[i] as Vector2).distance_to(mates[j])))
					failed = true

	# --- Designer regime with markers: the plan fills them in NAME
	# order (player team first, then the computer teams — name the
	# player markers so they sort first). ---
	level = _build_level()
	add_child(level)
	var marker_names := ["A1", "A2", "A3", "B1", "B2", "B3"]
	var expected: Array[Vector2] = []
	for i in marker_names.size():
		var marker := Marker2D.new()
		marker.name = marker_names[i]
		marker.position = Vector2(200.0 + 120.0 * i, 100.0 + 40.0 * i)
		marker.add_to_group("spawn_points")
		level.add_child(marker)
		expected.append(marker.position)
	figures = SpawnRegime._live_figures(level)
	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	SpawnRegime.apply(level)
	for i in expected.size():
		if (figures[i] as Node2D).global_position != expected[i]:
			_fail("designer: figure %d not on its marker (at %s, want %s)"
					% [i, str((figures[i] as Node2D).global_position),
					str(expected[i])])
			failed = true

	# --- Designer regime WITHOUT markers: authored positions stay. ---
	level = _build_level()
	add_child(level)
	figures = SpawnRegime._live_figures(level)
	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	SpawnRegime.apply(level)
	for i in figures.size():
		if (figures[i] as Node2D).global_position != Vector2(60, 60):
			_fail("designer: figure %d moved without markers" % i)
			failed = true

	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	if not failed:
		print("ISSUE523 ok=1")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _positions(figures: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for figure in figures:
		out.append((figure as Node2D).global_position)
	return out


## SpawnRegime's scatter lands two physics frames after apply() — the
## freshly-built ground must flush into the physics space first.
func _settle() -> void:
	for i in 3:
		await get_tree().physics_frame


## A figure stands at `at` when the sampler's own rule holds there:
## nothing solid within CLEAR_RADIUS, and the ground reaches within
## STAND_OFF + CLEAR_RADIUS along the LOCAL gravity (any surface —
## top, underside, side walls, rounded corners).
func _stands(level: Node, at: Vector2) -> bool:
	var grav := LevelTerrain.gravity_at(get_tree(), at)
	var space: PhysicsDirectSpaceState2D = \
			(level as Node2D).get_world_2d().direct_space_state
	return SpawnRegime._is_clear(space, at, grav)


func _spread_apart(positions: Array[Vector2]) -> bool:
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < MIN_GAP - 0.5:
				return false
	return true


func _fail(why: String) -> void:
	print("ISSUE523 ok=0 — %s" % why)


## A synthetic level: the shared indestructible-floor script (a real
## gravity source, real collision) plus a 9-figure cast staged in one
## authored cluster (3 teams x 3 figures, player team first).
func _build_level() -> Node2D:
	var level := Node2D.new()
	level.name = "TestLevel"
	var floor := StaticBody2D.new()
	floor.name = "Ground"
	floor.script = IndestructibleScript
	floor.set("rect_size", Vector2(FLOOR_W, FLOOR_H))
	floor.position = Vector2(FLOOR_W / 2.0, FLOOR_TOP + FLOOR_H / 2.0)
	level.add_child(floor)
	for t in TEAMS.size():
		for m in 3:
			var figure := DummyFigure.new()
			figure.name = "F%d_%d" % [t, m]
			figure.team_color = TEAMS[t]
			figure.position = Vector2(60, 60)
			figure.add_to_group("player_team" if t == 0 else "enemy_team")
			level.add_child(figure)
	return level
