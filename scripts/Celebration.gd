extends CanvasLayer
## Simple celebration overlay (issue #194).
##
## Shows a "Level Complete!" banner that pops in with a tween and rains
## confetti (square particles, the game's own shapes) for `duration`
## seconds, then emits `finished` and frees itself.

signal finished

@export var duration: float = 2.0
@export var message: String = "Level Complete!"

const CONFETTI_COLORS: Array[Color] = [
	Color(0.95, 0.3, 0.3),
	Color(0.3, 0.6, 0.95),
	Color(0.3, 0.8, 0.4),
	Color(0.95, 0.85, 0.3),
	Color(0.85, 0.4, 0.9),
]


func _ready() -> void:
	layer = 100
	_add_banner()
	_add_confetti()
	await get_tree().create_timer(duration).timeout
	_finish()


func _add_banner() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15))
	label.add_theme_constant_override("outline_size", 10)
	center.add_child(label)

	# Pop-in: start small and scale up with a little overshoot.
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.1, 0.1)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15)


func _add_confetti() -> void:
	var viewport_size := Vector2(1280, 720)
	if get_viewport() != null:
		viewport_size = get_viewport().get_visible_rect().size

	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(viewport_size.x / 2.0, -20.0)
	confetti.amount = 120
	confetti.lifetime = 1.6
	confetti.speed_scale = 1.0
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(viewport_size.x / 2.0, 8.0)
	confetti.direction = Vector2(0, 1)
	confetti.spread = 25.0
	confetti.gravity = Vector2(0, 500)
	confetti.initial_velocity_min = 60.0
	confetti.initial_velocity_max = 160.0
	confetti.angular_velocity_min = -360.0
	confetti.angular_velocity_max = 360.0
	confetti.scale_amount_min = 4.0
	confetti.scale_amount_max = 9.0

	# Squares of confetti in the game's palette.
	var gradient := Gradient.new()
	for i in CONFETTI_COLORS.size():
		gradient.set_color(float(i) / float(CONFETTI_COLORS.size() - 1), CONFETTI_COLORS[i])
	confetti.color_initial_ramp = gradient

	add_child(confetti)


func _finish() -> void:
	finished.emit()
	queue_free()
