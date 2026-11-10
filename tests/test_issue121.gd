extends Node
## Regression check for issue #121: a real scene test — a simple level with
## two computer teams of one member each fights itself to a winner, while
## the user (who has no team in this level) can only spectate.
##
## Run headless: godot --headless res://tests/test_issue121.tscn
## Exit code 0 = pass.

const TIME_LIMIT := 120.0

var _blue_was_active := false


func _ready() -> void:
	var level: Node = load("res://LevelDuel.tscn").instantiate()
	add_child(level)
	# Let the scene settle (Npc._ready builds teams, roll picks a team).
	for i in 30:
		await get_tree().physics_frame
	var blue: Node = null
	var red: Node = null
	for node in get_tree().get_nodes_in_group("player_team"):
		blue = node
	for node in get_tree().get_nodes_in_group("enemy_team"):
		red = node
	var teams_ok: bool = blue != null and red != null
	# Spectator check: no player-controlled figure exists in this level.
	var spectator: bool = get_tree().get_nodes_in_group("player").is_empty()
	# Speed the duel up: leave Red with a sliver of health so a single
	# clean hit finishes it after a few rounds.
	if red != null:
		red.take_damage(red.get("health") - 15)
	var elapsed := 0.0
	while elapsed < TIME_LIMIT and not TurnController.game_over:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if TurnController.active_member == blue:
			_blue_was_active = true
	var over: bool = TurnController.game_over
	var one_left: bool = (is_instance_valid(blue) and not is_instance_valid(red)) \
		or (is_instance_valid(red) and not is_instance_valid(blue))
	var ai_played: bool = _blue_was_active
	var ok: bool = teams_ok and spectator and over and one_left and ai_played
	print("ISSUE121 teams=", teams_ok, " spectator=", spectator,
		" game_over=", over, " one_left=", one_left,
		" blue_acted=", ai_played, " ok=", ok)
	get_tree().quit(0 if ok else 1)
