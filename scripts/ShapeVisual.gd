extends Control
## Issue #169: draws the team figure's body shape (instead of the plain
## square ColorRect). Sized like the scene-authored visual (64x64); the
## shape is filled with `shape_color`.

## One of: square, circle, triangle, star, ellipse.
@export var shape := "square"

@export var shape_color := Color(1, 0.84, 0.2, 1)

## Issue #169 rework: dark outline around the shape so the figure reads
## clearly against any background.
@export var outline_color := Color(0.12, 0.08, 0.16, 1.0)

@export var outline_scale := 1.14


func _draw() -> void:
	var size := self.size
	_draw_shape(size, outline_color, outline_scale)
	_draw_shape(size, shape_color, 1.0)


func _draw_shape(size: Vector2, color: Color, scale_f: float) -> void:
	var c := size / 2.0
	match shape:
		"circle", "ellipse":
			var y_scale := 1.0 if shape == "circle" else size.y / size.x
			draw_set_transform(c, 0.0, Vector2(scale_f, y_scale * scale_f))
			draw_circle(Vector2.ZERO, size.x / 2.0, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"triangle":
			draw_colored_polygon(_scaled(PackedVector2Array([
				Vector2(c.x, size.y * 0.06), Vector2(size.x * 0.96, size.y * 0.94), Vector2(size.x * 0.04, size.y * 0.94)
			]), c, scale_f), color)
		"star":
			var points := PackedVector2Array()
			var outer := size.x / 2.0
			var inner := outer * 0.45
			for i in 10:
				var angle := -PI / 2.0 + TAU * i / 10.0
				var radius := outer if i % 2 == 0 else inner
				points.append(c + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(_scaled(points, c, scale_f), color)
		_:
			# Square: plain filled rect (same look as the authored ColorRect).
			var half := size * 0.5 * scale_f
			draw_rect(Rect2(c - half, half * 2.0), color)


func _scaled(points: PackedVector2Array, c: Vector2, scale_f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(c + (p - c) * scale_f)
	return out


func set_shape(value: String) -> void:
	shape = value
	queue_redraw()


func set_shape_color(value: Color) -> void:
	shape_color = value
	queue_redraw()
