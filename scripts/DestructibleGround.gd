class_name DestructibleGround
extends StaticBody2D
## Issue #190: destructible terrain.
##
## Characters can stand on it, but it is NOT a gravity source — only
## indestructible ground bends gravity. An explosion (Projectile._explode)
## calls `apply_blast` and the rect chunk is subtracted with the blast's
## circle bounding box; the leftover strips spawn as new chunks, so craters
## grow chunk by chunk. Visual is drawn in code — no assets.

const COLOR := Color(0.45, 0.32, 0.2, 1)
## Strips thinner than this are discarded (avoids sub-pixel slivers).
const MIN_PIECE := 8.0

@export var rect_size := Vector2(200, 60)


func _ready() -> void:
	collision_layer = 1
	add_to_group("destructible_ground")
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = rect_size
	shape.shape = rect
	add_child(shape)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-rect_size / 2.0, rect_size), COLOR)


## Carve this chunk with an explosion at `global_point` (blast `radius`).
func apply_blast(global_point: Vector2, radius: float) -> void:
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


func _spawn(offset: Vector2, size: Vector2) -> void:
	if size.x < MIN_PIECE or size.y < MIN_PIECE:
		return
	var piece := DestructibleGround.new()
	piece.rect_size = size
	piece.position = position + offset + size / 2.0
	get_parent().add_child(piece)
