extends CanvasLayer
## Simple celebration overlay (issue #194).
##
## Shows a "Level Complete!" banner that pops in with a tween and rains
## confetti (square particles, the game's own shapes). Issue #194 rework
## (owner, 2026-11-27): the animation runs a little longer, and before it
## stops the confetti stops spawning and the remaining particles fly away
## out through the BOTTOM edge — nothing pops out mid-screen. Then the
## overlay emits `finished` and frees itself.

signal finished

@export var duration: float = 3.5
@export var message: String = "Level Complete!"

## Issue #194 rework: length of the final fly-away phase, during which no
## new confetti spawns and the live particles are pulled down and out
## through the bottom edge. 1.5 s covers the slowest particle from the
## top of the screen under the gravity surge (~1.1 s worst case) with
## margin; the total animation length is still `duration`.
const CONFETTI_FLYAWAY := 1.5

const CONFETTI_COLORS: Array[Color] = [
	Color(0.95, 0.3, 0.3),
	Color(0.3, 0.6, 0.95),
	Color(0.3, 0.8, 0.4),
	Color(0.95, 0.85, 0.3),
	Color(0.85, 0.4, 0.9),
]

var _confetti: CPUParticles2D = null
var _banner_label: Label = null


func _ready() -> void:
	layer = 100
	_add_banner()
	await get_tree().process_frame
	_add_confetti()
	# Issue #194 rework: rain for the first part of the animation, then
	# stop spawning confetti and sweep everything out through the bottom
	# edge BEFORE the animation stops.
	var fly_away_time := minf(duration, CONFETTI_FLYAWAY)
	var rain_time := duration - fly_away_time
	if rain_time > 0.0:
		await get_tree().create_timer(rain_time).timeout
	_fly_away(fly_away_time)
	await get_tree().create_timer(fly_away_time).timeout
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
	_banner_label = label

	# Pop-in: start small and scale up with a little overshoot.
	await get_tree().process_frame
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
	# Issue #194 rework: particles outlive the fly-away sweep so they
	# leave through the bottom edge instead of fading mid-screen.
	confetti.lifetime = 2.6
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
	# CPUParticles2D.color_initial_ramp is typed Gradient in Godot 4.x;
	# assigning a GradientTexture1D is a parse error under typed GDScript.
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in CONFETTI_COLORS.size():
		offsets.append(float(i) / float(CONFETTI_COLORS.size() - 1))
		colors.append(CONFETTI_COLORS[i])
	gradient.offsets = offsets
	gradient.colors = colors
	confetti.color_initial_ramp = gradient

	add_child(confetti)
	_confetti = confetti


## Issue #194 rework: stop spawning new confetti and surge the gravity so
## the remaining particles fly away out through the bottom edge before
## the overlay ends. The banner fades out just before the finish.
func _fly_away(fly_away_time: float) -> void:
	if _confetti != null:
		_confetti.emitting = false
		var sweep := create_tween()
		sweep.tween_property(_confetti, "gravity", Vector2(0, 2400), 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _banner_label != null:
		var fade := create_tween()
		fade.tween_interval(maxf(0.0, fly_away_time - 0.4))
		fade.tween_property(_banner_label, "modulate:a", 0.0, 0.4)


func _finish() -> void:
	finished.emit()
	queue_free()
