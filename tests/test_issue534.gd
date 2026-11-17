extends Node
## Regression check for issue #534: "Camera is blocked on the computer's
## turn in the first level."
##
## On a computer team's turn nobody is `controlled` (NPC figures receive
## no input), so the shared camera had NO follow target: the view stayed
## pinned to the human's figure for the whole computer turn while the
## computer acted off screen. The first fix (ZoomCamera._focus_member)
## makes the camera follow the ACTING figure of a computer turn exactly
## like the controlled member on a human turn.
##
## Rework (owner: "camera still blocks time to time, especially on the
## first turns. Make more tests and check it"): the VIEW still froze
## after a human turn. Player.set_controlled used to DISABLE the shared
## camera when its hosting figure dropped control at a computer turn's
## start — a disabled Camera2D stops driving the viewport, so the camera
## NODE kept following the acting NPC while the PICTURE stayed pinned to
## the human's last figure. The camera must stay ENABLED through every
## control change, so the checks below now verify the REAL view (the
## viewport canvas transform: the followed figure must sit at the CENTER
## of the screen), not only the camera node's position.
##
##  1. enemy first (the roll may pick the computer): the camera is
##     enabled, follows the acting NPC and centers it on screen;
##  2. player turn: the camera sits on the CONTROLLED figure (regression
##     of the classic behaviour) and the view really centers on it;
##  3. switching members keeps the camera enabled and follows the newly
##     controlled figure (the toggle fires off+on within one frame);
##  4. THE REPRO — player → computer handover: the camera stays ENABLED
##     (this is where it disabled itself before the rework), follows the
##     acting NPC and the human's figure leaves the screen center;
##  5. dropping control without a following grab (death-style handoff):
##     the camera frees the view (spectator, issue #126) but stays
##     enabled, and a later grab re-centers it;
##  6. drag-pan still moves the view DURING the computer turn (issue
##     #212) — the pan offset survives while the follow continues;
##  7. between turns the camera follows nobody: it stays put when a
##     figure moves away (free spectator camera, issue #126 regression).
##
## Run headless: godot --headless res://tests/test_issue534.tscn
## Exit code 0 = pass.

const LevelScene := preload("res://scenes/levels/Level1.tscn")
const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

const FOLLOW_TOLERANCE := 5.0
## The level camera has position_smoothing (speed 8/s): every view check
## settles long enough for the ease to finish, then this many screen
## pixels are plenty.
const VIEW_TOLERANCE := 8.0

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _camera() -> Camera2D:
	for node in get_tree().get_nodes_in_group("player_camera"):
		var cam := node as Camera2D
		if cam != null:
			return cam
	return null


func _controlled_figure() -> Node2D:
	for group in ["player_team", "enemy_team"]:
		for figure in get_tree().get_nodes_in_group(group):
			if figure.get("controlled") == true:
				return figure
	return null


## How far the figure sits from the CENTER of the SCREEN — what the
## player actually sees. A camera that is disabled (or following nobody)
## leaves the figure away from the center, whatever its node position.
func _screen_center_distance(cam: Camera2D, figure: Node2D) -> float:
	var xform: Transform2D = cam.get_viewport().get_canvas_transform()
	var view_size: Vector2 = cam.get_viewport().get_visible_rect().size
	return (xform * figure.global_position).distance_to(view_size * 0.5)


## Frames for the camera's position smoothing to settle after a change.
func _settle() -> void:
	for _i in 90:
		await get_tree().physics_frame
	for _i in 3:
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().physics_frame
	# Issue #617: every team defaults to the computer and the camera
	# boots on the free GLOBAL view — this regression checks the FOLLOW
	# behavior on computer turns, so opt the hero team in as the player
	# and pin the world-aligned follow camera before the level loads.
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	var level: Node = LevelScene.instantiate()
	add_child(level)
	for _i in 10:
		await get_tree().physics_frame
	var cam := _camera()
	if cam == null:
		push_error("FAIL: the level must host the shared camera")
		print("FAIL: no shared camera in the level")
		get_tree().quit(1)
		return
	# Freeze both NPCs: their turn AI may otherwise walk, shoot and end
	# the turn while the checks run — the camera must be the only thing
	# moving in this test.
	(level.get_node("Team2mate1") as Node2D).set_physics_process(false)
	(level.get_node("Team2mate2") as Node2D).set_physics_process(false)

	# Issue #572 added a THIRD default team: computer figures are dealt
	# round-robin to per-color team ids ("enemy:<color>"), so the literal
	# TEAM_ENEMY no longer names any team when several computer teams
	# exist. Resolve the acting computer team the way the real turn loop
	# does — from a live enemy figure — so _begin_turn gets a team that
	# actually has members.
	var computer_team: String = TurnController.TEAM_ENEMY
	for figure in get_tree().get_nodes_in_group("enemy_team"):
		var hp = figure.get("health")
		if hp is int and hp > 0:
			computer_team = TurnController.team_id_of(figure)
			break

	# --- 1) enemy rolls first: the acting NPC owns the view ----------
	# Nobody is controlled yet on a fresh level — this is the state the
	# very first computer turn starts from.
	TurnController._begin_turn(computer_team)
	await _settle()
	var acting: Node2D = TurnController.active_member
	_check(cam.enabled, "enemy-first turn: the camera must stay enabled")
	_check(acting != null and acting.is_in_group("enemy_team"),
			"the computer turn must be driven by an enemy NPC figure")
	if acting != null:
		_check(cam.global_position.distance_to(acting.global_position)
				< FOLLOW_TOLERANCE,
				"enemy-first turn: the camera node must follow the acting NPC")
		var dist: float = _screen_center_distance(cam, acting)
		_check(dist < VIEW_TOLERANCE,
				"enemy-first turn: the acting NPC must sit at the screen center (%.1f px off)"
				% dist)

	# --- 2) player turn: the controlled member owns the view ---------
	TurnController._begin_turn(TurnController.TEAM_PLAYER)
	await _settle()
	var controlled: Node2D = _controlled_figure()
	_check(controlled != null, "a player figure must be controlled on its turn")
	_check(cam.enabled, "player turn: the camera must stay enabled")
	if controlled != null:
		_check(cam.global_position.distance_to(controlled.global_position)
				< FOLLOW_TOLERANCE,
				"player turn: the camera must sit on the controlled figure")
		var pdist: float = _screen_center_distance(cam, controlled)
		_check(pdist < VIEW_TOLERANCE,
				"player turn: the controlled figure must sit at the screen center (%.1f px off)"
				% pdist)

		# --- 3) switch members: follow the new figure, stay on -------
		var before_switch: Node2D = controlled
		TeamController.switch_next()
		await _settle()
		var switched: Node2D = _controlled_figure()
		_check(switched != null and switched != before_switch,
				"switching must hand control to another team member")
		_check(cam.enabled,
				"member switch: the camera must stay enabled through the off/on toggle")
		if switched != null:
			_check(cam.global_position.distance_to(switched.global_position)
					< FOLLOW_TOLERANCE,
					"member switch: the camera must follow the newly controlled figure")

	# --- 4) THE REPRO: player → computer handover --------------------
	# Control was held a moment ago; starting the computer turn DROPS it
	# (TurnController._begin_turn clears controlled figures of other
	# teams) — the exact moment the camera used to disable itself and the
	# view froze for the whole computer turn.
	TurnController._begin_turn(computer_team)
	await _settle()
	acting = TurnController.active_member
	var none_controlled := true
	for figure in get_tree().get_nodes_in_group("player_team") \
			+ get_tree().get_nodes_in_group("enemy_team"):
		if figure.get("controlled") == true:
			none_controlled = false
	_check(none_controlled,
			"precondition: nobody is controlled on the computer's turn")
	_check(cam.enabled,
			"HANDOVER: the camera must stay enabled when control drops for the computer turn")
	_check(acting != null and acting.is_in_group("enemy_team"),
			"the computer turn must be driven by an enemy NPC figure")
	if acting != null:
		_check(cam.global_position.distance_to(acting.global_position)
				< FOLLOW_TOLERANCE,
				"computer turn: the camera must follow the acting figure")
		var cdist: float = _screen_center_distance(cam, acting)
		_check(cdist < VIEW_TOLERANCE,
				"computer turn: the acting NPC must sit at the screen center (%.1f px off) — the view must MOVE, not freeze"
				% cdist)
		var human: Node2D = _controlled_figure()
		if human == null:
			human = controlled
		if human != null:
			var hdist: float = _screen_center_distance(cam, human)
			_check(hdist > 100.0,
					"computer turn: the human's figure must leave the screen center (%.1f px)"
					% hdist)

		# --- 6) drag-pan during the computer turn (#212) -------------
		cam._pan_by(Vector2(200, 0))
		var panned_to := cam.global_position
		await _settle()
		_check(cam.global_position.distance_to(panned_to) < FOLLOW_TOLERANCE,
				"drag-pan: the offset view must hold while the follow continues")

	# --- 5) drop control with nobody grabbing it next ----------------
	# The death-style handoff: set_controlled(false) alone must FREE the
	# view (spectator camera) but never disable the camera.
	TurnController._begin_turn(TurnController.TEAM_PLAYER)
	await _settle()
	var holder: Node2D = _controlled_figure()
	if holder != null:
		holder.set_controlled(false)
		for _i in 5:
			await get_tree().physics_frame
		_check(cam.enabled,
				"dropped control: the camera must stay enabled (free spectator view)")
		var frozen := cam.global_position
		if acting != null:
			acting.global_position += Vector2(300, 0)
		await _settle()
		_check(cam.global_position.distance_to(frozen) < 0.5,
				"dropped control: the free camera must stay put while figures move")
		# A later grab re-centers the view.
		holder.set_controlled(true)
		await _settle()
		_check(cam.enabled, "re-grabbed control: the camera must be enabled")
		_check(cam.global_position.distance_to(holder.global_position)
				< FOLLOW_TOLERANCE,
				"re-grabbed control: the camera must follow the figure again")

	# --- 7) between turns: free camera, nobody is followed -----------
	TurnController.active_team = ""
	TurnController.active_member = null
	var frozen2 := cam.global_position
	if acting != null:
		acting.global_position += Vector2(300, 0)
	await _settle()
	_check(cam.global_position.distance_to(frozen2) < 0.5,
			"no turn: the camera must stay put (free spectator view)")
	_check(cam.enabled, "no turn: the camera must stay enabled (spectating)")

	level.queue_free()
	TurnController.game_over = false
	if failures == 0:
		print("PASS: issue #534 camera follows the computer's turn, enabled through every control change")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
