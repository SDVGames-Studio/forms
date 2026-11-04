extends Node
## Regression check for issue #299 (destructible ground precision):
## explosions used to carve RECT chunks with the blast's axis-aligned
## bounding BOX — a round blast punched a square notch with straight
## staircase walls (the issue screenshot). `apply_blast` now carves with
## the actual blast CIRCLE (same recursion as the ring carver, issue
## #250 rework): pieces disjoint from the circle survive untouched,
## fully covered pieces go, the rest halve until the circle decides by
## their centre.
##
## Run headless: godot --headless res://tests/test_issue299.tscn
## Exit code 0 = pass.

const BLAST := Vector2(0, -50)
const RADIUS := 40.0
## Safety band: no surviving piece is bigger than 2 x MIN_PIECE (16) per
## side, so its half-diagonal is under 11.4 — points 12+ px outside the
## blast circle always survive, points 12+ px inside are always carved.
const MARGIN := 12.0


func _ready() -> void:
	var chunk := DestructibleGround.new()
	chunk.rect_size = Vector2(300, 100)
	chunk.position = Vector2(1000, 1000)
	add_child(chunk)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var base: Vector2 = chunk.position
	chunk.apply_blast(base + BLAST, RADIUS)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var pieces := get_tree().get_nodes_in_group("destructible_ground")
	var covered := func(p: Vector2) -> bool:
		for piece in pieces:
			var size: Vector2 = piece.get("rect_size")
			if Rect2(piece.position - size / 2.0, size).grow(0.5).has_point(p):
				return true
		return false

	var origin_gone := not is_instance_valid(chunk)
	var p_deep := base + Vector2(0, -30)
	var p_edge := base + Vector2(20, -35)
	var p_corner := base + Vector2(38, -14)
	# Inside the blast circle -> carved away.
	var crater_open := not bool(covered.call(p_deep)) \
			and p_deep.distance_to(base + BLAST) < RADIUS - MARGIN
	var circle_carved := not bool(covered.call(p_edge)) \
			and p_edge.distance_to(base + BLAST) < RADIUS - MARGIN
	# Inside the old bounding BOX but outside the blast CIRCLE -> survives
	# (the square-notch bug of the old carver).
	var corner_kept := bool(covered.call(p_corner)) \
			and p_corner.distance_to(base + BLAST) > RADIUS + MARGIN
	var below_kept := bool(covered.call(base + Vector2(0, 10)))
	var no_slivers := true
	var centres_outside := true
	for piece in pieces:
		var size: Vector2 = piece.get("rect_size")
		if size.x < 8.0 or size.y < 8.0:
			no_slivers = false
		if (piece.position - base - BLAST).length() <= RADIUS - 0.1:
			centres_outside = false
	var ok := origin_gone and crater_open and circle_carved and corner_kept \
			and below_kept and no_slivers and centres_outside \
			and pieces.size() > 3
	print("ISSUE299 pieces=", pieces.size(), " origin_gone=", origin_gone,
		" crater_open=", crater_open, " circle_carved=", circle_carved,
		" corner_kept=", corner_kept, " below_kept=", below_kept,
		" no_slivers=", no_slivers, " centres_outside=", centres_outside)
	print("ISSUE299 ok=", ok)
	get_tree().quit(0 if ok else 1)
