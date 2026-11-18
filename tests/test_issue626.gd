extends Node
## Issue #626 regression: the spawn rework.
##
## - EVERY spawn mode ends in a settle pass: a figure whose body sits
##   IN the terrain is lifted along the local gravity axis to the
##   nearest clear standing spot (both directions probed per step, the
##   closest escape wins — LevelTerrain's field points out of the mass
##   from inside and onto the surface from outside).
## - Designer regime: an EMBEDDED marker is dug out too, and figures
##   beyond the marker count spawn RANDOMLY on sampled standing spots
##   instead of keeping the authored staging cluster. Levels without
##   markers keep the authored positions (still settled).
## - Figures that merely float in the air are never moved.
## - Choose regime: the chooser's own figures are skipped; the other
##   teams' authored figures are settled through the chooser's pause.
## - Random regime: the scatter's output is clear by construction —
##   asserted here so the "no one spawns in the ground" invariant is
##   checked for every mode this test drives.
##
## The floor is 3200x400 with its top face at y=400 — positions with
## y in (400, 800) are inside the ground.
##
## Run headless: godot --headless res://tests/test_issue626.tscn
## Exit code 0 = pass; the printed ISSUE626 ok= verdict is authoritative.

## A stand-in figure: SpawnRegime moves any Node2D in the team groups.
class DummyFigure extends Node2D:
	var team_color := Color.WHITE
	var display_name := ""


const IndestructibleScript := preload(
	"res://scripts/IndestructibleGround.gd")

## Wide, thick floor: 3200x400, top surface at y=400.
const FLOOR_W := 3200.0
const FLOOR_TOP := 400.0
const FLOOR_H := 400.0

## SpawnRegime constants mirrored locally (kept local so a change in
## tuning fails the test loudly instead of silently tracking).
const MIN_GAP := 80.0

## A pause-free timer that still fires while a chooser holds the tree
## paused (SceneTreeTimer with process_always).
const TICK := 0.05


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failed := false
	var saved_teams: Array = GameConfig.teams.duplicate(true)
	var saved_regime := GameConfig.spawn_regime

	# --- Designer regime: embedded marker dug out, marker figure kept,
	# --- leftovers spawn randomly on the floor. ---
	var level := _build_level(true)
	add_child(level)
	var figures := SpawnRegime._live_figures(level)
	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	SpawnRegime.apply(level)
	await _frames(6)
	var space: PhysicsDirectSpaceState2D = \
			(level as Node2D).get_world_2d().direct_space_state
	# M0 sits inside the ground — its figure must be lifted OUT, above
	# the floor top, straight up (the lift runs along the gravity axis).
	var f0 := figures[0] as Node2D
	if SpawnRegime._embedded(space, f0.global_position):
		_fail("designer: figure on the embedded marker stayed in the ground")
		failed = true
	if f0.global_position.y > FLOOR_TOP - 20.0 \
			or absf(f0.global_position.x - 400.0) > 1.0:
		_fail("designer: embedded-marker figure not lifted above the floor"
				+ str(f0.global_position))
		failed = true
	# M1 floats in the air — its figure keeps the marker position.
	if (figures[1] as Node2D).global_position != Vector2(1200.0, 200.0):
		_fail("designer: air-marker figure moved (%s)"
				% str((figures[1] as Node2D).global_position))
		failed = true
	# The four leftovers spawn randomly — standing clear on a walkable
	# surface (top OR underside — every surface counts, issue #523),
	# apart from each other.
	var stood: Array[Vector2] = []
	for i in range(2, figures.size()):
		var pos: Vector2 = (figures[i] as Node2D).global_position
		if SpawnRegime._embedded(space, pos) \
				or not _stands(level, pos):
			_fail("designer: leftover %d not standing clear (%s)"
					% [i, str(pos)])
			failed = true
		for other in stood:
			if pos.distance_to(other) < MIN_GAP - 0.5:
				_fail("designer: leftovers spawned closer than MIN_GAP")
				failed = true
		stood.append(pos)
	level.queue_free()
	await _tick(2)

	# --- Designer regime WITHOUT markers: authored positions stay,
	# --- embedded staging is dug out, floating staging is untouched. ---
	var level2 := _build_level(false, true)
	add_child(level2)
	var figures2 := SpawnRegime._live_figures(level2)
	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	SpawnRegime.apply(level2)
	await _frames(6)
	var space2: PhysicsDirectSpaceState2D = \
			(level2 as Node2D).get_world_2d().direct_space_state
	for i in [0, 1, 2]:
		var pos: Vector2 = (figures2[i] as Node2D).global_position
		if SpawnRegime._embedded(space2, pos) or pos.y > FLOOR_TOP - 20.0:
			_fail("marker-less: embedded figure %d not lifted out (%s)"
					% [i, str(pos)])
			failed = true
	if (figures2[3] as Node2D).global_position != Vector2(60.0, 60.0):
		_fail("marker-less: floating figure was moved")
		failed = true
	level2.queue_free()
	await _tick(2)

	# --- Random regime: an authored cluster inside the ground ends
	# --- standing clear — no one spawns in the ground in this mode. ---
	var level3 := _build_level(false, false)
	add_child(level3)
	var figures3 := SpawnRegime._live_figures(level3)
	GameConfig.spawn_regime = SpawnRegime.REGIME_RANDOM
	SpawnRegime.apply(level3)
	await _frames(6)
	var space3: PhysicsDirectSpaceState2D = \
			(level3 as Node2D).get_world_2d().direct_space_state
	for i in figures3.size():
		var pos: Vector2 = (figures3[i] as Node2D).global_position
		if SpawnRegime._embedded(space3, pos) \
				or not _stands(level3, pos):
			_fail("random: figure %d not standing clear (%s)"
					% [i, str(pos)])
			failed = true
	level3.queue_free()
	await _tick(2)

	# --- Choose regime: the enemies' authored staging is dug out
	# --- THROUGH the chooser's pause; the chooser itself is untouched. ---
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	var level4 := _build_level(false, true)
	add_child(level4)
	GameConfig.spawn_regime = SpawnRegime.REGIME_CHOOSE
	SpawnRegime.apply(level4)
	await _tick(14)
	var chooser := level4.get_node_or_null("SpawnChooser")
	if chooser == null:
		_fail("choose: no SpawnChooser on the level")
		failed = true
	else:
		if not get_tree().paused:
			_fail("choose: the chooser did not pause the tree")
			failed = true
		var space4: PhysicsDirectSpaceState2D = \
				(level4 as Node2D).get_world_2d().direct_space_state
		for figure in _enemies(level4):
			if SpawnRegime._embedded(space4, figure.global_position) \
					or figure.global_position.y > FLOOR_TOP - 20.0:
				_fail("choose: enemy not settled out of the ground (%s)"
						% str(figure.global_position))
				failed = true
		chooser.cancel()
		await _tick(4)
		if get_tree().paused:
			_fail("choose: cancel did not lift the pause")
			failed = true
	level4.queue_free()
	await _tick(2)

	# --- Restore the world the test found. ---
	GameConfig.teams = saved_teams
	GameConfig.spawn_regime = saved_regime
	get_tree().paused = false
	if failed:
		print("ISSUE626 ok=0")
		get_tree().quit(1)
	else:
		print("ISSUE626 ok=1")
		get_tree().quit(0)


## Physics-frame wait (the settle pass runs two physics frames after
## apply()).
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A pause-proof wait: SceneTreeTimers with process_always fire while
## a chooser holds the tree paused.
func _tick(n: int) -> void:
	for i in n:
		await get_tree().create_timer(TICK, true).timeout


## A figure stands at `at` when the sampler's own rule holds there
## (mirrors tests/test_issue523.gd): nothing solid within the clearance
## radius and the ground reaches within reach along the LOCAL gravity
## — any walkable surface counts.
func _stands(level: Node, at: Vector2) -> bool:
	var grav := LevelTerrain.gravity_at(get_tree(), at)
	var space: PhysicsDirectSpaceState2D = \
			(level as Node2D).get_world_2d().direct_space_state
	return SpawnRegime._is_clear(space, at, grav)


## A synthetic level: the shared indestructible-floor script (a real
## gravity source, real collision), player figures plus two enemies.
## With markers: M0 buried in the ground, M1 floating. With
## `embedded_staging`: the figures are authored just under the floor's
## TOP face (the realistic buried staging — deep mid-slab centers are
## not a real spawn; players at 900/430 and 1500/480, enemy 0 at
## 2100/560; the last enemy floats).
func _build_level(with_markers := false, embedded_staging := false) -> Node2D:
	var level := Node2D.new()
	level.name = "TestLevel"
	var floor := StaticBody2D.new()
	floor.name = "Ground"
	floor.script = IndestructibleScript
	floor.set("rect_size", Vector2(FLOOR_W, FLOOR_H))
	floor.position = Vector2(FLOOR_W / 2.0, FLOOR_TOP + FLOOR_H / 2.0)
	level.add_child(floor)
	if with_markers:
		var m0 := Marker2D.new()
		m0.name = "M0"
		m0.position = Vector2(400.0, 500.0)  # inside the ground
		m0.add_to_group("spawn_points")
		level.add_child(m0)
		var m1 := Marker2D.new()
		m1.name = "M1"
		m1.position = Vector2(1200.0, 200.0)  # floating in the air
		m1.add_to_group("spawn_points")
		level.add_child(m1)
	var players := [Vector2(60, 60), Vector2(60, 60), Vector2(60, 60),
			Vector2(60, 60)]
	if embedded_staging:
		players = [Vector2(900, 430), Vector2(1500, 480)]
	for i in players.size():
		var figure := DummyFigure.new()
		figure.name = "Hero" if i == 0 else "Mate%d" % i
		figure.position = players[i]
		figure.add_to_group("player_team")
		level.add_child(figure)
	var enemies := [Vector2(60, 60), Vector2(60, 60)]
	if embedded_staging:
		enemies = [Vector2(2100, 560), Vector2(60, 60)]
	for i in enemies.size():
		var enemy := DummyFigure.new()
		enemy.name = "Npc%d" % i
		enemy.team_color = Color(0.75, 0.2, 0.45)
		enemy.position = enemies[i]
		enemy.add_to_group("enemy_team")
		level.add_child(enemy)
	return level


func _enemies(level: Node) -> Array:
	var found: Array = []
	for figure in get_tree().get_nodes_in_group("enemy_team"):
		if figure != null and is_instance_valid(figure) \
				and SpawnRegime.is_ancestor_or_self(level, figure):
			found.append(figure)
	return found


func _fail(why: String) -> void:
	print("ISSUE626 ok=0 — %s" % why)
