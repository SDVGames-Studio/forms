extends Node
## Issue #547 regression: the "choose after the start" spawn regime.
##
## - REGIME_CHOOSE is regime 3 and the menu gains its label (the level
##   configuration menu builds its OptionButton rows from
##   SpawnRegime.REGIME_LABELS, so the label list is what the player
##   sees).
## - SpawnRegime.apply spawns a SpawnChooser child on the level which
##   PAUSES the tree (the first-team roll must wait for the player)
##   and hands it the TURN-BASED placement plan — one teammate per
##   team per round, teams in play order (owner rework 2026-11-27,
##   "make spawning turn-based too").
## - A HAND entry (first-team figure) is placed by the player:
##   confirm_spot() drops it onto the first VALID surface under local
##   gravity beneath the click (floor + clearance, exactly like the
##   random regimes' sampler); a bad click is rejected and advances
##   nothing.
## - A SCRIPT entry (the other teams' figures) is placed automatically
##   one AUTO_STEP beat after it becomes current — the plan interleaves
##   them BETWEEN the player's placements, so the spawn order mirrors
##   the turn order. A click while a script beat runs is ignored.
## - After the last entry the pause lifts and the chooser is gone;
##   the other teams' figures keep their authored positions (and are
##   revealed on them), un-placed figures of a cancel too — the
##   current figure returns to its authored spot instead of staying
##   at the cursor.
## - Camera unblock (owner rework 2026-11-21, "unblock camera in the
##   spawn regime"): the chooser keeps every player_camera in
##   PROCESS_MODE_ALWAYS through its pause (pan/zoom keep working)
##   and restores the mode after; it also joins the "spawn_chooser"
##   group so ZoomCamera can fall placement clicks through.
## - Global camera default (owner rework 2026-11-24, "make the global
##   camera a default cam mode"): the phase flips the shared camera
##   MODE to GLOBAL for the placement — a follow camera chased the
##   cursor-snapped figure off the level — and restores the mode the
##   player had (both when the last figure is placed and on cancel).
## - Script-placed cast (owner rework 2026-11-26, "before I place
##   character it shouldn't exist on the ground" / "computer didn't
##   place any character at all"): the staged cast enters the phase
##   HIDDEN — a figure exists on the field only once it is placed.
## - Rework (owner 2026-11-20, "this regime doesn't work"): with the
##   #617-rework-v2 ALL-COMPUTER default the chooser still engages —
##   the hand on the mouse places the first team whether the team
##   plays as a human or as the computer. Only a level with NO
##   first-team figures (pure spectate staging) falls back to the
##   designer regime.
## - Hot-seat rework (owner 2026-11-27, "I was able to choose spawn
##   points only for the first player, but the second player's team
##   teammates were placed by the computer too"): every team
##   configured "player" places its figures BY HAND — the hero team
##   plus the staged hot-seat teams (their figures' entries carry
##   hand=true through GameConfig.team_controller_for_color, the same
##   source TurnController's hot-seat input gating reads); only the
##   computer teams' figures keep the script beats.
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
const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

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

## The plan this level must build: 3 player figures + one 2-figure
## enemy team — Hero, Npc0, Mate1, Npc1, Mate2, hand flags T,F,T,F,T
## (owner rework 2026-11-27: turn-based spawning).
const PLAN_NAMES := ["Hero", "Npc0", "Mate1", "Npc1", "Mate2"]
const PLAN_HANDS := [true, false, true, false, true]


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
	# Owner rework 2026-11-21: a camera in the player_camera group —
	# the chooser must keep it LIVE (PROCESS_MODE_ALWAYS) through the
	# pause and restore its mode after the phase.
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.add_to_group("player_camera")
	level.add_child(camera)
	add_child(level)
	var players: Array = _players(level)
	# Owner rework 2026-11-24: the player sat on a FOLLOW camera type
	# (character global) before the level — the phase must default to
	# GLOBAL and hand the follow type back afterwards.
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
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
		if camera.process_mode != Node.PROCESS_MODE_ALWAYS:
			_fail("camera stayed frozen during the choose phase")
			failed = true
		if ZoomCameraScript.camera_mode != ZoomCameraScript.MODE_GLOBAL:
			_fail("choose phase did not default the camera to GLOBAL")
			failed = true
		if not chooser.is_in_group("spawn_chooser"):
			_fail("chooser is not in the spawn_chooser group")
			failed = true
		# --- Owner rework 2026-11-27 ("make spawning turn-based too"):
		# --- the plan interleaves the teams — one teammate per team per
		# --- round, the player's figures alternating with the script's.
		var plan: Array = chooser.entries
		if plan.size() != PLAN_NAMES.size():
			_fail("chooser got %d entries, want %d"
					% [plan.size(), PLAN_NAMES.size()])
			failed = true
		else:
			for i in plan.size():
				var entry: Dictionary = plan[i]
				if str((entry["figure"] as Node).name) != PLAN_NAMES[i]:
					_fail("entry %d is %s, want %s" % [i,
							str((entry["figure"] as Node).name),
							PLAN_NAMES[i]])
					failed = true
				if bool(entry["hand"]) != PLAN_HANDS[i]:
					_fail("entry %d hand flag is %s" % [i,
							str(entry["hand"])])
					failed = true
		# --- Owner rework 2026-11-26: the cast starts HIDDEN — only the
		# --- figure being placed exists on the field, at the cursor. ---
		if not players[0].visible:
			_fail("the figure being placed is not revealed at the cursor")
			failed = true
		for figure in players.slice(1):
			if figure.visible:
				_fail("an un-placed player figure exists on the ground")
				failed = true
		for figure in _enemies(level):
			if figure.visible:
				_fail("an enemy figure exists before it is placed")
				failed = true
		# --- A bad click (far off the floor, nothing within reach) — the
		# gravity-directed ray cannot reach any surface, so nothing moves. ---
		if chooser.confirm_spot(Vector2(5000.0, 5000.0)):
			_fail("a spot without ground was accepted")
			failed = true
		if chooser.get("_index") != 0:
			_fail("a rejected click advanced the index")
			failed = true
		# --- A click while a script beat runs is ignored: place the hero,
		# --- and BEFORE the enemy's beat fires the next hand figure is
		# --- not placeable yet.
		if not chooser.confirm_spot(Vector2(220.0, 80.0)):
			_fail("spot at x=220 was rejected")
			failed = true
		if chooser.confirm_spot(Vector2(640.0, 80.0)):
			_fail("a click during a script beat placed a figure")
			failed = true
		# --- Confirmed clicks and script beats alternate (turn-based):
		# --- each beat is one AUTO_STEP, the waits cover it.
		await _tick(6)
		var npc0: Node2D = _enemies(level)[0]
		if not npc0.visible or npc0.position != Vector2(60, 60):
			_fail("the first enemy was not script-placed on its spot")
			failed = true
		if not chooser.confirm_spot(Vector2(640.0, 80.0)):
			_fail("spot at x=640 was rejected")
			failed = true
		await _tick(6)
		var npc1: Node2D = _enemies(level)[1]
		if not npc1.visible or npc1.position != Vector2(60, 60):
			_fail("the second enemy was not script-placed on its spot")
			failed = true
		if not chooser.confirm_spot(Vector2(1060.0, 80.0)):
			_fail("spot at x=1060 was rejected")
			failed = true
		# The last entry placed — the plan is done and the phase ends.
		await _tick(2)
		if get_tree().paused:
			_fail("still paused after the last figure")
			failed = true
		if camera.process_mode != Node.PROCESS_MODE_PAUSABLE:
			_fail("camera process mode not restored after the phase")
			failed = true
		if ZoomCameraScript.camera_mode != ZoomCameraScript.MODE_STATIC:
			_fail("camera MODE not restored after the phase")
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
			if not figure.visible:
				_fail("enemy figure was not script-placed")
				failed = true

	level.queue_free()
	await _tick(2)

	# --- Esc/cancel: the rest keeps the authored positions — including
	# --- the figure that was following the cursor (owner rework
	# --- 2026-11-27: it returns to its authored spot, not the mouse). ---
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
		# The hero is placed; the enemy's beat fires and the next hand
		# figure becomes current — it follows the cursor.
		await _tick(6)
		var followed := _players(level2)[1] as Node2D
		if not followed.visible:
			_fail("the next hand figure was not revealed at the cursor")
			failed = true
		var followed_at := followed.position
		if followed_at == Vector2(60, 60):
			_fail("the hand figure never followed the cursor")
			failed = true
		chooser2.cancel()
		if followed.position != Vector2(60, 60):
			_fail("cancel did not return the current figure home (%s)"
					% str(followed.position))
			failed = true
		# Cancel script-places the rest — the un-placed players and the
		# enemies — one figure per beat; wait out the tail.
		await _tick(20)
		if get_tree().paused:
			_fail("cancel did not lift the pause")
			failed = true
		if ZoomCameraScript.camera_mode != ZoomCameraScript.MODE_STATIC:
			_fail("camera MODE not restored after cancel")
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
			if not figure.visible:
				_fail("cancel did not script-place an un-placed figure")
				failed = true
		for figure in _enemies(level2):
			if not figure.visible:
				_fail("cancel did not script-place an enemy figure")
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
		if chooser3.entries.size() != PLAN_NAMES.size():
			_fail("all-computer chooser got %d entries"
					% chooser3.entries.size())
			failed = true
		if not chooser3.confirm_spot(Vector2(420.0, 80.0)):
			_fail("all-computer spot was rejected")
			failed = true
		chooser3.cancel()
		# The tail script-places the rest (one figure per beat).
		await _tick(24)
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
			if not figure.visible:
				_fail("all-computer cancel did not script-place a figure")
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
	for figure in designed:
		if not figure.visible:
			_fail("designer fallback hid the cast")
			failed = true
	level4.queue_free()
	await _tick(2)

	# --- Hot-seat rework (owner 2026-11-27, "I was able to choose
	# --- spawn points only for the first player, but the second
	# --- player's team teammates were placed by the computer too"):
	# --- the owner's exact game — two HUMAN teams (the hero plus a
	# --- staged team configured "player", Team 2's color) and one
	# --- computer team (Team 3's color). Every human team's figures
	# --- are hand entries; only the computer team's stay with the
	# --- script beats.
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	GameConfig.teams[1]["controller"] = "player"
	if GameConfig.team_controller(1) != "player":
		_fail("opted-in second team is not human-played")
		failed = true
	var level5 := _build_level()
	add_child(level5)
	# Npc0 already wears Team 2's color (the second human); Npc1
	# switches to Team 3's color so it fields the computer team.
	var bots_figure := _enemies(level5)[1] as Node2D
	bots_figure.set("team_color", Color(0.9, 0.3, 0.3, 1))
	SpawnRegime.apply(level5)
	await _tick(8)
	var chooser5 := level5.get_node_or_null("SpawnChooser")
	if chooser5 == null:
		_fail("hot-seat apply(CHOOSE) added no chooser")
		failed = true
	else:
		# Plan: Hero H, Npc0 H (the second human's), Npc1 S (the
		# computer's), Mate1 H, Mate2 H — one teammate per team per
		# round, every human team dealt to the player's hand.
		var hot_names := ["Hero", "Npc0", "Npc1", "Mate1", "Mate2"]
		var hot_hands := [true, true, false, true, true]
		var plan5: Array = chooser5.entries
		if plan5.size() != hot_names.size():
			_fail("hot-seat chooser got %d entries, want %d"
					% [plan5.size(), hot_names.size()])
			failed = true
		else:
			for i in plan5.size():
				var entry: Dictionary = plan5[i]
				if str((entry["figure"] as Node).name) != hot_names[i]:
					_fail("hot-seat entry %d is %s, want %s" % [i,
							str((entry["figure"] as Node).name),
							hot_names[i]])
					failed = true
				if bool(entry["hand"]) != hot_hands[i]:
					_fail("hot-seat entry %d hand flag is %s" % [i,
							str(entry["hand"])])
					failed = true
		# The second human's figure is placed by the PLAYER's clicks —
		# it used to be script-placed on its authored spot.
		if not chooser5.confirm_spot(Vector2(220.0, 80.0)):
			_fail("hot-seat hero spot was rejected")
			failed = true
		if not chooser5.confirm_spot(Vector2(640.0, 80.0)):
			_fail("the second human team's spot was rejected")
			failed = true
		var second := _enemies(level5)[0] as Node2D
		if absf(second.position.y - STAND_Y) > 1.0 \
				or absf(second.position.x - 640.0) > 1.0:
			_fail("the second human's figure was not placed by hand (%s)"
					% str(second.position))
			failed = true
		# The computer team's figure still takes its script beat on the
		# authored spot — and the beat ignores clicks like before.
		if chooser5.confirm_spot(Vector2(1060.0, 80.0)):
			_fail("a click during the computer's beat placed a figure")
			failed = true
		await _tick(6)
		var bot := _enemies(level5)[1] as Node2D
		if not bot.visible or bot.position != Vector2(60, 60):
			_fail("the computer team's figure was not script-placed (%s)"
					% str(bot.position))
			failed = true
		# The rest of both human teams goes back to the players' hands.
		if not chooser5.confirm_spot(Vector2(1060.0, 80.0)):
			_fail("hot-seat Mate1 spot was rejected")
			failed = true
		if not chooser5.confirm_spot(Vector2(1400.0, 80.0)):
			_fail("hot-seat Mate2 spot was rejected")
			failed = true
		await _tick(2)
		if get_tree().paused:
			_fail("hot-seat phase did not lift the pause")
			failed = true
		if level5.get_node_or_null("SpawnChooser") != null:
			_fail("hot-seat chooser outlived the phase")
			failed = true
		var stood5 := 0
		for figure in _players(level5):
			if absf(figure.position.y - STAND_Y) < 1.0:
				stood5 += 1
		if stood5 != 3:
			_fail("hot-seat: only %d/3 player figures stand" % stood5)
			failed = true
	level5.queue_free()
	await _tick(2)

	# --- Restore the world the test found. ---
	GameConfig.teams = saved_teams
	GameConfig.spawn_regime = SpawnRegime.REGIME_DESIGNER
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_GLOBAL
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
