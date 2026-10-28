extends Node
## Regression test for issue #155: moving the player's character must never
## move an enemy character.
##
## Two checks:
##  1. Gameplay: in Level2, with a player turn active and a move action
##     held for 45 simulated seconds (spanning several turns), the player
##     and Enemy 2 must never move on the same physics frame.
##  2. Physics mechanism: a CharacterBody2D standing on a walking
##     CharacterBody2D must not be carried along — characters are never
##     platforms for each other (platform_floor_layers = terrain only).
##
## Run headless: godot --headless res://tests/test_issue155.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	ok = await _check_gameplay() and ok
	ok = await _check_no_carry() and ok
	print("ISSUE155 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


func _check_gameplay() -> bool:
	var level: Node = load("res://Level2.tscn").instantiate()
	add_child(level)
	for i in 10:
		await get_tree().physics_frame
	var player: CharacterBody2D = level.get_node("Player")
	var enemy2: CharacterBody2D = level.get_node("Npc2")
	TurnController._begin_turn(TurnController.TEAM_PLAYER)
	for i in 5:
		await get_tree().physics_frame
	var last_p: float = player.global_position.x
	var last_e: float = enemy2.global_position.x
	var sync_frames := 0
	var player_moved := false
	Input.action_press("move_right")
	for i in 2700:  # 45 simulated seconds — spans several turns.
		await get_tree().physics_frame
		var p: float = player.global_position.x
		var e: float = enemy2.global_position.x
		if absf(p - last_p) > 0.05:
			player_moved = true
			if absf(e - last_e) > 0.05:
				sync_frames += 1
		last_p = p
		last_e = e
	Input.action_release("move_right")
	level.queue_free()
	var ok := player_moved and sync_frames == 0
	print("ISSUE155 gameplay: player_moved=", player_moved,
		" sync_frames=", sync_frames, " ok=", ok)
	return ok


func _check_no_carry() -> bool:
	# Minimal mechanism check: a box rider standing on a walking box body
	# must not inherit its platform velocity (pre-fix it was carried).
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	var gshape := CollisionShape2D.new()
	var gbox := RectangleShape2D.new()
	gbox.size = Vector2(4000, 100)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position = Vector2(1000, 600)
	add_child(ground)

	var mover := CharacterBody2D.new()
	mover.collision_layer = 8
	mover.collision_mask = 1 | 8
	var ms := CollisionShape2D.new()
	var mbox := RectangleShape2D.new()
	mbox.size = Vector2(48, 64)
	ms.shape = mbox
	mover.add_child(ms)
	mover.position = Vector2(500, 500)
	add_child(mover)

	var rider := CharacterBody2D.new()
	rider.collision_layer = 2
	rider.collision_mask = 1 | 2 | 8
	var rs := CollisionShape2D.new()
	var rbox := RectangleShape2D.new()
	rbox.size = Vector2(48, 64)
	rs.shape = rbox
	rider.add_child(rs)
	rider.position = Vector2(500, 434)
	add_child(rider)
	# Same policy as Player.gd / Npc.gd since issue #155.
	mover.platform_floor_layers = 1
	rider.platform_floor_layers = 1

	for i in 20:
		await get_tree().physics_frame
	var s_m: float = mover.global_position.x
	var s_r: float = rider.global_position.x
	for i in 60:
		mover.velocity.x = 320.0
		mover.move_and_slide()
		if not rider.is_on_floor():
			rider.velocity.y += 1200.0 * get_physics_process_delta_time()
		else:
			rider.velocity.y = 0.0
		rider.velocity.x = 0.0
		rider.move_and_slide()
		await get_tree().physics_frame
	var carried: bool = absf(rider.global_position.x - s_r) > 1.0 \
		and mover.global_position.x - s_m > 100.0
	print("ISSUE155 no_carry: mover_dx=", mover.global_position.x - s_m,
		" rider_dx=", rider.global_position.x - s_r, " ok=", not carried)
	mover.queue_free()
	rider.queue_free()
	return not carried
