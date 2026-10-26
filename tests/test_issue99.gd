extends Node
## Regression check for issue #99: enemy NPCs must be able to damage the
## player's team. Before the fix, NPC grenades were lobbed with a fixed arc
## that fell back onto the shooter's own team (blast = friendly fire since
## #57/#71), so enemies killed themselves and players never took damage on
## Level3's vertical layout.
##
## Run headless: godot --headless res://tests/test_issue99.tscn
## Exit code 0 = pass: at least one player-team member takes damage during
## simulated enemy turns.

func _ready() -> void:
	var level: Node = load("res://Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	# Wait for the first turn to begin.
	for i in 300:
		await get_tree().physics_frame
		if tc.active_team != "":
			break
	# Simulate up to 6 full round trips, skipping player turns instantly.
	for round_i in 6:
		var waited := 0
		while tc.active_team == "player" and waited < 400:
			tc._turn_left = 0.0
			await get_tree().physics_frame
			waited += 1
		waited = 0
		while tc.active_team == "enemy" and waited < 480:
			await get_tree().physics_frame
			waited += 1
			if waited % 60 == 0:
				var ehp := []
				for m in get_tree().get_nodes_in_group("enemy_team"):
					ehp.append([m.name, m.health])
				var php := []
				for m in get_tree().get_nodes_in_group("player_team"):
					php.append([m.name, m.health])
				print("ISSUE99 t=", waited, " enemy=", ehp, " player=", php)
		if tc.game_over:
			break
	var damaged := false
	for m in get_tree().get_nodes_in_group("player_team"):
		if int(m.health) < 100:
			damaged = true
	# Enemies must not wipe themselves out without scratching the players.
	var enemies_alive := get_tree().get_nodes_in_group("enemy_team").size()
	var ok: bool = damaged and (not bool(tc.game_over) or enemies_alive > 0)
	print("ISSUE99 damaged=", damaged, " enemies_alive=", enemies_alive,
		" game_over=", tc.game_over, " ok=", ok)
	get_tree().quit(0 if ok else 1)
