extends Control
## Issue #169: draws the team figure's body shape (instead of the plain
## square ColorRect). Sized like the scene-authored visual (64x64); the
## shape is filled with `shape_color`.

## One of: square, circle, triangle, star, ellipse.
@export var shape := "square"

@export var shape_color := Color(1, 0.84, 0.2, 1)


func _draw() -> void:
	var size := self.size
	var c := size / 2.0
	match shape:
		"circle", "ellipse":
			var y_scale := 1.0 if shape == "circle" else size.y / size.x
			draw_set_transform(c, 0.0, Vector2(1.0, y_scale))
			draw_circle(Vector2.ZERO, size.x / 2.0, shape_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				Vector2(c.x, size.y * 0.06), Vector2(size.x * 0.96, size.y * 0.94), Vector2(size.x * 0.04, size.y * 0.94)
			]), shape_color)
		"star":
			var points := PackedVector2Array()
			var outer := size.x / 2.0
			var inner := outer * 0.45
			for i in 10:
				var angle := -PI / 2.0 + TAU * i / 10.0
				var radius := outer if i % 2 == 0 else inner
				points.append(c + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, shape_color)
		_:
			# Square: plain filled rect (same look as the authored ColorRect).
			draw_rect(Rect2(Vector2.ZERO, size), shape_color)


func set_shape(value: String) -> void:
	shape = value
	queue_redraw()


func set_shape_color(value: Color) -> void:
	shape_color = value
	queue_redraw()
