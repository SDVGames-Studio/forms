class_name DestructibleGround
extends StaticBody2D
## Issue #190: destructible terrain.
##
## Characters can stand on it, but it is NOT a gravity source — only
## indestructible ground bends gravity. An explosion (Projectile._explode)
## calls `apply_blast` and the chunk is carved with the actual blast
## CIRCLE; the leftover pieces spawn as new chunks, so craters grow chunk
## by chunk. Visual is drawn in code — no assets.
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
##
## Issue #376: convex POLYGON chunks (a non-empty `polygon`) — the
## trapezoid / triangle / half-disc destructible hills. They carve with
## the blast circle exactly like the other kinds: disjoint pieces
## survive, covered pieces vanish and partial ones are halved along
## their longer axis (convex clipping — the halves stay convex) until
## small enough to decide by their centre.

const COLOR := Color(0.45, 0.32, 0.2, 1)
## Strips thinner than this are discarded (avoids sub-pixel slivers).
## Issue #299: 2 px (was 8) so rect crater edges staircase at 2 px.
const MIN_PIECE := 2.0
## Issue #250: sectors of a whole-ring authoring node, and the smallest
## arc span / radial band a blast may still split into halves.
## Issue #299: 0.005 rad ≈ 3–6 px tangential (was 0.05) and 4 px bands
## (was 24) so ring crater edges read as smooth curves, not chunk steps.
const RING_SECTORS := 24
const MIN_ARC_SPAN := 0.005
const MIN_BAND := 4.0

@export var rect_size := Vector2(200, 60)

## Issue #376: convex polygon mode — the chunk is this authored polygon
## in local space (trapezoid, triangle, half-disc hills; base edge at
## y = 0). An empty array keeps the rectangle of `rect_size`.
@export var polygon: PackedVector2Array

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
	elif polygon.size() >= 3:
		var poly := CollisionPolygon2D.new()
		poly.name = "Shape"
		poly.polygon = polygon
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
	elif polygon.size() >= 3:
		draw_colored_polygon(polygon, COLOR)
	else:
		draw_rect(Rect2(-rect_size / 2.0, rect_size), COLOR)


## Issue #376: local-space bounds of the authored chunk — the rect for
## rectangle chunks, the polygon's AABB for polygon chunks. Consumers
## that must avoid the soil (e.g. ProjectileBody's rock exclusion)
## use this instead of assuming `rect_size`.
func local_bounds() -> Rect2:
	if polygon.size() >= 3:
		var aabb := Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			aabb = aabb.expand(p)
		return aabb
	return Rect2(-rect_size / 2.0, rect_size)


## Carve this chunk with an explosion at `global_point` (blast `radius`).
func apply_blast(global_point: Vector2, radius: float) -> void:
	if ring_outer > 0.0:
		_carve_sector(to_local(global_point), radius)
		return
	if polygon.size() >= 3:
		_carve_polygon(to_local(global_point), radius)
		return
	_carve_rect(to_local(global_point), radius)


## Issue #376: carve a convex polygon chunk with the blast CIRCLE —
## the polygon twin of `_carve_rect`: untouched chunks stay whole,
## everything else is halved along its longer axis (convex clipping)
## until each piece is disjoint, covered or small enough to decide by
## its centre.
func _carve_polygon(point: Vector2, blast: float) -> void:
	_blast_point = point
	_blast_radius = blast
	if _poly_disjoint(polygon):
		return
	queue_free()
	_split_or_keep_poly(get_parent(), polygon)


## True when the blast circle cannot touch the convex polygon — the
## closest point of its BOUNDARY is farther than the blast radius and
## the blast centre is not inside (a blast inside is never disjoint).
func _poly_disjoint(pts: PackedVector2Array) -> bool:
	if _poly_contains(_blast_point, pts):
		return false
	return LevelTerrain._closest_on_polygon(pts, _blast_point).distance_to(
			_blast_point) > _blast_radius


## True when the point sits inside (or on) the convex polygon — the
## edge cross products all keep one sign, whatever the winding.
func _poly_contains(p: Vector2, pts: PackedVector2Array) -> bool:
	var side := 0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var cross := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		if cross < 0.0:
			if side > 0:
				return false
			side = -1
		elif cross > 0.0:
			if side < 0:
				return false
			side = 1
	return true


## True when every polygon vertex sits inside the blast circle.
func _poly_covered(pts: PackedVector2Array) -> bool:
	for p in pts:
		if p.distance_to(_blast_point) > _blast_radius:
			return false
	return true


## Recursive halving for polygon pieces: keep disjoint ones, drop
## covered ones, halve the rest along the LONGER axis through the
## vertex mean (convex clip — both halves stay convex); a piece too
## small to halve is dropped when the blast circle swallows its
## centre, kept otherwise — mirroring `_split_or_keep_rect`.
func _split_or_keep_poly(parent: Node, pts: PackedVector2Array) -> void:
	if _poly_disjoint(pts):
		parent.add_child(_spawn_poly(pts))
		return
	if _poly_covered(pts):
		return
	var aabb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		aabb = aabb.expand(p)
	var axis := 0 if aabb.size.x >= aabb.size.y else 1
	if aabb.size[axis] < 2.0 * MIN_PIECE:
		var centroid := Vector2.ZERO
		for p in pts:
			centroid += p
		centroid /= float(pts.size())
		if centroid.distance_to(_blast_point) > _blast_radius:
			parent.add_child(_spawn_poly(pts))
		return
	var split := 0.0
	for p in pts:
		split += p[axis]
	split /= float(pts.size())
	var lo := _clip_half(pts, axis, split, false)
	var hi := _clip_half(pts, axis, split, true)
	if lo.size() >= 3:
		_split_or_keep_poly(parent, lo)
	if hi.size() >= 3:
		_split_or_keep_poly(parent, hi)


## Convex clip of `pts` against an axis-aligned half-plane: keep the
## side where p[axis] >= t (`keep_ge`) or <= t — Sutherland–Hodgman for
## a single clip edge, so both halves are closed convex polygons.
func _clip_half(pts: PackedVector2Array, axis: int, t: float,
		keep_ge: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var cur := pts[i]
		var nxt := pts[(i + 1) % n]
		var cur_in := (cur[axis] >= t) if keep_ge else (cur[axis] <= t)
		var nxt_in := (nxt[axis] >= t) if keep_ge else (nxt[axis] <= t)
		if cur_in:
			out.append(cur)
		if cur_in != nxt_in:
			var f := (t - cur[axis]) / (nxt[axis] - cur[axis])
			out.append(cur + (nxt - cur) * f)
	return out


## New chunk node for a surviving polygon piece. The piece lives in the
## carved node's local space, so it spawns at the same position.
func _spawn_poly(pts: PackedVector2Array) -> DestructibleGround:
	var piece := DestructibleGround.new()
	piece.polygon = pts
	piece.position = position
	return piece


## Issue #299: carve a rectangle chunk with the blast CIRCLE, not its
## axis-aligned bounding box. Same recursion as the ring carver: pieces
## disjoint from the circle survive untouched, fully covered pieces are
## carved away, and the rest are halved (in x and/or y) until small enough
## to decide by their centre — so a crater follows the round blast instead
## of punching a square notch through the ground.
func _carve_rect(point: Vector2, blast: float) -> void:
	_blast_point = point
	_blast_radius = blast
	var rect := Rect2(-rect_size / 2.0, rect_size)
	if _circle_rect_disjoint(rect):
		return
	queue_free()
	_split_or_keep_rect(get_parent(), rect)


## True when the blast circle cannot touch the rect at all — closest-point
## distance from the blast centre to the rect exceeds the blast radius.
func _circle_rect_disjoint(rect: Rect2) -> bool:
	var nearest := Vector2(
			clampf(_blast_point.x, rect.position.x, rect.end.x),
			clampf(_blast_point.y, rect.position.y, rect.end.y))
	return nearest.distance_to(_blast_point) > _blast_radius


## True when all four rect corners sit inside the blast circle.
func _circle_rect_covers(rect: Rect2) -> bool:
	var corners: Array = [rect.position, rect.end,
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.position.y)]
	for corner in corners:
		if corner.distance_to(_blast_point) > _blast_radius:
			return false
	return true


## Recursive halving for rect pieces: keep disjoint ones, drop covered ones,
## halve the rest (in x and/or y while both halves still clear MIN_PIECE);
## a piece too small to halve is dropped when the blast circle swallows its
## centre, kept otherwise — mirroring `_split_or_keep` for ring sectors.
func _split_or_keep_rect(parent: Node, rect: Rect2) -> void:
	if _circle_rect_disjoint(rect):
		_spawn(rect.position, rect.size)
		return
	if _circle_rect_covers(rect):
		return
	var split_x := rect.size.x / 2.0 >= MIN_PIECE
	var split_y := rect.size.y / 2.0 >= MIN_PIECE
	if split_x or split_y:
		var mid := rect.get_center()
		var xs: Array = [rect.position.x]
		var ws: Array = [rect.size.x]
		if split_x:
			xs = [rect.position.x, mid.x]
			ws = [rect.size.x / 2.0, rect.size.x / 2.0]
		var ys: Array = [rect.position.y]
		var hs: Array = [rect.size.y]
		if split_y:
			ys = [rect.position.y, mid.y]
			hs = [rect.size.y / 2.0, rect.size.y / 2.0]
		for i in xs.size():
			for j in ys.size():
				_split_or_keep_rect(parent, Rect2(
						Vector2(xs[i], ys[j]), Vector2(ws[i], hs[j])))
		return
	if rect.get_center().distance_to(_blast_point) > _blast_radius:
		_spawn(rect.position, rect.size)


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
## Issue #299: arcs are traced finely enough that the chord between sample
## points bows less than half a pixel — the old 0.2 rad sampling left
## wedge seams between adjacent sectors at large radii.
func _sector_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	var sample := 0.2
	if ring_outer > 1.0:
		sample = 2.0 * acos(clampf(1.0 - 0.5 / ring_outer, -1.0, 1.0))
	var steps := maxi(2, int(ceil(arc_span / sample)))
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
