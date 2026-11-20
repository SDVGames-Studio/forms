extends Node
## Issue #547 regression: the "choose after the start" spawn regime.
##
## - REGIME_CHOOSE is regime 3 and the menu gains its label (the level
##   configuration menu builds its OptionButton rows from
##   SpawnRegime.REGIME_LABELS, so the label list is what the player
##   sees).
## - SpawnRegime.apply spawns a SpawnChooser child on the level which
##   PAUSES the tree (the first-team roll must wait for the player)
##   and hands it the hero team's figures in group order, hero first.
## - confirm_spot() drops the current figure onto the first VALID
##   surface under local gravity beneath the click (floor + clearance,
##   exactly like the random regimes' sampler); a bad click is
##   rejected and advances nothing.
## - After the last figure the pause lifts and the chooser is gone;
##   computer/hot-seat teams and un-placed figures keep their authored
##   positions (Esc/cancel leaves the rest where they were staged).
## - Rework (owner 2026-11-20, "this regime doesn't work"): with the
##   #617-rework-v2 ALL-COMPUTER default the chooser still engages —
##   the hand on the mouse places the first team whether the team
##   plays as a human or as the computer. Only a level with NO
##   first-team figures (pure spectate staging) falls back to the
##   designer regime.
##
## The floor is thick so its underside is a second walkable surface
## (local gravity pulls up below the slab, like Level4's underside
## floors) — every surface counts.
##
## Run headless: godot --headless res://tests/test_issue547.tscn
## Exit code 0 = pass; the printed ISSUE547 ok= verdict is authoritative.

## A stand-in figure: the chooser moves any Node2D in the player team
## group and names itself through `display_name`.
class DummyFigure extends Node2D:
	var team_color := Color.WHITE
	var display_name := ""

const IndestructibleScript := preload(
	"res://scripts/IndestructibleGround.gd")

## Wide, thick floor: 3200x400, top surface at y=400.
const FLOOR_W := 3200.0
const FLOOR_TOP := 400.0
const FLOOR_H := 400.0

## SpawnRegime.STAND_OFF mirrored locally (kept local so a change in
## tuning fails the test loudly instead of silently tracking).
const STAND_OFF := 30.8

## Where a confirmed spot must land the figure (floor top 400).
const STAND_Y := FLOOR_TOP - STAND_OFF

## A pause-free timer that still fires while the chooser holds the
## tree paused (SceneTreeTimer with process_always).
const TICK := 0.05


func _ready() -> void:
	# The chooser pauses the whole tree — this test node must keep
	# processing (and its timers running) through that pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failed := false
	var saved_teams: Array = GameConfig.teams.duplicate(true)

	# --- Regime constants and menu label. ---
	if SpawnRegime.REGIME_CHOOSE != 3:
		_fail("REGIME_CHOOSE is not 3 (%d)" % SpawnRegime.REGIME_CHOOSE)
		failed = true
	if SpawnRegime.REGIME_LABELS.size() != 4:
		_fail("REGIME_LABELS has %d entries, want 4"
				% SpawnRegime.REGIME_LABELS.size())
		failed = true
	elif SpawnRegime.REGIME_LABELS[3] != "Choose after the start":
		_fail("regime 4 label is %s" % str(SpawnRegime.REGIME_LABELS[3]))
		failed = true

	# --- A human hero team enables the chooser (issue #617 rework v2:
	# --- the DEFAULT set is all-computer, the hero opts in explicitly). ---
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	if GameConfig.team_controller(0) != "player":
		_fail("opted-in hero team is not human-played")
		failed = true

	# --- apply() spawns a chooser that pauses the tree. ---
	var level := _build_level()
	add_child(level)
	var players: Array = _players(level)
	GameConfig.spawn_regime = SpawnRegime.REGIME_CHOOSE
	SpawnRegime.apply(level)
	await _tick(8)
	var chooser := level.get_node_or_null("SpawnChooser")
	if chooser == null:
		_fail("apply(CHOOSE) did not add a SpawnChooser")
		failed = true
	else:
		if not get_tree().paused:
			_fail("chooser did not pause the tree")
			failed = true
		if chooser.figures.size() != 3 \
				or chooser.figures[0].name != "Hero":
			_fail("chooser got %d figures, first %s"
					% [chooser.figures.size(),
					str(chooser.figures[0].name if chooser.figures.size() > 0
					else "-")])
			failed = true
		# --- A bad click (far off the floor, nothing within reach) — the
		# gravity-directed ray cannot reach any surface, so nothing moves. ---
		if chooser.confirm_spot(Vector2(5000.0, 5000.0)):
			_fail("a spot without ground was accepted")
			failed = true
		if chooser.get("_index") != 0:
			_fail("a rejected click advanced the index")
			failed = true
		# --- Confirmed clicks place the figures on the floor. ---
		for x in [220.0, 640.0, 1060.0]:
			if not chooser.confirm_spot(Vector2(x, 80.0)):
				_fail("spot at x=%s was rejected" % str(x))
				failed = true
		await _tick(4)
		if get_tree().paused:
			_fail("still paused after the last figure")
			failed = true
		if level.get_node_or_null("SpawnChooser") != null:
			_fail("chooser still on the level after finishing")
			failed = true
		var stood := 0
		for figure in players:
			if absf(figure.position.y - STAND_Y) < 1.0:
				stood += 1
		if stood != 3:
			_fail("only %d/3 figures stand on the floor" % stood)
			failed = true
		for figure in _enemies(level):
			if figure.position != Vector2(60, 60):
				_fail("chooser moved an enemy figure")
				failed = true

	level.queue_free()
	await _tick(2)

	# --- Esc/cancel: the rest keeps the authored positions. ---
	var level2 := _build_level()
	add_child(level2)
	SpawnRegime.apply(level2)
	await _tick(8)
	var chooser2 := level2.get_node_or_null("SpawnChooser")
	if chooser2 == null:
		_fail("second apply(CHOOSE) added no chooser")
		failed = true
	else:
		if not chooser2.confirm_spot(Vector2(300.0, 80.0)):
			_fail("cancel-path spot was rejected")
			failed = true
		chooser2.cancel()
		await _tick(4)
		if get_tree().paused:
			_fail("cancel did not lift the pause")
			failed = true
		var placed2 := _players(level2)
		if placed2.is_empty() \
				or absf(placed2[0].position.y - STAND_Y) > 1.0:
			_fail("the confirmed figure did not stand on the floor")
			failed = true
		for figure in placed2.slice(1):
			if figure.position != Vector2(60, 60):
				_fail("cancel moved an un-placed figure")
				failed = true
	level2.queue_free()
	await _tick(2)

	# --- All-computer set (the #617-rework-v2 DEFAULT): the chooser
	# --- must STILL engage — the owner picked the regime, the default
	# --- team set is all-computer, and the old controller fallback
	# --- silently ran the designer regime instead (owner 2026-11-20).
	GameConfig.teams = [{
		"label": "Bots", "color": Color(0.7, 0.7, 0.7),
		"controller": "computer", "shape": "square",
		"names": ["B1", "B2", "B3"],
	}]
	if GameConfig.team_controller(0) != "computer":
		_fail("computer hero team did not register")
		failed = true
	var level3 := _build_level(true)
	add_child(level3)
	SpawnRegime.apply(level3)
	await _tick(8)
	var chooser3 := level3.get_node_or_null("SpawnChooser")
	if chooser3 == null:
		_fail("chooser skipped an all-computer first team (owner rework)")
		failed = true
	else:
		if not get_tree().paused:
			_fail("all-computer chooser did not pause the tree")
			failed = true
		if chooser3.figures.size() != 3:
			_fail("all-computer chooser got %d figures"
					% chooser3.figures.size())
			failed = true
		if not chooser3.confirm_spot(Vector2(420.0, 80.0)):
			_fail("all-computer spot was rejected")
			failed = true
		chooser3.cancel()
		await _tick(4)
		if get_tree().paused:
			_fail("all-computer cancel did not lift the pause")
			failed = true
		var bots := _players(level3)
		if bots.is_empty() \
				or absf(bots[0].position.y - STAND_Y) > 1.0:
			_fail("the all-computer figure was not placed by hand")
			failed = true
		for figure in bots.slice(1):
			if figure.position != Vector2(60, 60):
				_fail("all-computer cancel moved an un-placed figure")
				failed = true
	level3.queue_free()
	await _tick(2)

	# --- Pure spectate staging (no first-team figures at all): the
	# --- designer regime keeps the authored cast — there is nothing
	# --- on the player side to click.
	var level4 := _build_level(true, false)
	add_child(level4)
	SpawnRegime.apply(level4)
	await _tick(8)
	if level4.get_node_or_null("SpawnChooser") != null:
		_fail("chooser appeared with no first-team figures")
		failed = true
	var designed := _enemies(level4)
	for i in mini(designed.size(), 3):
		if designed[i].position != Vector2(200.0 + 100.0 * i, 150.0):
			_fail("designer fallback did not fill marker %d" % i)
			failed = true
	level4.queue_free()

	# --- Restore the world the test found. ---
	GameConfig.teams = saved_teams
	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	get_tree().paused = false
	if failed:
		print("ISSUE547 ok=0")
		get_tree().quit(1)
	else:
		print("ISSUE547 ok=1")
		get_tree().quit(0)


## A pause-proof wait: SceneTreeTimers with process_always fire while
## the chooser holds the tree paused.
func _tick(frames: int) -> void:
	for i in frames:
		await get_tree().create_timer(TICK, true).timeout


## A synthetic level: the shared indestructible-floor script (a real
## gravity source, real collision), optionally a 3-figure hero team
## staged in one authored cluster and two enemies, plus (optionally)
## three "spawn_points" markers for the designer-fallback check.
func _build_level(with_markers := false, with_players := true) -> Node2D:
	var level := Node2D.new()
	level.name = "TestLevel"
	var floor := StaticBody2D.new()
	floor.name = "Ground"
	floor.script = IndestructibleScript
	floor.set("rect_size", Vector2(FLOOR_W, FLOOR_H))
	floor.position = Vector2(FLOOR_W / 2.0, FLOOR_TOP + FLOOR_H / 2.0)
	level.add_child(floor)
	if with_markers:
		for i in 3:
			var marker := Marker2D.new()
			marker.name = "M%d" % i
			marker.position = Vector2(200.0 + 100.0 * i, 150.0)
			marker.add_to_group("spawn_points")
			level.add_child(marker)
	for i in 3:
		var figure := DummyFigure.new()
		figure.name = "Hero" if i == 0 else "Mate%d" % i
		figure.display_name = "Player %d" % (i + 1)
		figure.position = Vector2(60, 60)
		figure.add_to_group("player_team")
		level.add_child(figure)
	if not with_players:
		for figure in level.get_children():
			if figure.is_in_group("player_team"):
				level.remove_child(figure)
				figure.queue_free()
	for i in 2:
		var enemy := DummyFigure.new()
		enemy.name = "Npc%d" % i
		enemy.team_color = Color(0.75, 0.2, 0.45)
		enemy.position = Vector2(60, 60)
		enemy.add_to_group("enemy_team")
		level.add_child(enemy)
	return level


func _players(level: Node) -> Array:
	var found: Array = []
	for figure in get_tree().get_nodes_in_group("player_team"):
		if figure != null and is_instance_valid(figure) \
				and SpawnRegime.is_ancestor_or_self(level, figure):
			found.append(figure)
	return found


func _enemies(level: Node) -> Array:
	var found: Array = []
	for figure in get_tree().get_nodes_in_group("enemy_team"):
		if figure != null and is_instance_valid(figure) \
				and SpawnRegime.is_ancestor_or_self(level, figure):
			found.append(figure)
	return found


func _fail(why: String) -> void:
	print("ISSUE547 ok=0 — %s" % why)
