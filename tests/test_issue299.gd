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
## Issue #299 rework: the owner's screenshots showed the RING level
## (Level5) still carved rough. Both carvers now split much finer —
## rect pieces down to 2 px sides, ring sectors down to a 4 px band and
## a 0.005 rad slice — so this test also pins the RING crater edge to
## the true blast circle within a few pixels (the old 24 px bands /
## 0.05 rad slices missed by up to ~50 px).
##
## Run headless: godot --headless res://tests/test_issue299.tscn
## Exit code 0 = pass.

const BLAST := Vector2(0, -50)
const RADIUS := 40.0
## Safety band: no surviving piece is bigger than 2 x MIN_PIECE (4) per
## side, so its half-diagonal is under 2.9 — points 6+ px outside the
## blast circle always survive, points 6+ px inside are always carved.
const MARGIN := 6.0

## Ring probe geometry (Level5-style band around a distant arena centre).
const RING_INNER := 640.0
const RING_OUTER := 1280.0
const RING_BLAST_R := 961.0
const RING_BLAST_A := 0.1
const RING_RADIUS := 60.0
## The crater edge along the ray through the blast centre sits at
## |r - RING_BLAST_R| = RING_RADIUS; finer carving must land within
## 15 px of it (the old granularity missed by up to ~50 px).
const EDGE_TOLERANCE := 15.0


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
		if size.x < DestructibleGround.MIN_PIECE \
				or size.y < DestructibleGround.MIN_PIECE:
			no_slivers = false
		if (piece.position - base - BLAST).length() <= RADIUS - 0.1:
			centres_outside = false
	var ok := origin_gone and crater_open and circle_carved and corner_kept \
			and below_kept and no_slivers and centres_outside \
			and pieces.size() > 3
	print("ISSUE299 rect pieces=", pieces.size(), " origin_gone=", origin_gone,
		" crater_open=", crater_open, " circle_carved=", circle_carved,
		" corner_kept=", corner_kept, " below_kept=", below_kept,
		" no_slivers=", no_slivers, " centres_outside=", centres_outside)

	# ---- Ring carving (the rework): craters open AND the carved edge
	# hugs the true blast circle within EDGE_TOLERANCE px. ----
	var rect_piece_ids := {}
	for piece in pieces:
		rect_piece_ids[piece.get_instance_id()] = true

	var arena := Node2D.new()
	arena.position = Vector2(5000, 5000)
	add_child(arena)
	var ring := DestructibleGround.new()
	ring.ring_inner = RING_INNER
	ring.ring_outer = RING_OUTER
	arena.add_child(ring)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var centre := arena.position + Vector2(
			cos(RING_BLAST_A), sin(RING_BLAST_A)) * RING_BLAST_R
	for piece in get_tree().get_nodes_in_group("destructible_ground"):
		if not rect_piece_ids.has(piece.get_instance_id()):
			piece.apply_blast(centre, RING_RADIUS)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ring_pieces: Array = []
	for piece in get_tree().get_nodes_in_group("destructible_ground"):
		if not rect_piece_ids.has(piece.get_instance_id()):
			ring_pieces.append(piece)

	var covered_ring := func(p_local: Vector2) -> bool:
		for piece in ring_pieces:
			var d := p_local.length()
			if d < float(piece.ring_inner) - 0.5 \
					or d > float(piece.ring_outer) + 0.5:
				continue
			var ad := absf(wrapf(
					p_local.angle() - float(piece.arc_center), -PI, PI))
			if ad <= float(piece.arc_span) / 2.0 + 0.0005:
				return true
		return false

	var aim := Vector2(cos(RING_BLAST_A), sin(RING_BLAST_A))
	# Deep probes (off-axis, well inside the blast circle) -> carved.
	var deep_carved := true
	for da in [-0.03, 0.0, 0.03]:
		var probe := aim.rotated(da) * (RING_BLAST_R - 25.0)
		if bool(covered_ring.call(probe)) \
				and probe.distance_to(aim * RING_BLAST_R) < RING_RADIUS - 20.0:
			deep_carved = false
	# Far side of the ring -> intact.
	var far_kept := bool(covered_ring.call(-aim * RING_BLAST_R))
	# Outer and inner crater edges along the aim ray hug the circle:
	# the largest carved radius near the outer rim and the smallest carved
	# radius near the inner rim must sit within EDGE_TOLERANCE of the true
	# circle crossings (RING_BLAST_R ± RING_RADIUS on this ray).
	var r_out := RING_BLAST_R + RING_RADIUS
	var r_in := RING_BLAST_R - RING_RADIUS
	var outer_edge := -1.0
	var r := r_out - 30.0
	while r <= r_out + 30.0:
		if not bool(covered_ring.call(aim * r)):
			outer_edge = r
		r += 1.0
	var inner_edge := -1.0
	r = r_in - 30.0
	while r <= r_in + 30.0:
		if not bool(covered_ring.call(aim * r)):
			inner_edge = r
			break
		r += 1.0
	var edge_dev := 999.0
	if outer_edge >= 0.0 and inner_edge >= 0.0:
		edge_dev = maxf(absf(outer_edge - r_out), absf(inner_edge - r_in))
	var ring_split := ring_pieces.size() > 24
	var ring_ok := deep_carved and far_kept \
			and edge_dev <= EDGE_TOLERANCE and ring_split
	print("ISSUE299 ring pieces=", ring_pieces.size(), " deep_carved=",
		deep_carved, " far_kept=", far_kept, " edge_dev=", edge_dev,
		" edge_within=", edge_dev <= EDGE_TOLERANCE)
	ok = ok and ring_ok

	print("ISSUE299 ok=", ok)
	get_tree().quit(0 if ok else 1)
