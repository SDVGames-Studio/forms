extends Node
## Regression check for issue #534: "Camera is blocked on the computer's
## turn in the first level."
##
## On a computer team's turn nobody is `controlled` (NPC figures receive
## no input), so the shared camera had NO follow target: the view stayed
## pinned to the human's figure for the whole computer turn while the
## computer acted off screen. The fix (ZoomCamera._focus_member) makes
## the camera follow the ACTING figure of a computer turn exactly like
## the controlled member on a human turn.
##
##  1. player turn: the camera sits on the CONTROLLED figure (regression);
##  2. computer turn: the camera tracks the acting NPC (the owner's
##     repro) and no longer sits on the human's figure;
##  3. drag-pan still moves the view DURING the computer turn (issue
##     #212) — the pan offset survives while the follow continues;
##  4. between turns the camera follows nobody: it stays put when a
##     figure moves away (free spectator camera, issue #126 regression).
##
## Run headless: godot --headless res://tests/test_issue534.tscn
## Exit code 0 = pass.

const LevelScene := preload("res://scenes/levels/Level.tscn")

const FOLLOW_TOLERANCE := 5.0

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


func _ready() -> void:
	await get_tree().physics_frame
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
	(level.get_node("Npc") as Node2D).set_physics_process(false)
	(level.get_node("Npc2") as Node2D).set_physics_process(false)

	# --- 1) player turn: the controlled member owns the view ---------
	TurnController._begin_turn(TurnController.TEAM_PLAYER)
	for _i in 3:
		await get_tree().physics_frame
	var controlled: Node2D = null
	for figure in get_tree().get_nodes_in_group("player_team"):
		if figure.get("controlled") == true:
			controlled = figure
			break
	_check(controlled != null, "a player figure must be controlled on its turn")
	if controlled != null:
		_check(cam.global_position.distance_to(controlled.global_position)
				< FOLLOW_TOLERANCE,
				"player turn: the camera must sit on the controlled figure")

	# --- 2) computer turn: the camera tracks the acting NPC ----------
	TurnController._begin_turn(TurnController.TEAM_ENEMY)
	for _i in 3:
		await get_tree().physics_frame
	var acting: Node2D = TurnController.active_member
	var none_controlled := true
	for figure in get_tree().get_nodes_in_group("player_team") \
			+ get_tree().get_nodes_in_group("enemy_team"):
		if figure.get("controlled") == true:
			none_controlled = false
	_check(none_controlled,
			"precondition: nobody is controlled on the computer's turn")
	_check(acting != null and acting.is_in_group("enemy_team"),
			"the computer turn must be driven by an enemy NPC figure")
	if acting != null:
		var dist: float = cam.global_position.distance_to(
				acting.global_position)
		_check(dist < FOLLOW_TOLERANCE,
				"computer turn: the camera must follow the acting figure (dist %.1f px)"
				% dist)
		if controlled != null:
			_check(cam.global_position.distance_to(controlled.global_position)
					> 100.0,
					"computer turn: the view must not stay on the human's figure")

		# --- 3) drag-pan during the computer turn (#212) -------------
		cam._pan_by(Vector2(200, 0))
		var panned_to := cam.global_position
		for _i in 3:
			await get_tree().physics_frame
		_check(cam.global_position.distance_to(panned_to) < FOLLOW_TOLERANCE,
				"drag-pan: the offset view must hold while the follow continues")

	# --- 4) between turns: free camera, nobody is followed -----------
	TurnController.active_team = ""
	TurnController.active_member = null
	var frozen := cam.global_position
	if acting != null:
		acting.global_position += Vector2(300, 0)
	for _i in 3:
		await get_tree().physics_frame
	_check(cam.global_position.distance_to(frozen) < 0.5,
			"no turn: the camera must stay put (free spectator view)")

	level.queue_free()
	TurnController.game_over = false
	if failures == 0:
		print("PASS: issue #534 camera follows the computer's turn")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
