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

## Issue #236: the level's ONLY gravity source — every level's gravity
## comes exclusively from indestructible ground. Purple marks it as the
## permanent, gravity-bending terrain (brown is destructible ground).
const COLOR := Color(0.45, 0.3, 0.65, 1)

## > 0 makes this body a circular disc (no sharp corners); otherwise it is
## a rectangle of `rect_size`.
@export var radius := 0.0
@export var rect_size := Vector2(200, 100)


func _ready() -> void:
	collision_layer = 1
	add_to_group("indestructible_ground")
	add_to_group("gravity_source")
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	if radius > 0.0:
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
	else:
		var rect := RectangleShape2D.new()
		rect.size = rect_size
		shape.shape = rect
	add_child(shape)
	queue_redraw()


func _draw() -> void:
	if radius > 0.0:
		draw_circle(Vector2.ZERO, radius, COLOR)
	else:
		draw_rect(Rect2(-rect_size / 2.0, rect_size), COLOR)
