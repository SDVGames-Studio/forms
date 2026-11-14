class_name LevelItems
extends Object
## Issue #364: the round drop — from the SECOND round on, ONE random
## item (first aid kit / weapon bundle / tool bundle) may appear on a
## random spot of the level each round. TurnController counts the rounds
## (one round = every team acted once through the turn order) and calls
## the spawn below; the items themselves are LevelItem bodies built in
## code.
##
## Issue #375: the creation spot is a uniformly random SURFACE point of
## the level. Every ground piece joins the draw with a weight equal to
## its walkable surface length — the flat top face of a slab or rect
## chunk, the full circle of a disc, the outer arc of a ring sector,
## destructible and indestructible alike — so every point of every
## ground type has exactly the same chance of hosting the new item. The
## item is created right ON the chosen surface (no sky drop, no more
## falling through gaps between grounds): surface gravity — vertical at
## a slab top, radial around a disc or ring — holds it there. The round
## drop itself became a 25% roll (TurnController.ROUND_DROP_CHANCE).


## Issue #375: one walkable surface of the level, open to item creation:
## a ground piece plus the length of its surface in px (the draw weight)
## and a mapper from a uniform offset [0, 1) along it to a local-space
## point + outward normal (see _surface_point).
##
## Surface kinds:
##  SLAB_TOP    — the flat top face of an indestructible slab or a
##                destructible rect chunk (surface gravity is vertical
##                there, so only the top face can host a resting item);
##  DISC_ARC    — the full circle of an indestructible disc;
##  SECTOR_ARC  — the outer arc of a destructible ring-sector chunk.
enum SurfaceKind { SLAB_TOP, DISC_ARC, SECTOR_ARC }


## Issue #375: a drawn surface is only USABLE when the item body
## would clear every ground piece — see _spot_clear (issue #403).
## Issue #403: overlapping masses are legal level authoring (issue
## #270 counts touching/overlapping masses as ONE landmass), and parts
## of a surface buried inside a neighbour used to host created items —
## they appeared inside the indestructible ground. Each drop now
## redraws until the spot is clear, at most this many tries.
const MAX_SPOT_TRIES := 12


## Issue #375: create one random item at a uniformly random SURFACE
## point of the level — every ground piece, whatever its type, gets
## exactly its surface's share of the chance. Returns the item, or null
## when the level has no measurable ground surface (menus, tests) or no
## drawn spot clears the ground (issue #403: skip the drop rather than
## bury the item).
static func spawn_random_item(level: Node) -> LevelItem:
	if level == null:
		return null
	var grounds: Array[Node2D] = []
	var total := 0.0
	for group in ["indestructible_ground", "destructible_ground"]:
		for node in level.get_tree().get_nodes_in_group(group):
			var ground := node as Node2D
			if ground == null or not is_instance_valid(ground):
				continue
			var length := _surface_length(ground)
			if length > 0.0:
				total += length
				grounds.append(ground)
	if grounds.is_empty():
		return null
	# Issue #403: draw spot after spot until one clears every ground
	# piece — the draw itself stays exactly the issue #375 uniform
	# surface lottery, only buried spots are redrawn.
	for _try in MAX_SPOT_TRIES:
		var picked: Node2D = _draw_ground(grounds, total)
		var spot := _surface_point(picked, randf())
		var xform: Transform2D = picked.global_transform
		var point: Vector2 = spot["point"]
		var normal: Vector2 = xform.basis_xform(spot["normal"]).normalized()
		# Issue #375: half the 64 px item plus a hair along the surface
		# normal — the item starts RESTING on the ground, not inside it.
		var gap := LevelItem.SIZE / 2.0 + 2.0
		var at: Vector2 = xform * point + normal * gap
		if not _spot_clear(level, at):
			continue
		var item := LevelItem.new()
		item.kind = [LevelItem.Kind.FIRST_AID,
				LevelItem.Kind.WEAPON_BUNDLE,
				LevelItem.Kind.TOOL_BUNDLE].pick_random()
		item.global_position = at
		level.add_child(item)
		DebugInfo.log("a %s appears on the field" % LevelItem.kind_name(item.kind))
		return item
	DebugInfo.log("no open spot for a new item this round")
	return null


## Issue #375: the weighted draw — a uniform roll over the total
## surface length walks the pieces; a piece gets exactly its surface's
## share.
static func _draw_ground(grounds: Array[Node2D], total: float) -> Node2D:
	var roll := randf() * total
	var picked: Node2D = grounds[grounds.size() - 1]
	for ground in grounds:
		roll -= _surface_length(ground)
		if roll <= 0.0:
			picked = ground
			break
	return picked


## Issue #403: true when the would-be item body overlaps NO ground
## piece: its centre plus four probes just inside its 64 px edges are
## point-queried against the physics space, which sees every ground
## shape — rounded slab corners, discs, ring sectors, carved chunks —
## through the collision bodies, all on layer 1.
static func _spot_clear(level: Node, at: Vector2) -> bool:
	var canvas := level as CanvasItem
	if canvas == null:
		return true
	var space := canvas.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1
	var reach := LevelItem.SIZE / 2.0 - 4.0
	var probes: Array[Vector2] = [at,
			at + Vector2(reach, 0.0), at + Vector2(-reach, 0.0),
			at + Vector2(0.0, reach), at + Vector2(0.0, -reach)]
	for probe in probes:
		query.position = probe
		if not space.intersect_point(query, 1).is_empty():
			return false
	return true


## Issue #375: the walkable surface length of one ground piece in px —
## its share of the creation draw. 0.0 for pieces without a measurable
## surface (whole-ring containers never join: their sector children
## carry the ring's surface).
static func _surface_length(ground: Node2D) -> float:
	var ring_outer = ground.get("ring_outer")
	if (ring_outer is float or ring_outer is int) and float(ring_outer) > 0.0:
		var span = ground.get("arc_span")
		if span is float or span is int:
			return float(ring_outer) * maxf(0.0, float(span))
		return 0.0
	var radius = ground.get("radius")
	if (radius is float or radius is int) and float(radius) > 0.0:
		return TAU * float(radius)
	var poly = ground.get("polygon")
	if poly is PackedVector2Array and poly.size() >= 3:
		return _up_boundary_length(poly)
	var size = ground.get("rect_size")
	if size is Vector2:
		return maxf(0.0, size.x)
	return 0.0


## Issue #375: the local-space surface point + outward normal of one
## ground piece at a uniform offset [0, 1) along its walkable surface
## (see _surface_length for the span kinds).
static func _surface_point(ground: Node2D, offset: float) -> Dictionary:
	var ring_outer = ground.get("ring_outer")
	if (ring_outer is float or ring_outer is int) and float(ring_outer) > 0.0:
		var span = ground.get("arc_span")
		var angle: float = float(ground.get("arc_center")) \
				- float(span) / 2.0 + float(span) * offset
		var radial := Vector2(cos(angle), sin(angle))
		return {"point": radial * float(ring_outer), "normal": radial}
	var radius = ground.get("radius")
	if (radius is float or radius is int) and float(radius) > 0.0:
		var angle := offset * TAU
		var radial := Vector2(cos(angle), sin(angle))
		return {"point": radial * float(radius), "normal": radial}
	var poly = ground.get("polygon")
	if poly is PackedVector2Array and poly.size() >= 3:
		return _up_boundary_point(poly, offset)
	var size = ground.get("rect_size")
	var width: float = size.x
	return {"point": Vector2((offset - 0.5) * width, -float(size.y) / 2.0),
			"normal": Vector2.UP}


## Issue #376: the outward normal of one polygon edge — the perpendicular
## pointing away from the polygon's centroid (convex chunks only).
static func _edge_normal(a: Vector2, b: Vector2,
		centroid: Vector2) -> Vector2:
	var edge := b - a
	var normal := Vector2(-edge.y, edge.x).normalized()
	var mid := (a + b) / 2.0
	if (mid + normal * 4.0).distance_to(centroid) \
				< (mid - normal * 4.0).distance_to(centroid):
		normal = -normal
	return normal


## Issue #376: the total length of a polygon chunk's UPWARD-facing
## boundary — the edges whose outward normal points at least somewhat
## up. The walkable surface of a trapezoid / triangle / half-disc hill
## is exactly that boundary (the flat base is not a surface).
static func _up_boundary_length(pts: PackedVector2Array) -> float:
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= float(pts.size())
	var total := 0.0
	for i in pts.size():
		var b := pts[(i + 1) % pts.size()]
		if _edge_normal(pts[i], b, centroid).y < -0.1:
			total += pts[i].distance_to(b)
	return total


## Issue #376: the point + outward normal at a uniform offset [0, 1)
## along the polygon chunk's upward-facing boundary.
static func _up_boundary_point(pts: PackedVector2Array,
		offset: float) -> Dictionary:
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= float(pts.size())
	var walk := offset * _up_boundary_length(pts)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var normal := _edge_normal(a, b, centroid)
		if normal.y >= -0.1:
			continue
		var edge_len := a.distance_to(b)
		if walk > edge_len:
			walk -= edge_len
			continue
		var t := walk / edge_len if edge_len > 0.0 else 0.0
		return {"point": a + (b - a) * t, "normal": normal}
	return {"point": pts[0], "normal": Vector2.UP}
