extends Node
## Regression check for issue #244: when the turn timer runs out while an
## effect is still pending (a thrown rock mid-flight, a grenade on fuse,
## an explosion ring still fading), the next turn must NOT begin at once —
## the character is blocked first and the turn passes only after every
## effect is done. Reproduced with the Rock tool: its throw does not end
## the turn, so the 1 s timer expires while the rock (3 s fuse) flies.
##
## Run headless: godot --headless res://tests/test_issue244.tscn
## Exit code 0 = pass.

func _ready() -> void:
	# Issue #244 repro: a short turn whose timer outlives the effect.
	GameConfig.turn_time = 1.0
	var level: Node = load("res://Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	# Wait for the player's turn to begin (an enemy team may move first).
	for i in 3600:
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			break
	var weapon: Node = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if bool(m.get("controlled")):
			weapon = m.get_node_or_null("Weapon")
			break
	if weapon == null or tc.active_team != "player":
		print("ISSUE244 no player turn/weapon, ok=false")
		get_tree().quit(1)
		return
	# Throw the rock straight away — the throw does NOT hand the turn
	# over, so the timer keeps running while the rock is in the air.
	weapon.throw_rock(0.5)
	await get_tree().physics_frame
	var thrown: bool = tc._live_projectiles() == 1 \
			and tc.active_team == "player" and not tc._switching
	# 1.6 s > the 1 s timer: the turn must be BLOCKED in the effects
	# wait, not passed — the rock still flies (3 s fuse).
	await get_tree().create_timer(1.6).timeout
	var blocked: bool = tc.active_team == "player" and tc._switching
	var frozen: bool = tc.is_input_frozen()
	var rock_alive: bool = tc._pending_effects() > 0
	# After the rock crumbles on its fuse and its blast ring fades, the
	# turn must hand over to another team on its own.
	for i in 1800:
		await get_tree().physics_frame
		if tc.active_team != "" and tc.active_team != "player" \
				and not tc._switching:
			break
	var handed_over: bool = tc.active_team != "" and tc.active_team != "player"
	var quiet: bool = tc._pending_effects() == 0
	var ok: bool = thrown and blocked and frozen and rock_alive \
			and handed_over and quiet
	print("ISSUE244 thrown=", thrown, " blocked=", blocked,
		" frozen=", frozen, " rock_alive=", rock_alive,
		" handed_over=", handed_over, " quiet=", quiet, " ok=", ok)
	get_tree().quit(0 if ok else 1)
