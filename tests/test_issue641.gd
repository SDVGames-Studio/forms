extends Node
## Regression check for issue #641: characters must move on inclined
## surfaces.
##
## The bug: every figure left CharacterBody2D's default floor_max_angle
## (45°) untouched, so any surface steeper than 45° was classified as a
## wall — the figure could not walk up or down a real incline, it ground
## to a halt against it.
##
## The rule (issue #641): a surface is walkable when its angle with the
## gravity vector (at the current point) is under 135° — floors, slopes,
## vertical walls and overhangs up to 45° past vertical.
##
## Asserts:
##   - Stats carries the 135° walkable rule and Character applies it
##     (floor_max_angle = 3π/4) plus the snap glue for descending;
##   - physics: a 60° ramp IS floor and the figure WALKS up it through
##     the same move() every brain uses (displacement along the surface,
##     staying on floor);
##   - physics: a 150° overhang is NOT floor (the 135° boundary holds);
##   - source: Npc re-derives its wall jump from achieved motion, since
##     is_on_wall() no longer fires against vertical walls.

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# --- Source-level checks.
	var stats_text := FileAccess.get_file_as_string("res://scripts/CharacterStats.gd")
	if not stats_text.contains("FLOOR_MAX_ANGLE := PI * 0.75"):
		failures.append("Stats must define the 135° walkable rule (FLOOR_MAX_ANGLE := PI * 0.75)")
	var char_text := FileAccess.get_file_as_string("res://scripts/Character.gd")
	if not char_text.contains("floor_max_angle = Stats.FLOOR_MAX_ANGLE"):
		failures.append("Character must apply Stats.FLOOR_MAX_ANGLE")
	if not char_text.contains("floor_snap_length = Stats.FLOOR_SNAP_LENGTH"):
		failures.append("Character must apply the floor snap glue")
	var npc_script := load("res://scripts/Npc.gd")
	if npc_script == null:
		failures.append("Npc.gd must compile")
	var npc_text := FileAccess.get_file_as_string("res://scripts/Npc.gd")
	if not npc_text.contains("achieved_tangent_speed"):
		failures.append("Npc must re-derive the wall jump from achieved motion")

	# --- Physics: a 60° ramp is walkable floor.
	var char_script := load("res://scripts/Character.gd")
	var ramp := _make_slab(deg_to_rad(-60.0), Vector2.ZERO)
	var player: Character = char_script.new()
	player.add_child(_box(24.0))
	player.position = ramp.position \
			+ Vector2(0.0, -(20.0 + 12.0 + 2.0)).rotated(ramp.rotation)
	add_child(player)
	for _i in 30:
		await get_tree().physics_frame
	if not player.is_on_floor():
		failures.append("a 60° ramp must be floor (walkable incline)")
	else:
		# Walk right through the same move() call every brain issues.
		var start := player.global_position
		for _i in 60:
			await get_tree().physics_frame
			player.move(1.0)
		var along := player.global_position - start
		# The ramp's surface line is its local +x rotated by the ramp angle.
		var surface_dir := Vector2(1, 0).rotated(ramp.rotation)
		var climbed := along.dot(surface_dir)
		if climbed < 40.0:
			failures.append("the figure must walk along the 60° ramp (moved %.1f px)" % climbed)
		if not player.is_on_floor():
			failures.append("the figure must stay on floor while walking the incline")
	player.queue_free()
	ramp.queue_free()

	# --- Physics: a 150° overhang is NOT floor (135° boundary holds).
	var overhang := _make_slab(deg_to_rad(-150.0), Vector2(600, 0))
	var climber: Character = char_script.new()
	climber.add_child(_box(24.0))
	climber.position = overhang.position \
			+ Vector2(0.0, -(20.0 + 12.0 + 2.0)).rotated(overhang.rotation)
	add_child(climber)
	var on_overhang := false
	for _i in 30:
		await get_tree().physics_frame
		if climber.is_on_floor():
			on_overhang = true
	if on_overhang:
		failures.append("a 150° overhang must NOT be floor")
	climber.queue_free()
	overhang.queue_free()

	if failures.is_empty():
		print("ISSUE641 OK: inclined surfaces are walkable")
	else:
		for f in failures:
			print("ISSUE641 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


## One 800×40 static slab rotated to `angle` — its top face is then an
## incline at that angle.
func _make_slab(angle: float, at: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.rotation = angle
	body.position = at
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(800, 40)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	return body


## A square collision box of `size` px for a figure body.
func _box(size: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size, size)
	shape.shape = rect
	return shape
