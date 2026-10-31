extends Node
## Regression check for issue #202: jump doesn't work.
##
## The bug: both Player.gd and Npc.gd computed the jump velocity as
## `-grav * JUMP_VELOCITY` — with the negative JUMP_VELOCITY constant that
## yields a DOWNWARD velocity, so Space pushed the figure into the floor.
##
## Asserts:
##   - both movement scripts now use `grav * JUMP_VELOCITY` (away from the
##     floor) and no longer contain the inverted `-grav *` form;
##   - physics smoke: a landed figure given the fixed jump velocity really
##     rises off the floor over subsequent frames.

const GRAV := Vector2.DOWN

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# --- Source-level regression check: the sign must stay correct.
	for path in ["res://Player.gd", "res://Npc.gd"]:
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("velocity = grav * JUMP_VELOCITY"):
			failures.append("%s must jump with `grav * JUMP_VELOCITY`" % path)
		if text.contains("-grav * JUMP_VELOCITY"):
			failures.append("%s still contains the inverted `-grav *` jump" % path)

	# --- Physics smoke: the fixed jump velocity lifts a landed figure.
	var Stats := load("res://scripts/CharacterStats.gd")
	var jump_vel: float = Stats.JUMP_VELOCITY
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(400, 40)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(0, 100)
	add_child(floor_body)

	var player: CharacterBody2D = load("res://Player.gd").new()
	var body_shape := CollisionShape2D.new()
	var body_rect := RectangleShape2D.new()
	body_rect.size = Vector2(24, 24)
	body_shape.shape = body_rect
	player.add_child(body_shape)
	player.position = Vector2(0, 60)
	add_child(player)

	# Let the figure land on the floor.
	for _i in 30:
		await get_tree().physics_frame
	if not player.is_on_floor():
		failures.append("figure must land on the floor before the jump check")
	else:
		var start_y := player.global_position.y
		# Apply the jump exactly like the fixed scripts do.
		player.velocity = GRAV * jump_vel
		var rose := false
		for _i in 30:
			await get_tree().physics_frame
			if player.global_position.y < start_y - 4.0:
				rose = true
				break
		if not rose:
			failures.append("fixed jump velocity must lift the figure off the floor")

	if failures.is_empty():
		print("ISSUE202 OK: jump works")
	else:
		for f in failures:
			print("ISSUE202 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
