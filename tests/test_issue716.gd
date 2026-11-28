extends Node
## Regression check for issue #716 (Weapon Visual Redesign 3a — idle &
## aim weapon motion, sub-issue of the #680 roadmap).
##
##  1. FOLLOW-THROUGH: a swung aim leaves the DRAWN weapon angle briefly
##     behind the live aim and then converges back onto the axis — while
##     the hold POSITION and _aim() answer the TRUE aim from the first
##     tick (aiming stays pixel-accurate; no visual offset feeds back).
##  2. IDLE BREATHING: a settled wielder (standing still, steady aim)
##     gets a gentle bob along the STANCE-GRAVITY axis — bounded by
##     IDLE_AMPLITUDE, periodic (no drift), zero leak onto the tangent.
##  3. SUPPRESSION: the settle delay holds the bob off right after the
##     weapon is taken; a walk command or a re-aim resets the settle
##     clock and the bob fades back out.
##  4. COMPOSITION: the #715 recoil still kicks and recovers exactly on
##     top of the idle layer.
##
## Run headless: godot --headless res://tests/test_issue716.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const WeaponVisualsScript := preload("res://scripts/WeaponVisuals.gd")

## Weapon slot order (Weapon.gd): 1 = rocket (a textured style, so both
## the ColorRect and the Sprite2D paths are exercised).
const WEAPON_SLOT_ROCKET := 1

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A shooter whose aim_dir answers the test's live aim vector, with a
## commandable walk signal (issue #700: 0.0 = planted) and stance
## gravity, answering the Character accessors Weapon reads.
class AimShooter:
	extends CharacterBody2D
	var aim := Vector2(1, 0)
	var grav := Vector2.DOWN
	var walk := 0.0
	func aim_dir(_facing: float, _grav: float = 1.0) -> Vector2:
		return aim
	func current_gravity() -> Vector2:
		return grav
	func walk_command() -> float:
		return walk


func _make_weapon(aim: Vector2) -> Node2D:
	var shooter := AimShooter.new()
	shooter.aim = aim
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Tuning: the idle/follow constants stay subtle and readable.
	_check(WeaponScript.IDLE_AMPLITUDE > 0.0
				and WeaponScript.IDLE_AMPLITUDE <= 3.0,
			"the idle bob must stay subtle (got %s px)"
			% WeaponScript.IDLE_AMPLITUDE)
	_check(WeaponScript.IDLE_PERIOD >= 1.0
				and WeaponScript.IDLE_PERIOD <= 5.0,
			"the idle bob must breathe at a calm pace (got %s s)"
			% WeaponScript.IDLE_PERIOD)
	_check(WeaponScript.IDLE_SETTLE_DELAY >= 0.5,
			"the settle delay must let an acting figure track exactly first (got %s s)"
			% WeaponScript.IDLE_SETTLE_DELAY)
	_check(WeaponScript.AIM_FOLLOW_RATE >= 5.0
				and WeaponScript.AIM_FOLLOW_RATE <= 40.0,
			"the follow-through must be slight (got %s 1/s)"
			% WeaponScript.AIM_FOLLOW_RATE)
	_check(WeaponScript.RECOIL_TIME == 0.28,
			"#715's recoil timing must be untouched by #716 (got %s)"
			% WeaponScript.RECOIL_TIME)

	# 2) FOLLOW-THROUGH: swing the aim; the drawn angle trails briefly
	# and converges; the hold position and _aim() stay exact throughout.
	var aimer := _make_weapon(Vector2(1, 0))
	aimer.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(wrapf(aimer._held_sprite.rotation, -PI, PI)) < 0.01,
			"a freshly held weapon snaps onto the aim axis (got %s rad)"
			% aimer._held_sprite.rotation)
	(aimer.get_parent() as AimShooter).aim = Vector2(-1, 0)
	await get_tree().physics_frame
	var mid_rot: float = wrapf(aimer._held_sprite.rotation, -PI, PI)
	_check(absf(mid_rot) > 0.2 and absf(mid_rot) < 2.9,
			"one tick after the swing the drawn angle must TRAIL the aim (got %s rad)"
			% mid_rot)
	_check(aimer._aim() == Vector2(-1, 0),
			"the LIVE aim must answer the new direction immediately, pixel-accurate (got %s)"
			% aimer._aim())
	var rocket_anchor := WeaponVisualsScript.anchor(WEAPON_SLOT_ROCKET)
	_check(absf(aimer._held_sprite.position.x - (-rocket_anchor)) < 0.1,
			"the hold position must ride the TRUE aim from the first tick (got %s)"
			% aimer._held_sprite.position.x)
	for i in 45:
		await get_tree().physics_frame
	_check(absf(absf(wrapf(aimer._held_sprite.rotation, -PI, PI)) - PI) < 0.01,
			"the drawn angle must converge back onto the aim axis (got %s rad)"
			% aimer._held_sprite.rotation)
	_check(aimer._held_sprite.flip_v,
			"aiming left must still flip the grip below the barrel")
	aimer.get_parent().queue_free()
	await get_tree().physics_frame

	# 3) IDLE BREATHING: settle a still wielder in, then sample the bob.
	var rocket_drop := WeaponVisualsScript.drop(WEAPON_SLOT_ROCKET)
	var hold := Vector2(rocket_anchor, rocket_drop)
	var holder := _make_weapon(Vector2(1, 0))
	holder.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	# The settle delay itself: the first seconds after taking the weapon
	# track exactly (no bob).
	for i in 40:
		await get_tree().physics_frame
	_check(holder._idle_amount == 0.0,
			"the settle delay must hold the bob off at first (got %s)"
			% holder._idle_amount)
	_check(holder._held_sprite.position.distance_to(hold) < 0.1,
			"before settling the weapon must hold exactly (got %s)"
			% holder._held_sprite.position)
	# Jump-start the settle clock (the natural 1.5 s path is proven
	# above); the fade-in itself is still real.
	holder._still_for = 10.0
	for i in 55:
		await get_tree().physics_frame
	_check(absf(holder._idle_amount - 1.0) < 0.001,
			"the bob must be fully faded in once settled (got %s)"
			% holder._idle_amount)
	var max_off := 0.0
	var min_off := 0.0
	var tangent_leak := 0.0
	var offsets: Array = []
	for i in 170:
		await get_tree().physics_frame
		var off: Vector2 = holder._held_sprite.position - hold
		offsets.append(off)
		max_off = maxf(max_off, off.y)
		min_off = minf(min_off, off.y)
		# The bob is purely along the stance-gravity axis (world Y in
		# this flat stance): no leak onto the aim/tangent axis.
		tangent_leak = maxf(tangent_leak, absf(off.x))
	_check(max_off > 0.5 and min_off < -0.5,
			"the settled weapon must visibly breathe (max %s, min %s px)"
			% [max_off, min_off])
	_check(maxf(absf(max_off), absf(min_off))
				<= WeaponScript.IDLE_AMPLITUDE + 0.25,
			"the bob must stay bounded by the amplitude (max %s px)"
			% maxf(absf(max_off), absf(min_off)))
	_check(tangent_leak < 0.1,
			"the bob must not leak onto the aim axis (leaked %s px)"
			% tangent_leak)
	# No drift: the offset is periodic — one IDLE_PERIOD (156 frames at
	# 60 Hz) later the same phase returns the same offset.
	var frame_period := int(round(WeaponScript.IDLE_PERIOD * 60.0))
	_check(frame_period < offsets.size(),
			"the sample window must cover a full idle period")
	var phase_a: Vector2 = offsets[10]
	var phase_b: Vector2 = offsets[10 + frame_period]
	_check(phase_a.distance_to(phase_b) < 0.08,
			"the bob must be periodic — no accumulated drift (spread %s)"
			% phase_a.distance_to(phase_b))
	# While settled with a steady aim the drawn angle stays on the axis.
	_check(absf(wrapf(holder._held_sprite.rotation, -PI, PI)) < 0.01,
			"breathing must not swing the drawn angle (got %s rad)"
			% holder._held_sprite.rotation)
	holder.get_parent().queue_free()
	await get_tree().physics_frame

	# 4) SUPPRESSION: a walk command resets the settle clock and the bob
	# fades back out; so does a re-aim.
	var mover := _make_weapon(Vector2(1, 0))
	mover.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	mover._still_for = 10.0
	for i in 55:
		await get_tree().physics_frame
	var spread_before := 0.0
	for i in 60:
		await get_tree().physics_frame
		var off: Vector2 = mover._held_sprite.position - hold
		spread_before = maxf(spread_before, absf(off.y))
	_check(spread_before > 0.5,
			"sanity: the mover breathes before walking (spread %s px)"
			% spread_before)
	(mover.get_parent() as AimShooter).walk = 1.0
	await get_tree().physics_frame
	_check(mover._still_for == 0.0,
			"a walk command must reset the settle clock (got %s)"
			% mover._still_for)
	for i in 55:
		await get_tree().physics_frame
	var spread_after := 0.0
	for i in 60:
		await get_tree().physics_frame
		var off2: Vector2 = mover._held_sprite.position - hold
		spread_after = maxf(spread_after, absf(off2.y))
	_check(spread_after < 0.15,
			"walking must fade the bob back out (spread %s px)"
			% spread_after)
	# A re-aim resets it too.
	(mover.get_parent() as AimShooter).walk = 0.0
	mover._still_for = 10.0
	for i in 55:
		await get_tree().physics_frame
	_check(mover._idle_amount > 0.99,
			"re-settled after the walk (got %s)" % mover._idle_amount)
	(mover.get_parent() as AimShooter).aim = Vector2(0, -1)
	await get_tree().physics_frame
	_check(mover._still_for < 0.05,
			"a re-aim must reset the settle clock (got %s)"
			% mover._still_for)
	for i in 40:
		await get_tree().physics_frame
	_check(mover._idle_amount < 0.2,
			"the bob must fade out after a re-aim (got %s)"
			% mover._idle_amount)
	mover.get_parent().queue_free()
	await get_tree().physics_frame

	# 5) TILTED STANCE: the bob rides the STANCE-gravity axis, not the
	# world axis.
	var tilted := _make_weapon(Vector2(1, 0))
	tilted.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	(tilted.get_parent() as AimShooter).grav = Vector2(1, 1).normalized()
	tilted._still_for = 10.0
	for i in 55:
		await get_tree().physics_frame
	var stance_g: Vector2 = (tilted.get_parent() as AimShooter).grav
	var stance_t := Vector2(-stance_g.y, stance_g.x)
	var anchor_vec := Vector2(rocket_anchor, 0.0)
	var lift := -anchor_vec.dot(stance_g)
	var hold_tilted := anchor_vec + stance_g * (lift
			* (1.0 - WeaponVisualsScript.lift_keep(WEAPON_SLOT_ROCKET))
			+ rocket_drop)
	var axis_off := 0.0
	var stance_leak := 0.0
	for i in 170:
		await get_tree().physics_frame
		var off: Vector2 = tilted._held_sprite.position - hold_tilted
		axis_off = maxf(axis_off, absf(off.dot(stance_g)))
		stance_leak = maxf(stance_leak, absf(off.dot(stance_t)))
	_check(axis_off > 0.5,
			"a tilted stance must still breathe along its own gravity axis (spread %s px)"
			% axis_off)
	_check(axis_off <= WeaponScript.IDLE_AMPLITUDE + 0.25,
			"the tilted bob must stay bounded (got %s px)" % axis_off)
	_check(stance_leak < 0.1,
			"the tilted bob must not leak onto the stance tangent (leaked %s px)"
			% stance_leak)
	tilted.get_parent().queue_free()
	await get_tree().physics_frame

	# 6) COMPOSITION: the #715 recoil still kicks and recovers exactly on
	# top of the idle layer (the bob only ever offsets the stance axis).
	var kicker := _make_weapon(Vector2(1, 0))
	kicker.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	kicker._still_for = 10.0
	for i in 55:
		await get_tree().physics_frame
	kicker._recoil_t = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var kicked: float = rocket_anchor - kicker._held_sprite.position.x
	_check(kicked > 4.0,
			"the recoil kick must still land on top of the idle layer (got %.1f px)"
			% kicked)
	for i in 22:
		await get_tree().physics_frame
	_check(absf(kicker._held_sprite.position.x - rocket_anchor) < 0.1,
			"the recoil must recover exactly along the aim axis (got %s)"
			% kicker._held_sprite.position.x)
	_check(absf(kicker._held_sprite.position.y - rocket_drop)
				<= WeaponScript.IDLE_AMPLITUDE + 0.25,
			"the recovered hold must sit inside the idle envelope (off %s px)"
			% absf(kicker._held_sprite.position.y - rocket_drop))
	kicker.get_parent().queue_free()
	await get_tree().physics_frame

	if failures > 0:
		push_error("issue #716 test: %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("issue #716 test: all checks passed")
	get_tree().quit(0)
