extends Node
## Regression check for issue #191: uniform multi-team turn order.
##
## Asserts:
##   - a level with several AI teams (distinct team_color values) gets one
##     team id per color, plus the player team;
##   - _turn_order is a shuffled permutation of ALL teams (first N turns
##     visit every team exactly once, N = number of teams);
##   - _next_alive_team repeats that exact order cyclically;
##   - a level with a single AI team keeps the legacy "enemy" id.

func _ready() -> void:
	await get_tree().process_frame
	var tc := TurnController
	var failures: Array[String] = []

	var player: CharacterBody2D = load("res://Player.gd").new()
	add_child(player)
	var red: CharacterBody2D = load("res://Npc.gd").new()
	red.team_color = Color(0.85, 0.2, 0.2)
	add_child(red)
	var blue: CharacterBody2D = load("res://Npc.gd").new()
	blue.team_color = Color(0.2, 0.5, 0.95)
	add_child(blue)
	var green: CharacterBody2D = load("res://Npc.gd").new()
	green.team_color = Color(0.22, 0.7, 0.3)
	add_child(green)
	await get_tree().process_frame

	# --- Multi-team scan.
	tc._scan_teams()
	if tc._teams.size() != 4:
		failures.append("expected 4 teams, got %d" % tc._teams.size())
	var sorted_teams: Array[String] = tc._teams.duplicate()
	sorted_teams.sort()
	var sorted_order: Array[String] = tc._turn_order.duplicate()
	sorted_order.sort()
	if sorted_teams != sorted_order:
		failures.append("turn order must be a permutation of all teams")
	if tc._turn_order.size() != tc._teams.size():
		failures.append("turn order must contain every team exactly once")

	# Player team id and distinct enemy ids.
	if not tc.is_player_team(tc.TEAM_PLAYER):
		failures.append("player id must be the player team")
	var ids := {}
	for id in tc._teams:
		ids[id] = true
	if ids.size() != 4:
		failures.append("team ids must be distinct, got %s" % str(tc._teams))
	if tc.team_id_of(red) == tc.team_id_of(blue) \
			or tc.team_id_of(blue) == tc.team_id_of(green):
		failures.append("different colors must map to different team ids")

	# --- Cyclic repetition: walking N*2 steps repeats the same order.
	var n := tc._turn_order.size()
	var first_pass: Array[String] = []
	for i in n:
		first_pass.append(tc._next_alive_team())
	var second_pass: Array[String] = []
	for i in n:
		second_pass.append(tc._next_alive_team())
	if first_pass != second_pass:
		failures.append("order must repeat: %s then %s" % [str(first_pass), str(second_pass)])

	# --- Elimination: dead teams are skipped, others keep cycling.
	blue.take_damage(9999)
	await get_tree().process_frame
	for i in n * 2:
		var id := tc._next_alive_team()
		if tc.team_id_of(blue) == id and blue.health > 0:
			pass  # blue is dead; its id must never come up
		if id == tc._color_to_id.get(blue.team_color, ""):
			failures.append("wiped team must be skipped in the order")
			break

	# --- Legacy single-enemy level keeps the plain "enemy" id.
	red.queue_free()
	green.queue_free()
	await get_tree().process_frame
	tc._scan_teams()
	if tc.team_id_of(blue) != tc.TEAM_ENEMY:
		failures.append("single AI team must keep the legacy 'enemy' id")

	if failures.is_empty():
		print("ISSUE191 OK: uniform multi-team turn order")
	else:
		for f in failures:
			print("ISSUE191 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
