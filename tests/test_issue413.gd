extends Node
## Regression check for issue #413: the next team turn must start only
## after every running action finished — however the turn ended — and a
## 30 s safety timer force-starts it when an action never completes,
## logging the force-fire to the debug action log.
##
## Phase A (death handover): the acting character DIES while a live
## action holds the "projectiles" group — the turn must not pass until
## the action is gone (old code called _end_turn() directly on death).
## Phase B (safety timer): the handover waits on an action that never
## finishes; once the 30 s safety window elapses (pumped directly — the
## window is white-box the same way tc._switching is) the turn is
## forced over and the debug action log records the force-fire.
##
## Run headless: godot --headless res://tests/test_issue413.tscn
## Exit code 0 = pass.

const OSDScript := preload("res://scripts/OSD.gd")

func _ready() -> void:
	GameConfig.turn_time = 2.0
	# The safety-timer force-fire must land in the debug action log —
	# keep the debug mode on so the OSD actually records log lines.
	GameConfig.debug_mode = true
	var level: Node = load("res://scenes/levels/Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	# Wait for the player's turn to begin (an enemy team may move first).
	for i in 3600:
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			break
	var actor: Node2D = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if bool(m.get("controlled")):
			actor = m
			break
	if actor == null or tc.active_team != "player":
		print("ISSUE413 no player turn/actor, ok=false")
		get_tree().quit(1)
		return
	# PHASE A — the actor dies while an action is still "running".
	var wedge := Node2D.new()
	wedge.name = "FakePendingActionA"
	add_child(wedge)
	wedge.add_to_group("projectiles")
	actor.set("health", 0)
	for i in 30:  # 0.5 s — far longer than a frame-perfect handover
		await get_tree().physics_frame
		if not tc._switching or tc.active_team != "player":
			break
	var death_waited: bool = tc._switching and tc.active_team == "player"
	print("ISSUE413 death_waited=", death_waited)
	# The action finishing is what releases the handover — the turn
	# passes to another team on its own and the field is quiet.
	wedge.queue_free()
	var death_passed := false
	for i in 300:  # 5 s of physics frames at most
		await get_tree().physics_frame
		if not tc._switching and tc.active_team != "" \
				and tc.active_team != "player":
			death_passed = true
			break
	print("ISSUE413 death_passed=", death_passed)
	# Wait for the player team's NEXT turn (the AI teams act in between).
	for i in 5400:  # up to 90 s of physics frames
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			break
	if tc.active_team != "player" or tc._switching:
		print("ISSUE413 no second player turn, ok=false")
		get_tree().quit(1)
		return
	# PHASE B — an action that NEVER finishes: the handover holds…
	var wedge2 := Node2D.new()
	wedge2.name = "FakePendingActionB"
	add_child(wedge2)
	wedge2.add_to_group("projectiles")
	tc._begin_effects_wait()
	# 7 s of REAL frames: the old 5 s switch watchdog (issue #85) would
	# have forced this turn over by now — the #413 safety window must
	# still be holding the handover for the never-finishing action.
	for i in 420:
		await get_tree().physics_frame
		if not tc._switching:
			break
	var safety_held: bool = tc._switching and tc.active_team == "player"
	print("ISSUE413 safety_held=", safety_held)
	# …until the 30 s safety window elapses — then the turn is FORCED
	# over (one white-box pump of the watchdog with the full window).
	tc._process_watchdog(tc.EFFECTS_SAFETY_TIME + 1.0)
	var forced: bool = not tc._switching and tc.active_team != "" \
			and tc.active_team != "player" and is_instance_valid(wedge2)
	# The force-fire must be in the debug action log.
	var logged := false
	var osd: Node = OSDScript._current
	if osd != null and is_instance_valid(osd):
		for line in osd._log_lines:
			if str(line[0]).find("safety timer") != -1:
				logged = true
	print("ISSUE413 forced=", forced, " logged=", logged)
	var ok: bool = death_waited and death_passed and safety_held \
			and forced and logged
	print("ISSUE413 ok=", ok)
	get_tree().quit(0 if ok else 1)
