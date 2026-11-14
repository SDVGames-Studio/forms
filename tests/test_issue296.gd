extends Node
## Regression check for issue #296 (destructible ground overlapping
## indestructible ground): in EVERY level, no destructible chunk may
## PENETRATE an indestructible mass. Touching is fine — a soil strip
## lying on a slab's top face, the Level 5 dirt ring hugging its core
## disc — but any real overlap fails. Level 1 authored its soil strip
## straight through the hill disc; this catches that class of bug in
## any level, using the shapes built at runtime (rounded-rect slabs,
## rect chunks, ring sectors).
##
## Run headless: godot --headless res://tests/test_issue296.tscn
## Exit code 0 = pass.

const LEVELS := [
	preload("res://scenes/levels/Level.tscn"),
	preload("res://scenes/levels/Level2.tscn"),
	preload("res://scenes/levels/Level3.tscn"),
	preload("res://scenes/levels/Level4.tscn"),
	preload("res://scenes/levels/Level5.tscn"),
	preload("res://scenes/levels/LevelDuel.tscn"),
]
## Touching (gap 0) is allowed; only penetration beyond EPS fails.
const EPS := 0.5


func _ready() -> void:
	var ok := true
	for level_res in LEVELS:
		var level: Node = level_res.instantiate()
		add_child(level)
		# Let _ready settle (the Level 5 ring spawns its sector chunks).
		await get_tree().physics_frame
		await get_tree().physics_frame
		ok = _check_level(level) and ok
		level.queue_free()
		await get_tree().physics_frame
	print("ISSUE296 ok=", ok)
	get_tree().quit(0 if ok else 1)


func _check_level(level: Node) -> bool:
	var lvl_name := String(level.name)
	var ok := true
	var destr: Array = get_tree().get_nodes_in_group("destructible_ground")
	var indestr: Array = get_tree().get_nodes_in_group("indestructible_ground")
	print("ISSUE296 ", lvl_name, " destructible=", destr.size(),
		" indestructible=", indestr.size())
	for d in destr:
		var sd := _shape_of(d)
		for i in indestr:
			var si := _shape_of(i)
			if sd.is_empty() or si.is_empty():
				continue
			if _overlap(sd, si):
				print("ISSUE296 ", lvl_name, " OVERLAP ",
					String(d.name), " x ", String(i.name))
				ok = false
	return ok


## Collision geometry of one ground body in world space (levels are
## unrotated, so positions add up directly): a circle, an annular-sector
## band — ring chunks keep their exact polar authoring, because the
## built polygon's inner arc is only a coarse approximation — or a
## polygon (rect chunks / rounded-rect slabs). Empty when shapeless.
func _shape_of(body: Node2D) -> Dictionary:
	if _num(body, "ring_outer") > 0.0 and _num(body, "arc_span") > 0.0:
		return {"kind": "sector", "origin": body.global_position,
			"inner": float(body.get("ring_inner")),
			"outer": float(body.get("ring_outer")),
			"center": _num(body, "arc_center"),
			"span": _num(body, "arc_span")}
	var shape_node: Node2D = body.get_node_or_null("Shape")
	if shape_node == null:
		return {}
	var cs := shape_node as CollisionShape2D
	if cs != null and cs.shape != null:
		var circle := cs.shape as CircleShape2D
		var rect := cs.shape as RectangleShape2D
		var origin: Vector2 = body.global_position + shape_node.position
		if circle != null:
			return {"kind": "circle", "c": origin, "r": circle.radius}
		if rect != null:
			var h := rect.size / 2.0
			return {"kind": "poly", "pts": PackedVector2Array([
				origin + Vector2(-h.x, -h.y), origin + Vector2(h.x, -h.y),
				origin + Vector2(h.x, h.y), origin + Vector2(-h.x, h.y)])}
	var cp := shape_node as CollisionPolygon2D
	if cp != null and cp.polygon.size() >= 3:
		var pts := PackedVector2Array()
		for p in cp.polygon:
			pts.append(body.global_position + cp.position + p)
		return {"kind": "poly", "pts": pts}
	return {}


## 0.0 for a property the node does not have (null-safe).
func _num(body: Node2D, prop: String) -> float:
	var v = body.get(prop)
	return 0.0 if v == null else float(v)


func _overlap(a: Dictionary, b: Dictionary) -> bool:
	if a["kind"] == "sector" and b["kind"] == "circle":
		return _sector_circle_overlap(a, b)
	if b["kind"] == "sector" and a["kind"] == "circle":
		return _sector_circle_overlap(b, a)
	if a["kind"] == "circle" and b["kind"] == "circle":
		return (a["c"] as Vector2).distance_to(b["c"]) \
				< a["r"] + b["r"] - EPS
	if a["kind"] == "circle":
		return _circle_poly_overlap(a["c"], a["r"], b["pts"])
	if b["kind"] == "circle":
		return _circle_poly_overlap(b["c"], b["r"], a["pts"])
	return _poly_poly_overlap(a["pts"], b["pts"])


## Exact polar test for a ring chunk vs a disc: the circle's radial
## reach versus the band first, then its angular reach. Touching (the
## ring hugging its core disc) is allowed.
func _sector_circle_overlap(s: Dictionary, c: Dictionary) -> bool:
	var offset: Vector2 = c["c"] - s["origin"]
	var d := maxf(offset.length(), 0.0001)
	var r: float = c["r"]
	if d + r <= float(s["inner"]) + EPS or d - r >= float(s["outer"]) - EPS:
		return false
	if d <= r:
		return true  # the circle swallows the band's centre axis
	var half := asin(clampf(r / d, 0.0, 1.0))
	var ad := absf(wrapf(offset.angle() - float(s["center"]), -PI, PI))
	return ad < half + float(s["span"]) / 2.0 - EPS


func _circle_poly_overlap(c: Vector2, r: float, pts: PackedVector2Array) -> bool:
	if _point_in_poly(c, pts) \
			and _closest_on_poly(pts, c).distance_to(c) > EPS:
		return true
	return _closest_on_poly(pts, c).distance_to(c) < r - EPS


## Convex-polygon overlap: containment (a vertex inside the other shape)
## plus a separating-axis pass with an EPS allowance, so shapes that
## merely touch along an edge (soil bottom on a slab top) stay separate.
func _poly_poly_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for p in a:
		if _point_in_poly(p, b) \
				and _closest_on_poly(b, p).distance_to(p) > EPS:
			return true
	for p in b:
		if _point_in_poly(p, a) \
				and _closest_on_poly(a, p).distance_to(p) > EPS:
			return true
	for poly in [a, b]:
		for i in poly.size():
			var p0: Vector2 = poly[i]
			var p1: Vector2 = poly[(i + 1) % poly.size()]
			var edge := p1 - p0
			if edge.length_squared() < 0.0001:
				continue
			var axis := Vector2(-edge.y, edge.x).normalized()
			var min_a := INF
			var max_a := -INF
			var min_b := INF
			var max_b := -INF
			for q in a:
				var t := q.dot(axis)
				min_a = minf(min_a, t)
				max_a = maxf(max_a, t)
			for q in b:
				var t2 := q.dot(axis)
				min_b = minf(min_b, t2)
				max_b = maxf(max_b, t2)
			if max_a <= min_b + EPS or max_b <= min_a + EPS:
				return false
	return true


func _point_in_poly(p: Vector2, pts: PackedVector2Array) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		if (pts[i].y > p.y) != (pts[j].y > p.y):
			var x_int := pts[i].x + (p.y - pts[i].y) \
					* (pts[j].x - pts[i].x) / (pts[j].y - pts[i].y)
			if p.x < x_int:
				inside = not inside
		j = i
	return inside


func _closest_on_poly(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var best := pts[0]
	var best_d := p.distance_squared_to(pts[0])
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var ab := b - a
		var t := 0.5
		if ab.length_squared() > 0.0001:
			t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best
