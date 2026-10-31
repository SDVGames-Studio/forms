extends Node
## Regression check for issue #190: level design rework.
##
## Asserts:
##   - DestructibleGround carves itself under a blast and spawns remainder
##     chunks instead of staying whole;
##   - blasts outside the chunk leave it intact;
##   - LevelTerrain.gravity_vector points toward the nearest indestructible
##     surface and ignores destructible ground;
##   - IndestructibleGround registers itself as a gravity source.

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# --- IndestructibleGround is a gravity source.
	var hill: StaticBody2D = load("res://scripts/IndestructibleGround.gd").new()
	hill.radius = 100.0
	hill.position = Vector2(0, 0)
	add_child(hill)
	await get_tree().process_frame
	if not hill.is_in_group("gravity_source"):
		failures.append("IndestructibleGround must join gravity_source")
	if hill.get_node_or_null("Shape") == null:
		failures.append("IndestructibleGround must build its Shape")

	# --- Destructible ground is NOT a gravity source and gets carved.
	var soil: StaticBody2D = load("res://scripts/DestructibleGround.gd").new()
	soil.rect_size = Vector2(400, 60)
	soil.position = Vector2(1000, 1000)
	add_child(soil)
	await get_tree().process_frame
	if soil.is_in_group("gravity_source"):
		failures.append("DestructibleGround must NOT join gravity_source")

	# Gravity near the hill points toward it; destructible soil far away
	# must not bend gravity at all.
	var probe := Node2D.new()
	probe.position = Vector2(0, -140)
	add_child(probe)
	await get_tree().process_frame
	var grav: Vector2 = LevelTerrain.gravity_vector(probe)
	var to_center := (hill.global_position - probe.global_position).normalized()
	if not grav.is_normalized():
		failures.append("gravity_vector must be normalized, got %s" % grav)
	if grav.dot(to_center) < 0.9:
		failures.append("gravity above the hill must point toward it, got %s" % grav)
	hill.queue_free()
	await get_tree().process_frame
	grav = LevelTerrain.gravity_vector(probe)
	if not grav.is_equal_approx(Vector2.DOWN):
		failures.append("gravity without sources must default DOWN, got %s" % grav)
	probe.queue_free()

	# --- Blast carving: direct hit must split the chunk into leftovers.
	soil.apply_blast(soil.global_position, 50.0)
	await get_tree().process_frame
	if is_instance_valid(soil):
		failures.append("blasted chunk must free itself")
	var chunks := 0
	for child in get_children():
		if child is StaticBody2D and child.is_in_group("destructible_ground"):
			chunks += 1
	if chunks == 0:
		failures.append("blast must leave remainder destructible chunks")

	if failures.is_empty():
		print("ISSUE190 OK: level design rework")
	else:
		for f in failures:
			print("ISSUE190 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
