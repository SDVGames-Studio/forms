extends Node
## Regression check for issue #151: win conditions must be CLEAR.
##
## Asserts:
##   - a player character that reaches 0 HP is dead (_dead flag) and no
##     longer counts toward its team even before the death animation frees
##     the node (previously players never died at all);
##   - wiping the player team ends the game with "PINK TEAM WINS!";
##   - mutual destruction ends in an explicit "DRAW!" instead of a
##     phantom winner;
##   - living members of both teams keep the game running.
##
## Run headless: godot --headless res://tests/test_issue151.tscn
## Exit code 0 = pass.

func _ready() -> void:
	# Let autoloads settle first.
	await get_tree().process_frame
	var tc := TurnController
	tc._build_ui()  # ensure the win banner exists even without a level scene
	var failures: Array[String] = []

	var player: CharacterBody2D = load("res://Player.gd").new()
	add_child(player)
	var enemy: CharacterBody2D = load("res://Npc.gd").new()
	add_child(enemy)
	await get_tree().process_frame

	# Both teams alive -> game keeps running.
	tc._check_win()
	if tc.game_over:
		failures.append("game_over must stay false while both teams live")

	# Player reaches 0 HP -> dead immediately, still pre-freedom.
	player.take_damage(9999)
	if player.health != 0 or not player._dead:
		failures.append("player at 0 HP must be flagged dead")
	if tc._alive("player_team").size() != 0:
		failures.append("dead player must not count as alive")
	if not tc._alive("enemy_team").size() == 1:
		failures.append("living enemy must count as alive")
	tc._check_win()
	if not tc.game_over or tc._label == null \
			or tc._label.text != "PINK TEAM WINS!":
		failures.append("wiped player team must end with PINK TEAM WINS!")

	# Mutual destruction -> DRAW, not a phantom winner.
	tc.game_over = false
	enemy.take_damage(9999)
	tc._check_win()  # both dead now
	if tc._label == null or tc._label.text != "DRAW!":
		failures.append("both teams wiped must end in DRAW!")

	# Dead characters cannot be healed back.
	player.heal(10)
	if not player._dead or player.health != 0:
		failures.append("dead character must stay dead (no heal)")

	if failures.is_empty():
		print("ISSUE151 OK: clear win/lose/draw conditions")
		get_tree().quit(0)
	else:
		print("ISSUE151 FAIL: %s" % " | ".join(failures))
		get_tree().quit(1)
