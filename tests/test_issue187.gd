extends Node
## Regression check for issue #187: after the CONTROLLED player character
## dies, the view must not stay blocked and the player must be able to act
## again — including handing control to another team member.
##
## Verifies, in the real Level scene:
##  1. killing the controlled member (the camera host) does not leave the
##     game without a camera — a survivor regains control and the shared
##     camera group is repopulated and enabled;
##  2. the turn flow continues (the enemy turn starts, then a fresh player
##     turn begins);
##  3. on the fresh player turn the Switch tool hands control to another
##     living member and TurnController.active_member follows it.
##
## Run headless: godot --headless res://tests/test_issue187.tscn
## Exit code 0 = pass.

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])


func _controlled() -> Node:
	for m in get_tree().get_nodes_in_group("player_team"):
		if is_instance_valid(m) and m.get("controlled") == true:
			return m
	return null


func _camera_ok() -> bool:
	for camera in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(camera) and camera.enabled:
			return true
	return false


func _ready() -> void:
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame
	# Get to a player turn (skip any enemy turn quickly).
	var waited := 0.0
	while TurnController.active_team != "player" and waited < 20.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		if TurnController.active_team == "enemy":
			TurnController._end_turn()
			for i in 5:
				await get_tree().physics_frame
			waited = 0.0
	_check(TurnController.active_team == "player", "reached a player turn")

	# Make sure the camera HOST (Player, scene camera parent) is the one
	# that dies — worst case for the view.
	var victim := _controlled()
	if victim == null:
		for m in get_tree().get_nodes_in_group("player_team"):
			if is_instance_valid(m) and m.name == "Player":
				victim = m
				break
	if victim == null:
		victim = get_tree().get_first_node_in_group("player_team")
	_check(victim != null, "found a victim to kill")
	var team_before := 0
	for m in get_tree().get_nodes_in_group("player_team"):
		if is_instance_valid(m):
			team_before += 1
	TurnController.active_member = victim
	victim.take_damage(1000)
	_check(victim.get("health") == 0, "victim health reached 0")

	# The death must be noticed: the turn hands over to the enemy team.
	waited = 0.0
	while TurnController.active_team != "enemy" and waited < 3.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	_check(TurnController.active_team == "enemy",
			"turn handed over to the enemy team after the death")

	# Run through the enemy turn quickly until the next player turn.
	waited = 0.0
	while TurnController.active_team != "player" and waited < 20.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		if TurnController.active_team == "enemy" and not TurnController.game_over:
			TurnController._end_turn()
			for i in 5:
				await get_tree().physics_frame
			waited = 0.0
	_check(TurnController.active_team == "player", "a fresh player turn began")
	_check(not TurnController.game_over, "game is not over while survivors remain")

	# 1: exactly one living member is controlled again.
	var ctrl := _controlled()
	_check(ctrl != null and is_instance_valid(ctrl) and ctrl.get("health") > 0,
			"a living member is controlled after the death")
	_check(_camera_ok(), "an enabled shared camera exists after the death")

	# 3: the Switch tool hands control over on the fresh turn.
	var switch_ok := false
	if ctrl != null and ToolInventory.use_tool(ToolInventory.TOOL_SWITCH):
		await get_tree().physics_frame
		var am = TurnController.active_member
		switch_ok = am != null and is_instance_valid(am) \
				and am != ctrl and am.get("controlled") == true
	_check(switch_ok, "Switch tool hands control to another member")

	if _failures.is_empty():
		print("PASS: issue #187 regression checks all passed")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % _failures.size())
		get_tree().quit(1)
