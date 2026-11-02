class_name DestructibleGround
extends StaticBody2D
## Issue #190: destructible terrain.
##
## Characters can stand on it, but it is NOT a gravity source — only
## indestructible ground bends gravity. An explosion (Projectile._explode)
## calls `apply_blast` and the rect chunk is subtracted with the blast's
## circle bounding box; the leftover strips spawn as new chunks, so craters
## grow chunk by chunk. Visual is drawn in code — no assets.
##
## Issue #250: annular-sector chunks. A node authored with `ring_outer > 0`
## and `arc_span <= 0` marks a WHOLE RING (an external dirt layer around a
## circular indestructible core): `_ready` turns it into the shapeless
## CONTAINER of RING_SECTORS equal sector chunks (children — the parent
## level is still setting up, so siblings cannot be added yet). Blasts split
## a sector into angular/radial halves exactly like the rect strips; halves
## that ended up fully inside the blast box are not respawned, so craters
## grow chunk by chunk here too. All chunks share the container's origin
## (the arena centre), so their local sector coordinates always line up.

const COLOR := Color(0.45, 0.32, 0.2, 1)
## Strips thinner than this are discarded (avoids sub-pixel slivers).
const MIN_PIECE := 8.0
## Issue #250: sectors of a whole-ring authoring node, and the smallest
## arc span / radial band a blast may still split into halves.
const RING_SECTORS := 24
const MIN_ARC_SPAN := 0.05
const MIN_BAND := 24.0

@export var rect_size := Vector2(200, 60)

## Issue #250: annular-sector mode — the chunk is the band between
## `ring_inner` and `ring_outer` over `arc_span` radians centred on
## `arc_center`, in this node's local space (the node sits at the arena
## centre). `ring_outer == 0` keeps the legacy rectangle of `rect_size`.
@export var ring_inner := 0.0
@export var ring_outer := 0.0
@export var arc_center := 0.0
@export var arc_span := 0.0


func _ready() -> void:
	collision_layer = 1
	if ring_outer > 0.0 and arc_span <= 0.0:
		# Whole-ring authoring node: build the sector chunks as children and
		# stay as their (shapeless, group-less) container.
		var span := TAU / float(RING_SECTORS)
		for i in RING_SECTORS:
			add_child(_make_sector(ring_inner, ring_outer,
					-PI / 2.0 + (float(i) + 0.5) * span, span))
		return
	add_to_group("destructible_ground")
	if ring_outer > 0.0:
		var poly := CollisionPolygon2D.new()
		poly.name = "Shape"
		poly.polygon = _sector_polygon()
		add_child(poly)
	else:
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var rect := RectangleShape2D.new()
		rect.size = rect_size
		shape.shape = rect
		add_child(shape)
	queue_redraw()


func _draw() -> void:
	if ring_outer > 0.0:
		draw_colored_polygon(_sector_polygon(), COLOR)
	else:
		draw_rect(Rect2(-rect_size / 2.0, rect_size), COLOR)


## Carve this chunk with an explosion at `global_point` (blast `radius`).
func apply_blast(global_point: Vector2, radius: float) -> void:
	if ring_outer > 0.0:
		_carve_sector(to_local(global_point), radius)
		return
	var rect := Rect2(-rect_size / 2.0, rect_size)
	var box := Rect2(global_point - global_position - Vector2(radius, radius),
			Vector2(radius, radius) * 2.0)
	var cut := rect.intersection(box)
	if cut.size.x <= 0.0 or cut.size.y <= 0.0:
		return
	# Four remainder strips: left, right (full height) and top, bottom
	# (between the cut edges).
	_spawn(Vector2(rect.position.x, rect.position.y),
			Vector2(cut.position.x - rect.position.x, rect.size.y))
	_spawn(Vector2(cut.end.x, rect.position.y),
			Vector2(rect.end.x - cut.end.x, rect.size.y))
	_spawn(Vector2(cut.position.x, rect.position.y),
			Vector2(cut.size.x, cut.position.y - rect.position.y))
	_spawn(Vector2(cut.position.x, cut.end.y),
			Vector2(cut.size.x, rect.end.y - cut.end.y))
	queue_free()


## Issue #250: carve an annular-sector chunk with a blast circle. Splits the
## sector into angular and radial halves; a half that ended up fully inside
## the blast box is not respawned, so the crater opens chunk by chunk.
func _carve_sector(point: Vector2, blast: float) -> void:
	var blast_box := Rect2(point - Vector2(blast, blast),
			Vector2(blast, blast) * 2.0)
	if not blast_box.intersects(_sector_bbox(ring_inner, ring_outer,
			arc_center, arc_span)):
		return
	var split_angular := arc_span / 2.0 >= MIN_ARC_SPAN
	var split_radial := (ring_outer - ring_inner) / 2.0 >= MIN_BAND
	if not split_angular and not split_radial:
		return  # Too small to halve — stays solid like the MIN_PIECE strips.
	queue_free()
	var half_span := arc_span / 2.0
	var mid_r := (ring_inner + ring_outer) / 2.0
	var angles: Array[float] = [arc_center]
	if split_angular:
		angles = [arc_center - half_span / 2.0, arc_center + half_span / 2.0]
	var bands: Array = [[ring_inner, ring_outer]]
	if split_radial:
		bands = [[ring_inner, mid_r], [mid_r, ring_outer]]
	for a in angles:
		var span := half_span if split_angular else arc_span
		for band in bands:
			# A half fully inside the blast box is carved away — skip it.
			if blast_box.encloses(_sector_bbox(band[0], band[1], a, span)):
				continue
			get_parent().add_child(_make_sector(band[0], band[1], a, span))


## New chunk node for a band of [inner, outer] over `span` radians centred
## on `center`, in the ring container's coordinate space. The caller adds
## it to the tree (children while building, siblings while carving).
func _make_sector(inner: float, outer: float, center: float, span: float) -> DestructibleGround:
	var piece := DestructibleGround.new()
	piece.ring_inner = inner
	piece.ring_outer = outer
	piece.arc_center = center
	piece.arc_span = span
	return piece


## Polygon of this sector: the outer arc traced start -> end, then the inner
## arc traced back (a closed band, no self intersections).
func _sector_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(2, int(ceil(arc_span / 0.2)))
	for i in steps + 1:
		var a := arc_center - arc_span / 2.0 + arc_span * float(i) / float(steps)
		points.append(Vector2(cos(a), sin(a)) * ring_outer)
	for i in steps + 1:
		var a := arc_center + arc_span / 2.0 - arc_span * float(i) / float(steps)
		points.append(Vector2(cos(a), sin(a)) * ring_inner)
	return points


## Bounding box of the band's inner and outer arcs (the blunt sector
## approximation used for blast hit/containment tests, mirroring how the
## rect chunks intersect with the blast's bounding box).
func _sector_bbox(inner: float, outer: float, center: float, span: float) -> Rect2:
	var rect := Rect2(Vector2(cos(center), sin(center)) * inner,
			Vector2.ZERO)
	for i in 5:
		var a := center - span / 2.0 + span * float(i) / 4.0
		rect = rect.expand(Vector2(cos(a), sin(a)) * inner)
		rect = rect.expand(Vector2(cos(a), sin(a)) * outer)
	if span >= PI:
		rect = rect.expand(Vector2.ZERO)
	return rect


func _spawn(offset: Vector2, size: Vector2) -> void:
	if size.x < MIN_PIECE or size.y < MIN_PIECE:
		return
	var piece := DestructibleGround.new()
	piece.rect_size = size
	piece.position = position + offset + size / 2.0
	get_parent().add_child(piece)
