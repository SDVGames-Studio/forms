extends Node
## Regression check for issue #312: a TRIGGERED mine must hold the turn
## handover — once a character steps on a dormant mine and its fuse starts
## burning, the turn may change only AFTER the mine has exploded (and its
## blast ring faded). Reproduced like issue #244: a 1 s turn timer and a
## mine armed next to the acting character (2 s fuse) — the timer expires
## while the fuse burns, so the handover must keep waiting.
##
## Run headless: godot --headless res://tests/test_issue312.tscn
## Exit code 0 = pass.

const MineScript := preload("res://scripts/ProjectileBody.gd")

func _ready() -> void:
	# Issue #312 repro: a short turn whose timer outlives the mine fuse.
	GameConfig.turn_time = 1.0
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
		print("ISSUE312 no player turn/actor, ok=false")
		get_tree().quit(1)
		return
	# A dormant mine right next to the acting character. It is FROZEN with
	# zero velocity, so it settles on the very first physics frame (speed
	# 0 < MINE_REST_SPEED) and arms on the next one — deterministic, no
	# bouncing race against the 1 s timer. 60 px < the 76.8 px trigger.
	var mine := RigidBody2D.new()
	mine.set_script(MineScript)
	mine.setup(ProjectileBody.Kind.MINE, Vector2.ZERO, 40, 0.0,
		Vector2(14, 14), Color(0.22, 0.24, 0.3, 1), 100.0, 0.8)
	mine.global_position = actor.global_position + Vector2(60.0, 0.0)
	add_child(mine)
	mine.freeze = true
	var armed := false
	for i in 30:  # 0.5 s of physics frames is plenty
		await get_tree().physics_frame
		if is_instance_valid(mine) and mine._armed:
			armed = true
			break
	# THE #312 contract: an armed mine is a live turn effect again — it
	# re-joined the "projectiles" group and counts as pending, so the
	# handover will hold the turn change for its fuse.
	var armed_group: bool = armed and mine.is_in_group("projectiles")
	var pending_while_burning: bool = armed and tc._pending_effects() >= 1
	print("ISSUE312 armed=", armed, " armed_group=", armed_group,
		" pending_while_burning=", pending_while_burning)
	# Wait for the 1 s turn timer to expire and start the handover.
	var switching := false
	for i in 300:  # 5 s of physics frames at most
		await get_tree().physics_frame
		if tc._switching:
			switching = true
			break
	# The core repro: at the moment the timer hands the turn over, the
	# mine is still burning its fuse — the turn must stay BLOCKED on the
	# player team instead of passing to the next one (old behavior).
	var blocked: bool = switching and tc.active_team == "player" \
			and is_instance_valid(mine) and tc._pending_effects() >= 1
	# After the fuse burns out and the blast ring fades, the turn must
	# hand over to another team on its own and the field must be quiet.
	for i in 900:  # 15 s of physics frames at most
		await get_tree().physics_frame
		if not is_instance_valid(mine) and tc.active_team != "" \
				and tc.active_team != "player" and not tc._switching:
			break
	var handed_over: bool = tc.active_team != "" and tc.active_team != "player" \
			and not tc._switching
	var quiet: bool = tc._pending_effects() == 0
	var ok: bool = armed_group and pending_while_burning and blocked \
			and handed_over and quiet
	print("ISSUE312 switching=", switching, " blocked=", blocked,
		" handed_over=", handed_over, " quiet=", quiet, " ok=", ok)
	get_tree().quit(0 if ok else 1)
