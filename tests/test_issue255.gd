extends Node
## Regression check for issue #255: the shield rework.
##
##   1. ONE ATTACK: the shield blocks a single attack — health is
##      untouched, but the shield is consumed (removed) by the block;
##   2. SECOND HIT LANDS: with the shield spent, the next attack deals
##      normal damage;
##   3. SAME RULE EVERYWHERE: the identical check runs on a Player
##      figure and on an Npc — no player/computer difference;
##   4. UNTIL THE NEXT MOVE: TurnController still clears every shield of
##      the team whose fresh turn begins (the untouched-tool rule from
##      #170/#221) — and only that team's shields.
##
## Run headless: godot --headless res://tests/test_issue255.tscn
## Exit code 0 = pass.

const PlayerScript := preload("res://scripts/Player.gd")
const NpcScript := preload("res://scripts/Npc.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## The one-attack rule, checked identically for any shielded figure.
func _check_blocks_one_attack(figure: CharacterBody2D, kind: String) -> void:
	figure.set("health", 60)
	figure.set_shielded(true)
	_check(bool(figure.get("shielded")), "%s: shield must be raisable" % kind)
	figure.take_damage(30)
	_check(int(figure.get("health")) == 60,
			"%s: the shielded figure must take no damage from the blocked attack" % kind)
	_check(not bool(figure.get("shielded")),
			"%s: blocking ONE attack must consume (remove) the shield" % kind)
	figure.take_damage(10)
	_check(int(figure.get("health")) == 50,
			"%s: after the block the shield is gone — the next attack must land" % kind)


func _ready() -> void:
	await get_tree().process_frame

	# 1-3) The one-attack rule, identical for player and computer figures.
	var hero: CharacterBody2D = PlayerScript.new()
	hero.add_to_group("player_team")
	add_child(hero)
	var grunt: CharacterBody2D = NpcScript.new()
	grunt.add_to_group("enemy_team")
	add_child(grunt)
	await get_tree().process_frame
	_check_blocks_one_attack(hero, "Player")
	_check_blocks_one_attack(grunt, "Npc")

	# 4) A fresh turn of a team still ends that team's shields only.
	# (set_process is off, so _level is handed over explicitly — that is
	# the only thing _process would otherwise do for us here.)
	TurnController.set_process(false)
	var level := Node.new()
	level.add_to_group("level")
	add_child(level)
	TurnController.game_over = false
	TurnController._level = level
	hero.set("health", 60)
	grunt.set("health", 60)
	hero.set_shielded(true)
	grunt.set_shielded(true)
	TurnController._begin_turn("player")
	_check(not bool(hero.get("shielded")),
			"the player's fresh turn must remove the player figure's shield")
	_check(bool(grunt.get("shielded")),
			"the player's fresh turn must NOT remove the enemy figure's shield")
	TurnController._begin_turn(TurnController.TEAM_ENEMY)
	_check(not bool(grunt.get("shielded")),
			"the enemy team's fresh turn must remove the NPC's shield")

	for figure in [hero, grunt]:
		figure.queue_free()
	level.queue_free()

	if failures == 0:
		print("PASS: issue #255 shield rework")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
