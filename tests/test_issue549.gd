extends Node
## Regression check for issue #549: a figure struck by the baseball bat
## moves like a projectile.
##
##  1. IMPULSE + LIFT: the launch is ONE initial velocity along the shot
##     direction (the full BAT_KNOCKBACK_SPEED at a full charge) with at
##     least BAT_MIN_LIFT of the launch speed pointing against gravity —
##     a perfectly flat aim still pops the victim off the floor;
##  2. GRAVITY: the level's gravity accelerates the flight every tick —
##     the along-gravity velocity component grows monotonically while
##     the aimed impulse stays, so the constant straight-line shove of
##     the old #527 knockback is gone;
##  3. BOUNDED: the flight (and its turn-effect gate) ends — a plain
##     Node2D stand-in has no floor contact to land on, so it rides the
##     BAT_FLIGHT_CAP safety limit to the end and then stops moving.
##
## Run headless: godot --headless res://tests/test_issue549.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const Stats := preload("res://scripts/CharacterStats.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A stand-in victim: plain Node2D with health + take_damage + velocity,
## so the bat's push takes the direct-offset branch (deterministic in
## headless tests — no physics shapes needed). The test scene has no
## gravity sources, so LevelTerrain's default DOWN gravity applies.
class FakeFigure extends Node2D:
	var health := 100
	var velocity := Vector2.ZERO

	func take_damage(damage: int) -> void:
		health -= damage


func _make_weapon() -> Node2D:
	var shooter := Node2D.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	var gun := _make_weapon()
	var victim := FakeFigure.new()
	victim.position = Vector2(60.0, 0.0)  # ahead along the aim (1, 0)
	add_child(victim)
	victim.add_to_group("enemy_team")
	gun._swing_bat(1.0)
	# Issue #721 rework: the strike lands at the forward sweep's peak —
	# wait out the wind-up so the flight below starts from its first
	# physics tick exactly as before (the strike is ~20 frames in).
	for i in 30:
		await get_tree().physics_frame
		if gun._bat_push_left > 0.0:
			break
	_check(victim.health == 100 - WeaponScript.BAT_DAMAGE,
			"the swing must still damage the figure it reaches")

	# 1) The launch impulse after its FIRST physics tick: full aim along
	# +x plus the guaranteed lift, already bent by one tick of gravity.
	await get_tree().physics_frame
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var expected := Vector2(WeaponScript.BAT_KNOCKBACK_SPEED,
			-WeaponScript.BAT_KNOCKBACK_SPEED * WeaponScript.BAT_MIN_LIFT
			+ Stats.GRAVITY * dt)
	_check(victim.velocity.distance_to(expected) < 1.0,
			"the launch must be the aimed impulse plus the lift and one tick of gravity (got %s, want %s)"
			% [victim.velocity, expected])

	# 2) Gravity keeps accelerating the flight downward — the velocity
	# sample two frames later has grown by two more gravity steps, while
	# the aimed impulse is untouched (gravity bends the arc, it does not
	# eat the launch).
	var vy1 := victim.velocity.y
	await get_tree().physics_frame
	await get_tree().physics_frame
	var vy2 := victim.velocity.y
	_check(vy2 > vy1 + Stats.GRAVITY * dt,
			"gravity must accelerate the flight downward (%f then %f)"
			% [vy1, vy2])
	_check(absf(victim.velocity.x - expected.x) < 1.0,
			"the aimed impulse must survive the arc (vx=%f)"
			% victim.velocity.x)
	_check(victim.position.y < 0.0,
			"the victim must have risen against gravity on the arc (y=%f)"
			% victim.position.y)

	# 3) Bounded: no floor for a Node2D stand-in — the BAT_FLIGHT_CAP
	# ends the flight and releases the turn-effect gate, and the body
	# stops being pushed.
	for i in int(WeaponScript.BAT_FLIGHT_CAP * 60.0) + 5:
		await get_tree().physics_frame
		if gun._bat_push_left <= 0.0:
			break
	await get_tree().physics_frame
	_check(gun._bat_push_left == 0.0,
			"the ballistic flight must end at the BAT_FLIGHT_CAP")
	_check(get_tree().get_nodes_in_group(TurnController.EFFECT_GROUP).is_empty(),
			"the turn-effect gate must be released once the flight ends")
	var settled := victim.position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(victim.position.distance_to(settled) < 0.001,
			"the victim stops being pushed once the flight ended")

	if failures == 0:
		print("PASS: issue #549 ballistic bat knockback")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
