class_name CharacterAnimator
extends Node
## Issue #558: reusable PROCEDURAL character animation — idle, walk and
## jump motion derived from the figure's MOVEMENT state and applied to
## the BODY VISUAL only (squash/stretch, bob, tilt) plus, when the visual
## is a ModularCharacterVisual, its face (blinking, eye glances and the
## airborne expression).
##
## Purely visual BY CONSTRUCTION: this is a plain Node under the figure —
## it never writes the figure's velocity, position or collision shapes
## and no gameplay code depends on it. It only READS the movement state
## (is_on_floor plus the velocity split into the gravity frame's tangent
## and normal — current_gravity()/current_tangent() when the figure
## offers them, world-down otherwise) and writes the visual node's
## transform. Squash/stretch bends the visual AROUND its centre; the
## walk tilt composes ON TOP of the gravity-aligned base rotation
## FigurePose assigns every physics frame (the animator runs after the
## physics step in the frame loop), so the same animation works under
## any gravity direction, radial arenas included, and for every
## geometric body (ColorRect square, ShapeVisual silhouettes, the
## modular character).
##
## States (mapped 1:1 onto the movement state):
##   IDLE — breathing squash/stretch, blinking, small eye movements;
##   WALK — repeated bouncing with a step-rate tilt oscillation and a
##          subtle squash at each ground contact;
##   RISE — stretch along the local up axis while moving away from the
##          floor (with a takeoff squash impulse, see notify_jump);
##   FALL — milder stretch plus a worried airborne expression.
## A landing squash impulse plays on the airborne→grounded edge. Every
## state's target is blended toward with one exponential smoother, so
## movement-state changes never snap or fight each other: the animator
## is the single writer of the visual's transform.
##
## Attach: add as a child of the figure and call setup(figure, visual).
## All frequencies, amounts and blend times are exported — the animation
## timing is configurable per instance from the Inspector or from code.

## ------------------------------------------------------------------ idle
## Breaths per second of the idle breathing squash/stretch.
@export var idle_breath_rate := 0.35:
	set(value):
		idle_breath_rate = maxf(value, 0.0)

## Vertical scale amplitude of one idle breath (0.03 = 3% at 64 px).
@export var idle_breath_amount := 0.03

## Random pause between blinks, in seconds (drawn per blink).
@export var blink_interval_min := 2.0
@export var blink_interval_max := 5.5

## How long one blink keeps the lid (fully) closed-ish, in seconds.
@export var blink_duration := 0.12

## Seconds between idle eye glances and how far the pupils roam
## (fraction of the eye radius).
@export var eye_dart_interval := 1.6
@export var eye_dart_amount := 0.35

## ------------------------------------------------------------------ walk
## Tangential speed above which grounded motion counts as WALK.
@export var walk_speed_threshold := 20.0

## Reference walk speed the step rate scales with (CharacterStats.SPEED).
@export var walk_reference_speed := 220.0

## Bounce cycles per second at the reference speed.
@export var walk_step_rate := 3.4

## Bob height of each bounce, px at the reference 64 px body.
@export var walk_bounce_amount := 2.6

## Peak tilt of the step oscillation, degrees.
@export var walk_tilt_deg := 5.0

## Squash at each bounce's ground contact.
@export var walk_squash_amount := 0.05

## ------------------------------------------------------------- jump/air
## Takeoff impulse: squash envelope played at notify_jump() — the visual
## squash that reads as "squash before takeoff" while the jump rises.
@export var takeoff_squash := 0.18
@export var takeoff_time := 0.10

## Peak stretch away from the floor while rising, and the milder one
## while falling.
@export var rise_stretch := 0.22
@export var fall_stretch := 0.10

## Landing squash impulse and its recovery time, seconds.
@export var land_squash := 0.22
@export var land_recover_time := 0.22

## ---------------------------------------------------------------- blend
## Exponential smoothing time toward each state's target — this is what
## makes every state change a smooth transition.
@export var blend_time := 0.10

## Drive the face too (blink/glances/airborne expression) when the
## visual has facial features; transform animation always runs.
@export var face_animation := true

enum State { IDLE, WALK, RISE, FALL }

## Current animation state — public read for tests/debugging.
var state: State = State.IDLE

var _figure: CharacterBody2D
var _visual: Control
## Authored transform the animation composes on top of.
var _home_position := Vector2.ZERO
## Live blended values (the smoother owns them — single writer).
var _scale_now := Vector2.ONE
var _bob_now := 0.0
var _tilt_now := 0.0

var _time := 0.0
var _walk_phase := 0.0
var _walk_dir := 1.0
var _air_time := 0.0
var _was_grounded := true
var _takeoff_left := 0.0
var _land_left := 0.0

## Face life (only when the visual supports it).
const FaceVisual := preload("res://scripts/ModularCharacterVisual.gd")
var _has_face := false
var _idle_eye: int = -1
var _idle_brow: int = -1
var _idle_mouth: int = -1
var _blink_wait := 1.0
var _blink_time_left := 0.0
var _dart_wait := 0.0
var _dart := Vector2.ZERO
var _dart_target := Vector2.ZERO


## Point the animator at the figure it animates and at the node that
## depicts its body. Safe to re-call after a team-shape change swapped
## the visual node.
func setup(figure: CharacterBody2D, visual: Control) -> void:
	_figure = figure
	_visual = visual
	_home_position = visual.position
	_scale_now = visual.scale
	_bob_now = 0.0
	_tilt_now = 0.0
	_has_face = visual.get("eye_style") != null
	if _has_face:
		# Remember the authored face so grounded states restore it —
		# the airborne expression is a temporary override, not a restyle.
		_idle_eye = int(visual.get("eye_style"))
		_idle_brow = int(visual.get("eyebrow_style"))
		_idle_mouth = int(visual.get("mouth_style"))
		visual.set("eye_open", 1.0)
		visual.set("pupil_shift", Vector2.ZERO)
	_blink_wait = randf_range(blink_interval_min, blink_interval_max)
	_dart_wait = randf_range(0.2, eye_dart_interval)


## Movement-state hook for the jump edge: gameplay jumps immediately
## (physics stays untouched); the quick squash impulse this fires reads
## as the squash-before-takeoff while the figure lifts off.
func notify_jump() -> void:
	_takeoff_left = takeoff_time


func _process(delta: float) -> void:
	if not is_instance_valid(_figure) or not is_instance_valid(_visual) \
			or _figure.is_queued_for_deletion():
		return
	_time += delta

	# --- read the movement state (gravity frame, DOWN fallback) -------
	var grav := Vector2.DOWN
	if _figure.has_method("current_gravity"):
		var g: Vector2 = _figure.current_gravity()
		if g.length_squared() > 0.25:
			grav = g.normalized()
	var tangent := Vector2(grav.y, -grav.x)
	var grounded := _figure.is_on_floor()
	var walk_speed := _figure.velocity.dot(tangent)
	# Along-gravity speed: > 0 = falling toward the floor, < 0 = rising.
	var vertical := _figure.velocity.dot(grav)

	if grounded:
		_air_time = 0.0
	else:
		_air_time += delta
	# Landing edge: airborne for a real while, then grounded again.
	if grounded and not _was_grounded and _air_time <= 0.0 \
			and _was_air_recently:
		_land_left = land_recover_time
	if not grounded:
		_was_air_recently = true
	else:
		_was_air_recently = false
	_was_grounded = grounded

	# --- pick the animation state --------------------------------------
	if not grounded:
		state = State.RISE if vertical < -10.0 else State.FALL
	elif absf(walk_speed) > walk_speed_threshold:
		state = State.WALK
	else:
		state = State.IDLE

	# --- per-state target transform ------------------------------------
	var target_scale := Vector2.ONE
	var target_bob := 0.0
	var target_tilt := 0.0
	match state:
		State.IDLE:
			var breath := sin(_time * TAU * idle_breath_rate) \
					* idle_breath_amount
			target_scale = Vector2(1.0 - breath * 0.6, 1.0 + breath)
		State.WALK:
			var speed_ratio := clampf(absf(walk_speed)
					/ maxf(walk_reference_speed, 1.0), 0.35, 1.0)
			_walk_phase = fmod(_walk_phase
					+ delta * walk_step_rate * speed_ratio, 1.0)
			_walk_dir = signf(walk_speed) if walk_speed != 0.0 else _walk_dir
			# Two ground contacts per cycle: hop peaks between them.
			var hop := absf(sin(_walk_phase * PI))
			var squash := walk_squash_amount * (0.5 - hop)
			target_scale = Vector2(1.0 + squash, 1.0 - squash)
			target_bob = hop * walk_bounce_amount
			target_tilt = deg_to_rad(walk_tilt_deg) \
					* sin(_walk_phase * TAU) * _walk_dir
		State.RISE:
			var k := clampf(-vertical / 400.0, 0.0, 1.0)
			target_scale = _volume(1.0 + rise_stretch * k)
		State.FALL:
			var k := clampf(vertical / 500.0, 0.0, 1.0)
			target_scale = _volume(1.0 + fall_stretch * k)

	# --- transient impulses (bell envelopes: continuous in and out) ---
	# The takeoff impulse REPLACES the state target for its short life —
	# multiplied onto the rise stretch (x1.2+) the squash would cancel
	# out and read as nothing; on its own it is the visible
	# squash-before-takeoff that then blends into the rise stretch.
	if _takeoff_left > 0.0:
		_takeoff_left = maxf(_takeoff_left - delta, 0.0)
		var p := 1.0 - _takeoff_left / maxf(takeoff_time, 0.001)
		target_scale = _volume(1.0 - takeoff_squash
				* sin(PI * clampf(p, 0.0, 1.0)))
	if _land_left > 0.0:
		_land_left = maxf(_land_left - delta, 0.0)
		var p2 := 1.0 - _land_left / maxf(land_recover_time, 0.001)
		target_scale *= _volume(1.0 - land_squash
				* sin(PI * clampf(p2, 0.0, 1.0)))

	# --- one exponential smoother -> smooth transitions, no fights -----
	var k := 1.0 - exp(-delta / maxf(blend_time, 0.001))
	_scale_now = _scale_now.lerp(target_scale, k)
	_bob_now = lerpf(_bob_now, target_bob, k)
	_tilt_now = lerpf(_tilt_now, target_tilt, k)
	_apply(grav)
	if _has_face:
		_tick_face(delta)


func _apply(grav: Vector2) -> void:
	# Rotation: the gravity-aligned base FigurePose writes each physics
	# frame, plus the animation tilt on top (the animator's _process runs
	# after the physics step, so its value is what renders).
	_visual.rotation = (grav.angle() - PI / 2.0) + _tilt_now
	_visual.pivot_offset = _visual.size / 2.0
	# Bob along the LOCAL up (away from the floor) in the figure's frame.
	_visual.position = _home_position - grav * _bob_now
	# Volume-preserving squash/stretch, clamped against degenerate values.
	_visual.scale = Vector2(
			clampf(_scale_now.x, 0.3, 2.5),
			clampf(_scale_now.y, 0.3, 2.5))


## Width grows as height shrinks, keeping the body's visual volume.
func _volume(sy: float) -> Vector2:
	sy = clampf(sy, 0.3, 2.5)
	return Vector2(1.0 / sqrt(sy), sy)


func _tick_face(delta: float) -> void:
	# Airborne expression while off the ground; authored face restored
	# as soon as the figure is grounded again.
	if state == State.RISE:
		_visual.set("eye_style", FaceVisual.EyeStyle.WIDE)
		_visual.set("eyebrow_style", FaceVisual.EyebrowStyle.RAISED)
		_visual.set("mouth_style", FaceVisual.MouthStyle.OPEN)
	elif state == State.FALL:
		_visual.set("eye_style", FaceVisual.EyeStyle.WIDE)
		_visual.set("eyebrow_style", FaceVisual.EyebrowStyle.WORRIED)
		_visual.set("mouth_style", FaceVisual.MouthStyle.FROWN)
	else:
		_visual.set("eye_style", _idle_eye)
		_visual.set("eyebrow_style", _idle_brow)
		_visual.set("mouth_style", _idle_mouth)

	# Blinking (grounded states; wide airborne eyes never blink).
	if state == State.RISE or state == State.FALL:
		_visual.set("eye_open", 1.0)
	else:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_wait = randf_range(blink_interval_min,
					blink_interval_max)
			_blink_time_left = blink_duration
		var open := 1.0
		if _blink_time_left > 0.0:
			_blink_time_left = maxf(_blink_time_left - delta, 0.0)
			var p := 1.0 - _blink_time_left / maxf(blink_duration, 0.001)
			open = 1.0 - sin(PI * clampf(p, 0.0, 1.0))
		_visual.set("eye_open", open)

	# Small idle glances: pupils ease toward a fresh nearby target every
	# couple of seconds.
	_dart_wait -= delta
	if _dart_wait <= 0.0:
		_dart_wait = randf_range(0.4 * eye_dart_interval,
				1.6 * eye_dart_interval)
		var angle := randf() * TAU
		var reach := eye_dart_amount * randf()
		_dart_target = Vector2(cos(angle), sin(angle)) * reach
	_dart = _dart.lerp(_dart_target,
			1.0 - exp(-delta / maxf(blend_time * 2.0, 0.001)))
	_visual.set("pupil_shift", _dart)


## True while the figure was airborne moments ago (landing detection
## that survives the one-frame _air_time reset).
var _was_air_recently := false
