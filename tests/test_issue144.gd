extends Node
## Regression check for issue #144: one character must not be able to move
## another during its move. Walking into another figure BLOCKS the mover —
## the old step-up/climb-on-top behavior (issue #39 rework) let a figure
## pass through another and displace it.
##
## Run headless: godot --headless res://tests/test_issue144.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true

	# --- Static check: the climb-on-characters mechanic is gone. ---
	var player_script: Script = load("res://Player.gd")
	var npc_script: Script = load("res://Npc.gd")
	var no_climb: bool = player_script.get_script_method_list().filter(
			func(m): return m.name == "_climb_on_characters").is_empty() \
		and npc_script.get_script_method_list().filter(
			func(m): return m.name == "_climb_on_characters").is_empty()
	ok = ok and no_climb
	print("ISSUE144 no_climb_code=", no_climb)

	# --- Physics check: a moving figure cannot displace another one. ---
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(2000.0, 40.0)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(500.0, 500.0)
	add_child(floor_body)

	var mover := CharacterBody2D.new()
	var mover_shape := CollisionShape2D.new()
	var circle_a := CircleShape2D.new()
	circle_a.radius = 32.0
	mover_shape.shape = circle_a
	mover.add_child(mover_shape)
	# Same layer setup as the character scripts (player character).
	mover.collision_layer = 8
	mover.collision_mask = 1 | 2 | 8
	mover.position = Vector2(300.0, 468.0)
	add_child(mover)

	var stander := CharacterBody2D.new()
	var stander_shape := CollisionShape2D.new()
	var circle_b := CircleShape2D.new()
	circle_b.radius = 32.0
	stander_shape.shape = circle_b
	stander.add_child(stander_shape)
	stander.collision_layer = 8
	stander.collision_mask = 1 | 2 | 8
	stander.position = Vector2(500.0, 468.0)
	add_child(stander)

	var stander_start: Vector2 = stander.global_position
	# Walk the mover straight into the standing figure for ~2 seconds.
	for i in 120:
		mover.velocity = Vector2(300.0, 0.0)
		mover.move_and_slide()
		await get_tree().physics_frame
	var stander_moved: bool = stander.global_position != stander_start
	var mover_through: bool = mover.global_position.x > stander_start.x
	ok = ok and not stander_moved and not mover_through
	print("ISSUE144 stander_moved=", stander_moved,
		" mover_through=", mover_through,
		" mover_x=", mover.global_position.x,
		" stander_x=", stander.global_position.x)

	print("ISSUE144 ok=", ok)
	get_tree().quit(0 if ok else 1)
