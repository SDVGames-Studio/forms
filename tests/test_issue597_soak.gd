extends Node
## Repro harness for issue #597: "game accidentally crashed (web-version)".
##
## The owner's screenshot shows Level 4, turn 15, RED TEAM Member 1 fired
## a Baseball Bat, took 30 damage (0/100) and DIED while the OSD still
## reads "Shot fired — waiting for the projectiles..." — the crash/stall
## happened inside that post-shot effects wait, right after the acting
## member died.
##
## This harness boots the real Level 4 scene and lets the game play out:
## the human team never acts (every player turn expires on its timer, the
## same passivity as a player who stops clicking), the NPC teams fight
## each other. Engine.time_scale accelerates the run. The harness FAILS
## if the game never reaches game_over within the wall-clock budget
## (a wedged turn loop — the web "crash"), and logs the turn state when
## it stalls.
##
## Run headless: godot --headless res://tests/test_issue597_soak.tscn
## Exit code 0 = game reached game_over; 1 = stalled/failed.

const LEVEL := preload("res://scenes/levels/Level4.tscn")

## Wall-clock budget for the whole game (seconds, unscaled).
const WALL_BUDGET := 420.0

var _last_state := ""

func _ready() -> void:
	Engine.time_scale = 10.0
	add_child(LEVEL.instantiate())
	var waited := 0.0
	while waited < WALL_BUDGET:
		await get_tree().create_timer(5.0, true, false, true).timeout
		waited += 5.0
		var state := _snapshot()
		if state == _last_state and not TurnController.game_over \
				and waited > 60.0:
			# Same state for a long stretch with no game over: only a
			# warning — the safety timer may legitimately hold a wait.
			print("  [..] state unchanged: %s" % state)
		_last_state = state
		print("  [t=%3.0fs] %s" % [waited, state])
		if TurnController.game_over:
			print("SOAK-OK: game over reached after %.0f s wall" % waited)
			await get_tree().process_frame
			get_tree().quit(0)
			return
	print("SOAK-FAIL: no game over within %.0f s wall; last: %s"
			% [WALL_BUDGET, _last_state])
	await get_tree().process_frame
	get_tree().quit(1)

func _snapshot() -> String:
	var switching: String = "switching" if TurnController.is_input_frozen() else "live"
	var team: String = TurnController.active_team
	if team == "":
		team = "(none)"
	return "team=%s %s" % [team, switching]
