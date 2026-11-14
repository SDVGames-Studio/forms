extends Node
## Regression check for issue #559: expressions + weapon visualization.
##
##  1. EXPRESSIONS: all six moods (NEUTRAL, ANGRY, FRIENDLY, CONFIDENT,
##     SCARED, SURPRISED) exist, each composes its own eye/eyebrow/mouth
##     configuration, and every composition differs from the others;
##  2. SIMPLE API: the enum property, set_expression with an enum, and
##     set_expression with case-insensitive names all restyle the face;
##     an unknown name changes NOTHING (the face keeps its look);
##  3. GAMEPLAY FACES: the animator keeps the visual's expression on the
##     ground, flash_expression overrides it for a moment (the damage
##     flinch), a charging weapon shows the ANGRY focus, and the airborne
##     face still wins mid-jump;
##  4. DAMAGE WIRING: Player.take_damage and Npc.take_damage feed the
##     SURPRISED flinch (source contract — the wiring is in place);
##  5. WEAPONS: the held weapon floats at HELD_ANCHOR along the aim and
##     rotates to the aim angle, independent of the body visual —
##     expression changes never move it — and the anchor sits outside
##     the face zone (±16 px of the 64 px reference body);
##  6. PURE VISUAL: expressions never touch the figure's physics — its
##     position, velocity and collision transform stay put while the
##     face changes.
##
## Run headless: godot --headless res://tests/test_issue559.tscn
## Exit code 0 = pass.

const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")
const AnimatorScript := preload("res://scripts/CharacterAnimator.gd")
const WeaponScript := preload("res://scripts/Weapon.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## Minimal stand-in for Player/Npc: the gravity-frame accessors the real
## figures expose plus aim_dir for the Weapon (the same surface Player
## and Npc give their Weapon child in game).
class TestFigure extends CharacterBody2D:
	func current_gravity() -> Vector2:
		return Vector2.DOWN

	func current_tangent() -> Vector2:
		return Vector2.RIGHT

	func aim_dir(facing: float, _legacy_sign: float = 1.0) -> Vector2:
		return Vector2(facing, 0.0)

	func _physics_process(delta: float) -> void:
		if not is_on_floor():
			velocity += Vector2.DOWN * 980.0 * delta
		move_and_slide()


func _triple(face: Control) -> Array:
	return [face.eye_style, face.eyebrow_style, face.mouth_style]


func _features(key: int) -> Array:
	var f: Dictionary = VisualScript.EXPRESSION_FEATURES[key]
	return [f["eye"], f["brow"], f["mouth"]]


func _first_color_rect(of: Node) -> ColorRect:
	for child in of.get_children():
		var rect := child as ColorRect
		if rect != null:
			return rect
	return null


func _ready() -> void:
	# --- 1) the expression set ------------------------------------------
	var names: Array = VisualScript.ExpressionType.keys()
	_check(names.has("NEUTRAL") and names.has("ANGRY")
			and names.has("FRIENDLY") and names.has("CONFIDENT")
			and names.has("SCARED") and names.has("SURPRISED"),
			"all six required expressions exist")
	var seen: Array = []
	for key in VisualScript.EXPRESSION_FEATURES:
		var triple := _features(key)
		_check(not seen.has(triple),
				"expression %s composes a unique configuration" % key)
		seen.append(triple)

	var face: Control = VisualScript.new()
	face.size = Vector2(64, 64)
	add_child(face)
	for key in VisualScript.EXPRESSION_FEATURES:
		face.set_expression(key)
		_check(_triple(face) == _features(key),
				"set_expression(%s) applies its composition" % key)
		_check(face.expression == key and face.has_expression(),
				"set_expression(%s) tracks the current expression" % key)

	# --- 2) the simple API ----------------------------------------------
	face.expression = VisualScript.ExpressionType.ANGRY
	_check(_triple(face) == _features(VisualScript.ExpressionType.ANGRY),
			"the exported property restyles the face")
	face.set_expression("confident")
	_check(_triple(face) == _features(VisualScript.ExpressionType.CONFIDENT),
			"set_expression takes lowercase names")
	face.set_expression("SCARED")
	_check(_triple(face) == _features(VisualScript.ExpressionType.SCARED),
			"set_expression takes uppercase names")
	face.set_expression("Surprised")
	_check(_triple(face) == _features(VisualScript.ExpressionType.SURPRISED),
			"set_expression takes mixed-case names")
	face.set_expression("grumpy")
	_check(_triple(face) == _features(VisualScript.ExpressionType.SURPRISED),
			"an unknown name changes nothing")

	# --- 3) gameplay faces through the animator --------------------------
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(2000, 40)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(0, 20)
	add_child(floor_body)

	var figure := TestFigure.new()
	var shape := CollisionShape2D.new()
	var body_rect := RectangleShape2D.new()
	body_rect.size = Vector2(64, 64)
	shape.shape = body_rect
	figure.add_child(shape)
	figure.position = Vector2(0, -32)
	add_child(figure)
	var weapon = WeaponScript.new()
	weapon.name = "Weapon"  # the in-game child name the animator polls
	figure.add_child(weapon)
	weapon.selected_weapon = 3  # spear — the longest classical style
	face.reparent(figure)
	var animator = AnimatorScript.new()
	figure.add_child(animator)
	animator.setup(figure, face)

	for i in 6:
		await get_tree().physics_frame
	_check(figure.is_on_floor(), "the test figure rests on the floor")

	face.set_expression("FRIENDLY")
	for i in 6:
		await get_tree().process_frame
	_check(_triple(face) == _features(VisualScript.ExpressionType.FRIENDLY),
			"the grounded face follows the visual's expression")

	animator.flash_expression("SURPRISED", 0.5)
	for i in 6:
		await get_tree().process_frame
	_check(_triple(face) == _features(VisualScript.ExpressionType.SURPRISED),
			"flash_expression overrides the face for its duration")
	await get_tree().create_timer(0.8).timeout
	for i in 3:
		await get_tree().process_frame
	_check(_triple(face) == _features(VisualScript.ExpressionType.FRIENDLY),
			"the resting expression returns when the flash expires")

	# Test-only: force the charge state (the input path needs the full
	# turn machinery); is_charging is the public read the animator uses.
	weapon._charging = true
	_check(weapon.is_charging(), "is_charging exposes the charge state")
	for i in 6:
		await get_tree().process_frame
	_check(_triple(face) == _features(VisualScript.ExpressionType.ANGRY),
			"a charging weapon shows the angry focus face")
	weapon._charging = false
	for i in 6:
		await get_tree().process_frame
	_check(_triple(face) == _features(VisualScript.ExpressionType.FRIENDLY),
			"the resting expression returns after the charge")

	# Airborne still wins: jump, and the mid-air face takes over.
	figure.velocity = Vector2(0, -420)
	await get_tree().create_timer(0.15).timeout
	for i in 3:
		await get_tree().process_frame
	_check(_triple(face) == _features(VisualScript.ExpressionType.SURPRISED)
			or _triple(face) == [VisualScript.EyeStyle.WIDE,
					VisualScript.EyebrowStyle.WORRIED,
					VisualScript.MouthStyle.FROWN],
			"the airborne face overrides the expression mid-jump")
	await get_tree().create_timer(1.2).timeout
	for i in 4:
		await get_tree().process_frame
	_check(figure.is_on_floor(),
			"the figure lands again after the jump")
	_check(_triple(face) == _features(VisualScript.ExpressionType.FRIENDLY),
			"the resting expression returns after landing")

	# --- 4) the damage wiring contract -----------------------------------
	var player_src := FileAccess.get_file_as_string("res://scripts/Player.gd")
	_check(player_src.contains("_animator.flash_expression(\"SURPRISED\""),
			"Player.take_damage flashes the SURPRISED flinch")
	var npc_src := FileAccess.get_file_as_string("res://scripts/Npc.gd")
	_check(npc_src.contains("_animator.flash_expression(\"SURPRISED\""),
			"Npc.take_damage flashes the SURPRISED flinch")

	# --- 5) weapon independence ------------------------------------------
	var held := _first_color_rect(weapon)
	_check(held != null, "the weapon holds a drawn weapon rect")
	var style: Dictionary = WeaponScript.HELD_STYLES[3]
	var aim_pos: Vector2 = Vector2.RIGHT * float(WeaponScript.HELD_ANCHOR) \
			- style["size"] / 2.0
	_check(held.position.distance_to(aim_pos) < 0.01,
			"the held weapon floats at HELD_ANCHOR along the aim")
	_check(is_equal_approx(held.rotation, 0.0),
			"the held weapon rotates to the aim angle")
	_check(float(WeaponScript.HELD_ANCHOR) >= 32.0,
			"the weapon anchor sits outside the ±16 px face zone")

	var held_before := held.position
	var rot_before := held.rotation
	face.set_expression("ANGRY")
	face.set_expression("SCARED")
	for i in 4:
		await get_tree().process_frame
	_check(held.position == held_before and held.rotation == rot_before,
			"expression changes never move the weapon")

	# Facing flip: the weapon mirrors to the other side, aim rotation
	# follows — position/rotation stay aim-driven, never face-driven.
	figure.velocity = Vector2(-120, 0)
	for i in 12:
		await get_tree().physics_frame
	figure.velocity = Vector2.ZERO
	var mirrored: Vector2 = Vector2.LEFT * float(WeaponScript.HELD_ANCHOR) \
			- style["size"] / 2.0
	_check(held.position.distance_to(mirrored) < 0.01
			and is_equal_approx(absf(held.rotation), PI),
			"the weapon mirrors and rotates with the facing aim")

	# --- 6) expressions are purely visual --------------------------------
	_check(figure.position.x < 0.0,
			"the walk check really moved the figure leftwards")
	face.set_expression("CONFIDENT")
	for i in 4:
		await get_tree().process_frame
	_check(shape.position == Vector2.ZERO
			and shape.rotation == 0.0,
			"the collision transform never moves with expressions")
	_check(figure.velocity == Vector2.ZERO,
			"expressions never write the figure's velocity")

	# A frame so every queued draw pass really runs headless.
	for i in 3:
		await get_tree().process_frame
	_check(is_instance_valid(face) and is_instance_valid(figure),
			"the draw pass leaves every instance alive")

	if failures == 0:
		print("PASS: issue #559 expressions + weapon visualization")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
