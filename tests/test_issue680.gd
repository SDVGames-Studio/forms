extends Node
## Regression check for issue #680 (roadmap part 1 — weapon art
## prototype): the rocket launcher renders as a hand-drawn cartoon
## sprite while every gameplay number stays exactly as it was.
##
##  1. STYLE: the rocket's HELD_STYLES entry carries the launcher
##     texture at the exaggerated in-game size (readable next to the
##     48 px body) and the sprite is wired to render instead of the
##     plain ColorRect;
##  2. AIM: the sprite's rotation follows the aim axis both ways —
##     right (no flip) and left (flip_v keeps the grip below the
##     tube), so aiming stays independent of the artwork. Rework
##     (owner 2026-11-23): the launcher also rides LOWER — its height
##     along the wielder's stance-gravity axis is damped toward the
##     body's vertical middle plus a fixed drop, flat AND tilted
##     stances;
##  3. MECHANICS: the rocket's speed, damage, quota and the spawned
##     rigid body are byte-for-byte the pre-#680 values — the sprite
##     is visual only.
##
## Run headless: godot --headless res://tests/test_issue680.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")

## Weapon slot order (Weapon.gd): 1 = rocket.
const WEAPON_SLOT_ROCKET := 1

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A shooter whose aim_dir answers the test's live aim vector. The
## optional stance gravity (default: straight down) answers
## current_gravity() the way Character does.
class AimShooter:
	extends CharacterBody2D
	var aim := Vector2(1, 0)
	var grav := Vector2.DOWN
	func aim_dir(_facing: float, _grav: float = 1.0) -> Vector2:
		return aim
	func current_gravity() -> Vector2:
		return grav


func _make_weapon(aim: Vector2) -> Node2D:
	var shooter := AimShooter.new()
	shooter.aim = aim
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


## Rigid bodies currently parented to this test root (the weapon spawns
## them into its parent's parent, which is this node).
func _spawned_bodies() -> Array:
	var out: Array = []
	for child in get_children():
		if child.get_script() == ProjectileBodyScript:
			out.append(child)
	return out


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Style: the rocket renders through the launcher sprite.
	var style: Dictionary = WeaponScript.HELD_STYLES[WEAPON_SLOT_ROCKET]
	_check(style.has("texture"),
			"the rocket style must carry the launcher texture (#680)")
	_check(style["size"] == Vector2(52, 20),
			"the launcher sprite must sit at the authored in-game size (got %s)"
			% style["size"])
	if style.has("texture"):
		var tex: Texture2D = style["texture"]
		_check(tex != null and tex.get_width() == 208 and tex.get_height() == 80,
				"the launcher texture must load at its authored 208x80")

	# The sprite is wired: textured style shows the Sprite2D, not the rect.
	var gun := _make_weapon(Vector2(1, 0))
	gun.selected_weapon = WEAPON_SLOT_ROCKET
	gun._update_held()
	_check(gun._held_sprite.texture != null,
			"the held Sprite2D must carry the launcher texture")
	_check(absf(gun._held_sprite.scale.x - 0.25) < 0.001
			and absf(gun._held_sprite.scale.y - 0.25) < 0.001,
			"the 208x80 texture must scale to the 52x20 in-game size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect must stay hidden for the textured style")
	gun.get_parent().queue_free()
	await get_tree().physics_frame

	# 2) Aim: the sprite rides the aim axis — right, then left (flip_v).
	var aimer := _make_weapon(Vector2(1, 0))
	aimer.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(wrapf(aimer._held_sprite.rotation, -PI, PI)) < 0.01,
			"aiming right must keep the sprite on the aim axis (got %s rad)"
			% aimer._held_sprite.rotation)
	_check(not aimer._held_sprite.flip_v,
			"aiming right must not flip the launcher")
	_check(aimer._held_sprite.position.length() >= WeaponScript.HELD_ANCHOR - 0.5,
			"the sprite must float at the held anchor, clear of the body")
	# Issue #680 rework (owner 2026-11-23): the launcher sits LOWER —
	# at a flat horizontal aim its height is exactly the fixed drop
	# below the stance mid line, not the old on-axis anchor.
	_check(absf(aimer._held_sprite.position.x - WeaponScript.HELD_ANCHOR) < 0.1,
			"the horizontal reach must stay at the held anchor (got %s)"
			% aimer._held_sprite.position.x)
	_check(absf(aimer._held_sprite.position.y - WeaponScript.HELD_SPRITE_DROP) < 0.1,
			"a flat aim must drop the launcher below the mid line (got %s)"
			% aimer._held_sprite.position.y)
	# Aiming 45 degrees up: the old anchor lifted the launcher 22.6 px
	# along gravity; the rework keeps it within a few px of the body's
	# vertical middle (lift * LIFT_KEEP - DROP = 9.05 - 6 = 3.05 up).
	(aimer.get_parent() as AimShooter).aim = Vector2(1, -1).normalized()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lifted: float = -aimer._held_sprite.position.dot(Vector2.DOWN)
	_check(absf(lifted - (WeaponScript.HELD_ANCHOR * sqrt(0.5)
				* WeaponScript.HELD_SPRITE_LIFT_KEEP
				- WeaponScript.HELD_SPRITE_DROP)) < 0.1,
			"an aimed-up launcher must stay near the vertical middle (got %s px up)"
			% lifted)
	_check(lifted < WeaponScript.HELD_ANCHOR * 0.25,
			"the damped lift must stay far below the raw anchor lift")
	# A TILTED stance (gravity down-right 45 degrees) drops along the
	# stance axis, not the world axis: height along stance gravity is
	# lift * LIFT_KEEP - DROP with lift = anchor . (up-along-stance).
	(aimer.get_parent() as AimShooter).aim = Vector2(1, 0)
	(aimer.get_parent() as AimShooter).grav = Vector2(1, 1).normalized()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var stance_g := (aimer.get_parent() as AimShooter).grav
	var stance_h: float = -aimer._held_sprite.position.dot(stance_g)
	_check(absf(stance_h - (-WeaponScript.HELD_ANCHOR * sqrt(0.5)
				* WeaponScript.HELD_SPRITE_LIFT_KEEP
				- WeaponScript.HELD_SPRITE_DROP)) < 0.1,
			"a tilted stance must measure the drop along the stance axis (got %s)"
			% stance_h)
	(aimer.get_parent() as AimShooter).grav = Vector2.DOWN
	(aimer.get_parent() as AimShooter).aim = Vector2(-1, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(absf(wrapf(aimer._held_sprite.rotation, -PI, PI)) - PI) < 0.01,
			"aiming left must rotate the sprite onto the aim axis (got %s rad)"
			% aimer._held_sprite.rotation)
	_check(aimer._held_sprite.flip_v,
			"aiming left must flip the launcher so the grip stays below")
	aimer.get_parent().queue_free()
	await get_tree().physics_frame

	# 3) Mechanics: every rocket number is the pre-#680 value.
	_check(WeaponScript.ROCKET_SPEED == 700.0,
			"the rocket speed must stay 700 px/s")
	_check(WeaponScript.ROCKET_DAMAGE == 35,
			"the rocket damage must stay 35")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_ROCKET] == 1,
			"the rocket keeps its single shot per turn")
	var shooter2 := _make_weapon(Vector2(1, 0))
	shooter2.selected_weapon = WEAPON_SLOT_ROCKET
	shooter2._fire_rocket(1.0)
	var bodies := _spawned_bodies()
	_check(bodies.size() == 1,
			"one rocket launch must spawn exactly one rigid body (got %d)"
			% bodies.size())
	if bodies.size() == 1:
		var rocket: RigidBody2D = bodies[0]
		_check(rocket.kind == ProjectileBodyScript.Kind.ROCKET,
				"the spawned body must be the ROCKET kind")
		_check(rocket.launch_velocity == Vector2(700.0, 0.0),
				"the rocket must launch dead straight at full power (got %s)"
				% rocket.launch_velocity)
		_check(rocket.damage == 35 and rocket.blast_radius == 90.0,
				"the rocket keeps its damage and blast radius")
		rocket.queue_free()
	shooter2.get_parent().queue_free()

	# The other weapons keep their plain rectangle fills.
	for slot in WeaponScript.HELD_STYLES.size():
		if slot == WEAPON_SLOT_ROCKET:
			continue
		_check(not WeaponScript.HELD_STYLES[slot].has("texture"),
				"slot %d must keep its plain rectangle fill (#680 only touches the rocket)"
				% slot)

	if failures > 0:
		push_error("issue #680 test: %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("issue #680 test: all checks passed")
	get_tree().quit(0)
