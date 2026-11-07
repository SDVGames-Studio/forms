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


## Issue #375: create one random item at a uniformly random SURFACE
## point of the level — every ground piece, whatever its type, gets
## exactly its surface's share of the chance. Returns the item, or null
## when the level has no measurable ground surface (menus, tests).
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
	# The weighted draw: a uniform roll over the total surface length
	# walks the pieces; a piece gets exactly its surface's share.
	var roll := randf() * total
	var picked: Node2D = grounds[grounds.size() - 1]
	for ground in grounds:
		roll -= _surface_length(ground)
		if roll <= 0.0:
			picked = ground
			break
	var spot := _surface_point(picked, randf())
	var xform: Transform2D = picked.global_transform
	var point: Vector2 = spot["point"]
	var normal: Vector2 = xform.basis_xform(spot["normal"]).normalized()
	# Issue #375: half the 64 px item plus a hair along the surface
	# normal — the item starts RESTING on the ground, not inside it.
	var gap := LevelItem.SIZE / 2.0 + 2.0
	var item := LevelItem.new()
	item.kind = [LevelItem.Kind.FIRST_AID,
			LevelItem.Kind.WEAPON_BUNDLE,
			LevelItem.Kind.TOOL_BUNDLE].pick_random()
	item.global_position = xform * point + normal * gap
	level.add_child(item)
	DebugInfo.log("a %s appears on the field" % LevelItem.kind_name(item.kind))
	return item


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
	var size = ground.get("rect_size")
	var width: float = size.x
	return {"point": Vector2((offset - 0.5) * width, -float(size.y) / 2.0),
			"normal": Vector2.UP}
