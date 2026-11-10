extends Node
## Regression check for issue #376 — more destructible ground:
##  - every campaign level except the fifth (Level..Level4) has a
##    destructible LAYER resting on an indestructible slab's top face,
##    3–8 character widths (192–512 px) tall;
##  - every campaign level except the fifth has at least two shaped
##    destructible hills (convex polygon chunks: trapezoid / triangle /
##    half-disc), each 4–10 character widths (256–640 px) tall;
##  - the fifth level (Level5) keeps exactly its whole ring — no layer
##    and no polygon hills were added there;
##  - no character spawns buried inside the new ground (authored
##    positions sit on top of it, not in it);
##  - polygon chunks carve with the blast circle like the other kinds:
##    a distant blast leaves the chunk whole, a blast inside frees it
##    into pieces that each keep at least one vertex outside the blast
##    circle (covered material is gone, untouched material survives).
##
## Run headless: godot --headless res://tests/test_issue376.tscn
## Exit code 0 = pass.

const LEVEL_SCENES := [
	preload("res://Level.tscn"),
	preload("res://Level2.tscn"),
	preload("res://Level3.tscn"),
	preload("res://Level4.tscn"),
]
const CHAR := 64.0
const MARGIN := 8.0

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE376 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	# 1) The four campaign levels before the fifth.
	for i in LEVEL_SCENES.size():
		var level: Node = LEVEL_SCENES[i].instantiate()
		add_child(level)
		var label := str(level.name)
		_check("%s: a 3–8 char tall destructible layer rests on the "
				% label + "indestructible ground", _has_layer(level))
		_check("%s: at least two shaped hills 4–10 char tall" % label,
				_shaped_hills(level) >= 2)
		_check("%s: no character spawns buried in the ground" % label,
				not _buried_spawn(level))
		level.queue_free()
		await get_tree().physics_frame

	# 2) The fifth level stays as it was: its only destructible ground
	# is the whole ring around the core (24 sector chunks, no polygons,
	# no layer).
	var fifth: Node = load("res://Level5.tscn").instantiate()
	add_child(fifth)
	await get_tree().physics_frame
	var stray := 0
	for node in get_tree().get_nodes_in_group("destructible_ground"):
		var chunk := node as DestructibleGround
		if chunk == null:
			continue
		if chunk.polygon.size() >= 3 or (chunk.ring_outer <= 0.0
				and chunk.rect_size.y >= 3.0 * CHAR):
			stray += 1
	_check("Level5 keeps only its ring (no layer, no polygon hills)",
			stray == 0)
	fifth.queue_free()
	await get_tree().physics_frame

	# 3) Polygon chunks carve like the other kinds.
	await _carve_checks()

	if _fails.is_empty():
		print("ISSUE376 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE376 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)


## A destructible rect chunk 3–8 char widths tall whose bottom face sits
## (within 1 px) on an indestructible slab's authored top face.
func _has_layer(level: Node) -> bool:
	var slab_tops: Array = []
	for node in get_tree().get_nodes_in_group("indestructible_ground"):
		var slab := node as IndestructibleGround
		if slab != null and slab.radius <= 0.0 and level.is_ancestor_of(slab):
			slab_tops.append(slab.global_position.y - slab.rect_size.y / 2.0)
	for node in get_tree().get_nodes_in_group("destructible_ground"):
		var chunk := node as DestructibleGround
		if chunk == null or chunk.ring_outer > 0.0 or chunk.polygon.size() >= 3:
			continue
		if not level.is_ancestor_of(chunk):
			continue
		var height := chunk.rect_size.y
		if height < 3.0 * CHAR or height > 8.0 * CHAR:
			continue
		var bottom := chunk.global_position.y + height / 2.0
		for top in slab_tops:
			if absf(bottom - float(top)) <= 1.0:
				return true
	return false


## Polygon hills 4–10 char widths tall, authored with their base edge
## at local y = 0 (they sit on whatever is below them).
func _shaped_hills(level: Node) -> int:
	var hills := 0
	for node in level.get_tree().get_nodes_in_group("destructible_ground"):
		var chunk := node as DestructibleGround
		if chunk == null or chunk.ring_outer > 0.0:
			continue
		var pts: PackedVector2Array = chunk.polygon
		if pts.size() < 3:
			continue
		var min_y := pts[0].y
		var max_y := pts[0].y
		for p in pts:
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
		if max_y == 0.0 and max_y - min_y >= 4.0 * CHAR \
				and max_y - min_y <= 10.0 * CHAR:
			hills += 1
	return hills


## True when some player/enemy character's authored position is buried
## deeper than MARGIN inside ground (rect bounds, polygon chunks, discs).
func _buried_spawn(level: Node) -> bool:
	var grounds: Array = []
	for group in ["indestructible_ground", "destructible_ground"]:
		for node in get_tree().get_nodes_in_group(group):
			if level.is_ancestor_of(node):
				grounds.append(node)
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or not level.is_ancestor_of(body):
				continue
			var pos := body.global_position
			for ground in grounds:
				var g := ground as Node2D
				if g == null:
					continue
				if _deeply_inside(pos, g):
					return true
	return false


## Point-in-ground test with a MARGIN: only a point buried deeper than
## MARGIN counts as inside.
func _deeply_inside(pos: Vector2, ground: Node2D) -> bool:
	var local := ground.to_local(pos)
	var radius = ground.get("radius")
	if (radius is float or radius is int) and float(radius) > 0.0:
		return local.length() < float(radius) - MARGIN
	var poly = ground.get("polygon")
	if poly is PackedVector2Array and poly.size() >= 3:
		var best := 1e9
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			var edge := (b - a).normalized()
			var inward := Vector2(edge.y, -edge.x)
			var centroid := Vector2.ZERO
			for p in poly:
				centroid += p
			centroid /= float(poly.size())
			if (a + inward).distance_to(centroid) < (a - inward).distance_to(centroid):
				inward = -inward
			best = minf(best, (local - a).dot(inward))
		return best > MARGIN
	var size = ground.get("rect_size")
	if size is Vector2:
		var rect := Rect2(-size / 2.0, size).grow(-MARGIN)
		return rect.has_point(local)
	return false


## Carve checks on synthetic polygon chunks (same shapes as the hills).
func _carve_checks() -> void:
	var arena := Node2D.new()
	add_child(arena)

	# Distant blast: the hill must survive untouched.
	var dome := DestructibleGround.new()
	dome.polygon = _dome_points(256.0)
	arena.add_child(dome)
	dome.apply_blast(Vector2(5000.0, 0.0), 60.0)
	_check("a distant blast leaves a polygon hill untouched",
			not dome.is_queued_for_deletion() and dome.polygon.size() >= 3)
	dome.queue_free()

	# Trapezoid + dome carved by a blast right inside: the chunk dies and
	# every surviving piece keeps material OUTSIDE the blast circle.
	for shape in [
		PackedVector2Array([Vector2(-180, 0), Vector2(180, 0),
				Vector2(130, -256), Vector2(-130, -256)]),
		_dome_points(256.0),
	]:
		var hill := DestructibleGround.new()
		hill.polygon = shape
		arena.add_child(hill)
		var blast := Vector2(20.0, -90.0)
		hill.apply_blast(blast, 80.0)
		await get_tree().physics_frame
		var pieces := 0
		var bad := 0
		for child in arena.get_children():
			var piece := child as DestructibleGround
			if piece == null or piece.is_queued_for_deletion():
				continue
			pieces += 1
			var outside := false
			for p in piece.polygon:
				if p.distance_to(blast) > 80.0:
					outside = true
					break
			if not outside:
				bad += 1
		_check("a blast inside carves the polygon hill into surviving "
				+ "pieces (pieces=%d)" % pieces, pieces >= 2 and bad == 0)
		for child in arena.get_children():
			child.queue_free()
		await get_tree().physics_frame
	arena.queue_free()


## A half-disc polygon (base on y = 0, dome above it), 24 arc steps.
func _dome_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 24
	for k in steps + 1:
		var a := PI - PI * float(k) / float(steps)
		pts.append(Vector2(round(cos(a) * radius), round(-sin(a) * radius)))
	return pts
