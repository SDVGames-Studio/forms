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
## level is still setting up, so siblings cannot be added yet). All chunks
## share the container's origin (the arena centre), so their local sector
## coordinates always line up.
##
## Issue #250 rework: blasts carve the ring with the actual blast CIRCLE
## (not its bounding box). The blast is expressed in the arena's polar
## space — its radial reach [d - r, d + r] and the angular span it
## subtends from the centre — and each piece is decided against that:
## disjoint pieces survive untouched, a piece whose border points all sit
## inside the circle is carved away, and everything in between is halved
## (angularly/radially) until it is small enough to decide by its centre.
## Craters therefore actually OPEN chunk by chunk — the first delivery
## only ever split chunks smaller (a half never fitted inside the blast
## BOX), so the ring stayed solid.

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


## Issue #250 rework: carve an annular-sector chunk with a blast CIRCLE.
## Pieces disjoint from the blast's polar region survive untouched, fully
## covered pieces are carved away, and partial ones are halved until they
## are small enough to decide by their centre — craters open chunk by chunk.
func _carve_sector(point: Vector2, blast: float) -> void:
	var d := maxf(point.length(), 1.0)
	_blast_point = point
	_blast_radius = blast
	_blast_lo = maxf(0.0, d - blast)
	_blast_hi = d + blast
	_blast_aim = point.angle()
	# A blast swallowing the centre axis reaches every angle equally.
	_blast_half = PI if d <= blast else asin(clampf(blast / d, 0.0, 1.0))
	if _polar_disjoint(ring_inner, ring_outer, arc_center, arc_span):
		return
	queue_free()
	_split_or_keep(get_parent(), ring_inner, ring_outer, arc_center, arc_span)


## Blast context while carving this chunk (polar, in the container's space).
var _blast_point := Vector2.ZERO
var _blast_radius := 0.0
var _blast_lo := 0.0
var _blast_hi := 0.0
var _blast_aim := 0.0
var _blast_half := 0.0


## True when the piece's band/arc cannot touch the blast's polar region.
func _polar_disjoint(inner: float, outer: float, center: float, span: float) -> bool:
	if outer <= _blast_lo or inner >= _blast_hi:
		return true
	var ad := absf(wrapf(center - _blast_aim, -PI, PI))
	return ad >= _blast_half + span / 2.0


## True when the whole piece sits inside the blast circle: its polar band
## and arc are contained AND every border probe (corners + outer mid-arc)
## is within the blast radius.
func _blast_covers(inner: float, outer: float, center: float, span: float) -> bool:
	if inner < _blast_lo or outer > _blast_hi:
		return false
	var ad := absf(wrapf(center - _blast_aim, -PI, PI))
	if ad + span / 2.0 > _blast_half:
		return false
	var lo := center - span / 2.0
	var hi := center + span / 2.0
	var probes: Array = [Vector2(cos(lo), sin(lo)) * inner,
			Vector2(cos(hi), sin(hi)) * inner,
			Vector2(cos(lo), sin(lo)) * outer,
			Vector2(cos(hi), sin(hi)) * outer,
			Vector2(cos(center), sin(center)) * outer]
	for probe in probes:
		if probe.distance_to(_blast_point) > _blast_radius:
			return false
	return true


## Recursive half-splitting: keep disjoint pieces, drop covered ones, halve
## the rest (angular and/or radial); a piece too small to halve is dropped
## when the blast circle swallows its centre, kept otherwise — mirroring how
## the rect strips keep slivers the blast box only grazes.
func _split_or_keep(parent: Node, inner: float, outer: float,
		center: float, span: float) -> void:
	if _polar_disjoint(inner, outer, center, span):
		parent.add_child(_make_sector(inner, outer, center, span))
		return
	if _blast_covers(inner, outer, center, span):
		return
	var half_span := span / 2.0
	var split_angular := half_span >= MIN_ARC_SPAN
	var split_radial := (outer - inner) / 2.0 >= MIN_BAND
	if split_angular or split_radial:
		var angles: Array[float] = [center]
		if split_angular:
			angles = [center - half_span / 2.0, center + half_span / 2.0]
		var mid_r := (inner + outer) / 2.0
		var bands: Array = [[inner, outer]]
		if split_radial:
			bands = [[inner, mid_r], [mid_r, outer]]
		for a in angles:
			var s := half_span if split_angular else span
			for band in bands:
				_split_or_keep(parent, band[0], band[1], a, s)
		return
	var mid := Vector2(cos(center), sin(center)) * ((inner + outer) / 2.0)
	if mid.distance_to(_blast_point) > _blast_radius:
		parent.add_child(_make_sector(inner, outer, center, span))


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


func _spawn(offset: Vector2, size: Vector2) -> void:
	if size.x < MIN_PIECE or size.y < MIN_PIECE:
		return
	var piece := DestructibleGround.new()
	piece.rect_size = size
	piece.position = position + offset + size / 2.0
	get_parent().add_child(piece)
