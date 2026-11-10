extends Node
## Regression check for issue #343: a team's turn rotates its members.
##
## Asserts:
##   - each new turn of a team begins with the member AFTER the one that
##     acted last time (cyclic) — never the same figure twice in a row;
##   - the player team rotates only its CONTROLLABLE figures — AI allies
##     (Npc.gd in player_team, issue #121) are never handed the turn;
##   - control follows the rotation for the player team (the newly
##     rotated member is `controlled` and TurnController.active_member);
##   - a dead member drops out of the rotation and the cycle continues
##     with the surviving members.
##
## Run headless: godot --headless res://tests/test_issue343.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var tc := TurnController
	var failures: Array[String] = []

	# A "level" node so _begin_turn's guard passes; deterministic order.
	var level := Node.new()
	level.add_to_group("level")
	add_child(level)

	# Player team: two controllable figures + one AI ally (issue #121).
	var p1: CharacterBody2D = load("res://Player.gd").new()
	var p2: CharacterBody2D = load("res://Player.gd").new()
	var ally: CharacterBody2D = load("res://Npc.gd").new()
	ally.team = "player"
	# Enemy team: three Npcs of one color (single "enemy" id, issue #191).
	var red := Color(0.85, 0.2, 0.2)
	var e1: CharacterBody2D = load("res://Npc.gd").new()
	var e2: CharacterBody2D = load("res://Npc.gd").new()
	var e3: CharacterBody2D = load("res://Npc.gd").new()
	for e in [e1, e2, e3]:
		e.team_color = red
	add_child(p1)
	add_child(p2)
	add_child(ally)
	add_child(e1)
	add_child(e2)
	add_child(e3)
	await get_tree().process_frame

	tc._scan_teams()
	var enemy_id: String = tc.team_id_of(e1)
	# Deterministic team order: player first, enemy second.
	tc._turn_order = [tc.TEAM_PLAYER, enemy_id]
	tc._turn_index = 0
	tc._last_active = {}

	var player_picks: Array[String] = []
	var enemy_picks: Array[String] = []
	# Play six turns (three per team) through the REAL flow.
	for i in 6:
		tc._begin_turn(tc.TEAM_PLAYER if i % 2 == 0 else enemy_id)
		var pick: String = str(tc.active_member.get("name"))
		if i % 2 == 0:
			player_picks.append(pick)
			# Control must follow the rotation for the player team.
			if tc.active_member.get("controlled") != true:
				failures.append("player turn %d: rotated member not controlled" % i)
		else:
			enemy_picks.append(pick)
		tc._end_turn()

	# Rotation: p1 -> p2 -> p1 for the player team, ally never chosen.
	if player_picks != [str(p1.name), str(p2.name), str(p1.name)]:
		failures.append("player rotation wrong: %s" % str(player_picks))
	if str(ally.name) in player_picks:
		failures.append("AI ally must never receive the player turn")
	# Rotation: e1 -> e2 -> e3 for the enemy team.
	if enemy_picks != [str(e1.name), str(e2.name), str(e3.name)]:
		failures.append("enemy rotation wrong: %s" % str(enemy_picks))

	# A dead member drops out: kill p2, the next player turn repeats p1
	# (its only controllable survivor), never picks the dead figure.
	p2.take_damage(99999)
	await get_tree().process_frame
	tc._begin_turn(tc.TEAM_PLAYER)
	if tc.active_member != p1:
		failures.append("dead member must drop out, expected p1 got %s"
				% str(tc.active_member))
	tc._end_turn()
	# Enemy side: kill e2; with e3 last active the next pick is e1
	# (cycle continues among the living).
	e2.take_damage(99999)
	await get_tree().process_frame
	tc._last_active[enemy_id] = e3
	var members := tc._alive_of(enemy_id)
	var nxt: Node = tc._next_member(enemy_id, members)
	if nxt != e1:
		failures.append("enemy cycle must continue with e1, got %s" % str(nxt))
	if tc._next_member(enemy_id, tc._alive_of(enemy_id)) == e2:
		failures.append("dead enemy must never be picked")

	# Cleanup the fake level so the autoload drops its state.
	level.queue_free()
	await get_tree().process_frame
	tc._on_level_changed()

	if failures.is_empty():
		print("ISSUE343 OK: team members rotate on new turns")
	else:
		for f in failures:
			print("ISSUE343 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
