extends Control
## Static geometric background composition for the main menu
## (docs/ui/main_menu.md §3.3).
##
## Dark graphite base, a restrained composition of Forms (geometric
## shapes) laid out along a curved "gravity distortion" arc, subtle
## glow and shadow. Completely static: drawn once per resize, no
## animation, particles or movement. Standalone scene so the background
## stays replaceable independently of menu logic.

const BASE := Color("#17191F")
const PANEL := Color("#292D38")
const EDGE := Color("#343943")
const DIM := Color("#777D8B")
const ACCENT := Color("#A78BFA")

const SHADOW := Color(0.0, 0.0, 0.0, 0.28)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 8.0 or s.y < 8.0:
		return
	draw_rect(Rect2(Vector2.ZERO, s), BASE)

	var unit: float = minf(s.x, s.y)
	var focus := Vector2(s.x * 0.78, s.y * 0.66)
	var radius: float = unit * 0.30

	_glow(focus, radius)
	_depth_rings(focus, radius, unit)
	_gravity_arc(focus, radius)
	_forms_on_arc(focus, radius, unit)


## Subtle lighting: layered translucent accent circles behind the
## composition. Restrained on purpose (spec: background must not
## compete with menu controls).
func _glow(focus: Vector2, radius: float) -> void:
	for layer in 3:
		var a := 0.050 - layer * 0.016
		draw_circle(focus, radius * (1.0 + layer * 0.55), Color(ACCENT, a))


## Faint concentric outlines adding depth without motion.
func _depth_rings(focus: Vector2, radius: float, unit: float) -> void:
	var far := Vector2(size.x * 0.12, size.y * 0.18)
	draw_arc(far, unit * 0.55, 0.0, TAU, 96, Color(EDGE, 0.35), 1.5, true)
	draw_arc(focus, radius * 0.55, 0.0, TAU, 96, Color(EDGE, 0.30), 1.5, true)


## The curved arrangement referencing gravity distortion: two offset
## arcs the Forms travel along.
func _gravity_arc(focus: Vector2, radius: float) -> void:
	var from_a: float = PI * -0.15
	var to_a: float = PI * 0.60
	draw_arc(focus, radius, from_a, to_a, 48, Color(EDGE, 0.9), 2.0, true)
	draw_arc(focus, radius * 1.28, from_a + 0.10, to_a - 0.05, 48,
		Color(EDGE, 0.45), 2.0, true)
	draw_arc(focus, radius * 0.72, from_a + 0.05, to_a - 0.10, 48,
		Color(ACCENT, 0.18), 1.5, true)


## Triangle, square and circle (the Forms) placed on the main arc with
## soft drop shadows; the triangle (player's figure) gets the accent.
func _forms_on_arc(focus: Vector2, radius: float, unit: float) -> void:
	var scale: float = clampf(unit / 648.0, 0.55, 1.4)
	var spots := [
		{"ang": PI * 0.02, "kind": "triangle", "size": 76.0 * scale},
		{"ang": PI * 0.28, "kind": "square", "size": 54.0 * scale},
		{"ang": PI * 0.50, "kind": "circle", "size": 40.0 * scale},
	]
	for spot in spots:
		var pos := focus + Vector2(cos(spot["ang"]), sin(spot["ang"])) * radius
		var shape_size: float = spot["size"]
		var accent_edge: bool = spot["kind"] == "triangle"
		_shadow_under(pos, shape_size)
		match spot["kind"]:
			"triangle":
				_triangle(pos, shape_size, spot["ang"] + PI * 0.5, accent_edge)
			"square":
				_square(pos, shape_size, spot["ang"], accent_edge)
			"circle":
				draw_circle(pos, shape_size * 0.5, PANEL)
				if accent_edge:
					draw_arc(pos, shape_size * 0.5, 0.0, TAU, 48,
						Color(ACCENT, 0.8), 2.0, true)
				else:
					draw_arc(pos, shape_size * 0.5, 0.0, TAU, 48,
						Color(EDGE, 0.9), 1.5, true)


func _shadow_under(pos: Vector2, shape_size: float) -> void:
	var ellipse := Transform2D().scaled_local(
		Vector2(shape_size * 0.62, shape_size * 0.16))
	draw_set_transform_matrix(ellipse.translated(
		pos + Vector2(0, shape_size * 0.62)))
	draw_circle(Vector2.ZERO, 1.0, SHADOW)
	draw_set_transform_matrix(Transform2D())


func _triangle(pos: Vector2, shape_size: float, rot: float,
		accent: bool) -> void:
	var r: float = shape_size * 0.58
	var pts := PackedVector2Array([
		Vector2(0, -r),
		Vector2(r * 0.87, r * 0.5),
		Vector2(-r * 0.87, r * 0.5),
	])
	draw_set_transform(pos, rot, Vector2.ONE)
	draw_colored_polygon(pts, PANEL)
	if accent:
		draw_polyline(pts + PackedVector2Array([pts[0]]),
			Color(ACCENT, 0.85), 2.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _square(pos: Vector2, shape_size: float, rot: float,
		accent: bool) -> void:
	var half: float = shape_size * 0.5
	var rect := Rect2(-half, -half, shape_size, shape_size)
	draw_set_transform(pos, rot, Vector2.ONE)
	draw_rect(rect, PANEL)
	if accent:
		draw_rect(rect, Color(ACCENT, 0.85), false, 2.5)
	else:
		draw_rect(rect, Color(EDGE, 0.9), false, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
