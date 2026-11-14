extends Node
## Regression check for issue #558: procedural character animation.
##
##  1. PURE VISUAL: the animator never touches the figure's physics —
##     the collision shape's transform stays identity while the body
##     visual bends, and the figure still lands/rests normally;
##  2. STATES FOLLOW MOVEMENT: IDLE when grounded and still, WALK when
##     grounded and moving, RISE/FALL when airborne, back to IDLE after
##     landing;
##  3. EACH STATE ANIMATES: idle breath moves the scale subtly, walk
##     bounces and tilts, a jump squashes at takeoff and stretches while
##     rising, landing squashes and recovers;
##  4. SMOOTHNESS: even abrupt movement-state flips change the transform
##     smoothly (bounded per-frame step — no fighting animations);
##  5. FACE LIFE: blinking closes the eyes, idle glances move the
##     pupils, the airborne expression takes over mid-air and the
##     authored face returns on the ground;
##  6. CONFIGURABLE: exported amplitudes drive the motion (a 6x breath
##     reads 6x bigger);
##  7. SHAPES: the same animator stretches every geometric silhouette.
##
## Run headless: godot --headless res://tests/test_issue558.tscn
## Exit code 0 = pass.

const AnimatorScript := preload("res://scripts/CharacterAnimator.gd")
const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")

var failures := 0


## Minimal stand-in for Player/Npc: gravity + move_and_slide and the
## same gravity-frame accessors the real figures expose.
class TestFigure extends CharacterBody2D:
	func current_gravity() -> Vector2:
		return Vector2.DOWN

	func current_tangent() -> Vector2:
		return Vector2.RIGHT

	func _physics_process(delta: float) -> void:
		if not is_on_floor():
			velocity += Vector2.DOWN * 980.0 * delta
		move_and_slide()


## Watches one visual's scale every rendered frame to bound how fast the
## animator may ever change it (the smoothness gate).
class ScaleMonitor extends Node:
	var target: Control
	var last := Vector2.ONE
	var max_step := 0.0

	func _process(_delta: float) -> void:
		if target == null or not is_instance_valid(target):
			return
		max_step = maxf(max_step, (target.scale - last).length())
		last = target.scale


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	# --- build the mini-level -------------------------------------------
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(600.0, 40.0)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	var figure := TestFigure.new()
	figure.collision_layer = 8
	figure.collision_mask = 1
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 57.6
	var collision := CollisionShape2D.new()
	collision.name = "TestShape"
	collision.shape = capsule
	figure.add_child(collision)
	var visual: Control = VisualScript.new()
	visual.name = "TestVisual"
	visual.position = Vector2(-32.0, -32.0)
	visual.size = Vector2(64.0, 64.0)
	figure.add_child(visual)
	figure.position = Vector2(0.0, -48.0)
	add_child(figure)

	var animator := AnimatorScript.new()
	figure.add_child(animator)
	animator.setup(figure, visual)
	var monitor := ScaleMonitor.new()
	monitor.target = visual
	figure.add_child(monitor)

	await _frames(15)
	_check(figure.is_on_floor(), "the test figure rests on the floor")

	# --- 1) pure visual + 2/3) idle ---------------------------------------
	_check(animator.state == AnimatorScript.State.IDLE,
			"a grounded, still figure idles")
	var sy1 := visual.scale.y
	await _frames(25)
	var sy2 := visual.scale.y
	_check(absf(sy1 - 1.0) <= 0.06 and absf(sy2 - 1.0) <= 0.06,
			"idle breathing stays subtle")
	_check(not is_equal_approx(sy1, sy2), "idle breath moves the body")
	_check(collision.scale == Vector2.ONE
			and is_zero_approx(collision.rotation)
			and collision.position == Vector2.ZERO,
			"the collision shape is never animated")

	# --- walk -------------------------------------------------------------
	figure.velocity = Vector2(240.0, 0.0)
	await _frames(8)
	_check(animator.state == AnimatorScript.State.WALK,
			"grounded motion reads as WALK")
	var saw_bounce := false
	var saw_tilt := 0.0
	for i in 30:
		await get_tree().physics_frame
		if absf(visual.position.y - (-32.0)) > 0.5:
			saw_bounce = true
		saw_tilt = maxf(saw_tilt, absf(visual.rotation))
	_check(saw_bounce, "walk bounces the body")
	_check(saw_tilt > 0.02, "walk adds the step tilt")
	figure.velocity = Vector2(0.0, 0.0)

	# --- jump -------------------------------------------------------------
	var eye_before: int = visual.eye_style
	var brow_before: int = visual.eyebrow_style
	var mouth_before: int = visual.mouth_style
	figure.velocity = Vector2(0.0, -420.0)
	animator.notify_jump()
	await _frames(2)
	_check(animator.state == AnimatorScript.State.RISE,
			"leaving the floor upward reads as RISE")
	var saw_takeoff_squash := false
	var saw_rise_stretch := false
	for i in 20:
		await get_tree().physics_frame
		saw_takeoff_squash = saw_takeoff_squash or visual.scale.y < 0.99
		saw_rise_stretch = saw_rise_stretch or visual.scale.y > 1.05
	_check(saw_takeoff_squash, "takeoff squashes the body first")
	_check(saw_rise_stretch, "rising stretches the body")
	_check(visual.eye_style == VisualScript.EyeStyle.WIDE
			and visual.mouth_style == VisualScript.MouthStyle.OPEN,
			"rising shows the airborne expression")
	var saw_land_squash := false
	for i in 70:
		await get_tree().physics_frame
		saw_land_squash = saw_land_squash or visual.scale.y < 0.95
	_check(figure.is_on_floor() and animator.state == AnimatorScript.State.IDLE,
			"landing returns to IDLE")
	_check(saw_land_squash, "landing squashes the body")
	_check(visual.eye_style == eye_before
			and visual.eyebrow_style == brow_before
			and visual.mouth_style == mouth_before,
			"the authored face returns on the ground")

	# --- 4) abrupt movement-state flips stay smooth ------------------------
	figure.velocity = Vector2(240.0, 0.0)
	await _frames(5)
	figure.velocity = Vector2(-240.0, 0.0)
	await _frames(5)
	figure.velocity = Vector2(0.0, -420.0)
	animator.notify_jump()
	await _frames(20)
	figure.velocity = Vector2(0.0, 0.0)
	await _frames(60)
	_check(monitor.max_step < 0.09,
			"state flips change the transform smoothly (max step %.4f)"
			% monitor.max_step)

	# --- 5) face life + 6) configurable amplitude ---------------------------
	animator.blink_interval_min = 0.05
	animator.blink_interval_max = 0.05
	animator.blink_duration = 0.30
	animator.eye_dart_interval = 0.3
	var loud := AnimatorScript.new()
	var loud_visual: Control = VisualScript.new()
	loud_visual.position = Vector2(-32.0, -32.0)
	loud_visual.size = Vector2(64.0, 64.0)
	figure.add_child(loud_visual)
	figure.add_child(loud)
	loud.idle_breath_amount = 0.18
	loud.setup(figure, loud_visual)
	var saw_blink := false
	var saw_dart := false
	var loud_dev := 0.0
	var calm_dev := 0.0
	for i in 150:
		await get_tree().physics_frame
		saw_blink = saw_blink or visual.eye_open < 0.9
		saw_dart = saw_dart or visual.pupil_shift.length() > 0.05
		loud_dev = maxf(loud_dev, absf(loud_visual.scale.y - 1.0))
		calm_dev = maxf(calm_dev, absf(visual.scale.y - 1.0))
	_check(saw_blink, "blinking closes the eyes")
	_check(saw_dart, "idle glances move the pupils")
	_check(loud_dev > 0.10 and loud_dev > 2.0 * calm_dev,
			"idle amplitude is configurable (%.3f loud vs %.3f default)"
			% [loud_dev, calm_dev])

	# --- 7) every geometric silhouette --------------------------------------
	var host := CharacterBody2D.new()
	add_child(host)
	host.velocity = Vector2(0.0, -300.0)
	var shape_visuals: Array = []
	for shape_name in ["square", "circle", "triangle", "star", "ellipse"]:
		var shape_visual: Control = VisualScript.new()
		shape_visual.body_shape = shape_name
		shape_visual.position = Vector2(-32.0, -32.0)
		shape_visual.size = Vector2(64.0, 64.0)
		host.add_child(shape_visual)
		var shape_anim := AnimatorScript.new()
		host.add_child(shape_anim)
		shape_anim.setup(host, shape_visual)
		shape_visuals.append(shape_visual)
	await _frames(12)
	for shape_visual in shape_visuals:
		_check(is_instance_valid(shape_visual)
				and shape_visual.scale.y > 1.02
				and is_finite(shape_visual.scale.y),
				"the %s silhouette animates" % shape_visual.body_shape)

	if failures == 0:
		print("PASS: issue #558 procedural character animation")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
