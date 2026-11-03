class_name IndestructibleGround
extends StaticBody2D
## Issue #190: indestructible terrain — the level's ONLY gravity source.
##
## Two authored forms:
##  - rectangle slab (`radius == 0`, size = `rect_size`): flat ground;
##  - circle disc (`radius > 0`): a curved hill — a surface without sharp
##    corners, so surface gravity has a single well-defined normal.
## Gravity near this body always points toward its surface along the
## surface normal (see LevelTerrain.gd). Visuals are drawn in code —
## no assets.
##
## Issue #236: the level's ONLY gravity source — every level's gravity
## comes exclusively from indestructible ground. Purple marks it as the
## permanent, gravity-bending terrain (brown is destructible ground).
##
## Issue #270: geometry rules for every indestructible mass.
##  - MINIMUM THICKNESS 7 character widths (7 x 64 = 448 px): an authored
##    slab thinner than that is extended DOWNWARD at build time so the
##    walkable top face never moves; a disc must be at least 448 px in
##    diameter (radius >= 224).
##  - ROUNDED CORNERS of at least 3 character widths (192 px) on every
##    slab — clamped to half the slab's shortest side when the slab is
##    too small to fit the full radius. The collision becomes a convex
##    rounded-rectangle polygon (CollisionPolygon2D "Shape") and the
##    visual draws exactly that polygon; LevelTerrain handles it.
##  - SEPARATED masses keep at least 8 character widths (512 px) of gap;
##    touching/overlapping masses count as ONE landmass. This is a level
##    authoring rule — verified per level by tests/test_issue270.gd.
const COLOR := Color(0.45, 0.3, 0.65, 1)

const Stats := preload("res://scripts/CharacterStats.gd")
## Issue #270: the terrain rules, in character widths (BODY_SIZE = 64).
const MIN_THICKNESS := 7.0 * Stats.BODY_SIZE
const MIN_CORNER := 3.0 * Stats.BODY_SIZE

## > 0 makes this body a circular disc (no sharp corners); otherwise it is
## a rectangle of `rect_size`.
@export var radius := 0.0
@export var rect_size := Vector2(200, 100)

## Effective slab geometry after the issue #270 guards (slab mode only):
## the real size, the local y offset of the slab's centre (the thickness
## guard extends downward, keeping the authored top face) and the corner
## radius. Exposed for the gravity math and the regression test.
var _eff_size := Vector2.ZERO
var _eff_offset := 0.0
var _corner := 0.0


func _ready() -> void:
	collision_layer = 1
	add_to_group("indestructible_ground")
	add_to_group("gravity_source")
	if radius > 0.0:
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		add_child(shape)
	else:
		# Issue #270: enforce the minimum thickness by extending the slab
		# DOWNWARD — the authored top face (the walking surface) is kept
		# exactly where the level placed it.
		_eff_size = rect_size
		if _eff_size.y < MIN_THICKNESS:
			_eff_offset = -rect_size.y / 2.0 + MIN_THICKNESS / 2.0
			_eff_size.y = MIN_THICKNESS
		_corner = clampf(MIN_CORNER, 0.0, minf(_eff_size.x, _eff_size.y) / 2.0)
		var poly := CollisionPolygon2D.new()
		poly.name = "Shape"
		poly.position = Vector2(0.0, _eff_offset)
		poly.polygon = rounded_rect_polygon(_eff_size, _corner)
		add_child(poly)
	queue_redraw()


func _draw() -> void:
	if radius > 0.0:
		draw_circle(Vector2.ZERO, radius, COLOR)
	else:
		draw_colored_polygon(rounded_rect_polygon(_eff_size, _corner,
				_eff_offset), COLOR)


## Effective slab size / corner radius / centre offset after the issue
## #270 thickness guard (slab mode; zeroed for discs).
func effective_size() -> Vector2:
	return _eff_size


func corner_radius() -> float:
	return _corner


func effective_offset() -> float:
	return _eff_offset


## Convex polygon of a `size`-sized rounded rectangle centred on the
## origin (optionally shifted by `y_offset`), tracing the four corner
## arcs of radius `corner` — the collision shape AND the drawn visual of
## every slab, so the two can never drift apart.
static func rounded_rect_polygon(size: Vector2, corner: float,
		y_offset := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := size / 2.0
	var c := clampf(corner, 0.0, minf(h.x, h.y))
	if c <= 0.0:
		pts.append(Vector2(-h.x, -h.y + y_offset))
		pts.append(Vector2(h.x, -h.y + y_offset))
		pts.append(Vector2(h.x, h.y + y_offset))
		pts.append(Vector2(-h.x, h.y + y_offset))
		return pts
	# Corner arc centres; each arc runs the OUTWARD quarter turn so
	# consecutive arcs line up along the straight top/right/bottom/left
	# edges (start angle 180° + 90°·i — the quadrant facing away from the
	# rect's centre, i.e. the actual corner).
	var centres := [Vector2(-h.x + c, -h.y + c), Vector2(h.x - c, -h.y + c),
			Vector2(h.x - c, h.y - c), Vector2(-h.x + c, h.y - c)]
	const SEGMENTS := 12
	for i in 4:
		var a0 := PI + PI / 2.0 * float(i)
		for s in SEGMENTS + 1:
			var a := a0 + (PI / 2.0) * float(s) / float(SEGMENTS)
			pts.append(centres[i] + Vector2(c * cos(a), c * sin(a))
					+ Vector2(0.0, y_offset))
	return pts
