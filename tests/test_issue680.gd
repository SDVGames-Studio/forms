extends Node
## Regression check for issue #680 (weapon visual redesign roadmap).
##
##  PART 1 (prototype): the rocket launcher renders as a hand-drawn
##  cartoon sprite while every gameplay number stays exactly as it was.
##  PART 2 (reusable system): every held-weapon visual now lives in the
##  WeaponVisuals registry as data — per-weapon sprite, size and hold
##  position — and the shotgun joins as the SECOND cartoon weapon with
##  its own sprite and its own hold, proving art swaps touch no weapon
##  logic. Owner rework 2026-11-24 ("a little lower"): the launcher's
##  hold sits lower than the 2026-11-23 tuning.
##  PART 3 (animations/effects, first slice): recoil — every committed
##  shot kicks the held visual back along the aim and recovers, the
##  magnitude per-weapon in the registry (0 for melee styles) — plus a
##  cartoon MUZZLE FLASH (bold outline starburst, code-drawn) that pops
##  at the barrel, aimed along the shot, and frees itself.
##
##  1. REGISTRY: WeaponVisuals.STYLES is the single visual table — the
##     rocket and shotgun entries carry textures with per-weapon
##     anchor/lift_keep/drop, every other slot stays a plain rectangle;
##  2. STYLE: both sprites load at their authored sizes and are wired
##     to render instead of the plain ColorRect fills;
##  3. AIM/HOLD: the sprite's rotation follows the aim axis both ways
##     (flip_v keeps the grip below), and each weapon's hold position
##     comes from ITS OWN registry values (flat, aimed-up, tilted
##     stance), the launcher measurably LOWER than the 2026-11-23
##     rework values;
##  4. MECHANICS: the rocket's and the shotgun's speeds, damages,
##     quotas and spawned bodies are byte-for-byte the pre-#680 values
##     — the sprites are visual only.
##
## Run headless: godot --headless res://tests/test_issue680.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const WeaponVisualsScript := preload("res://scripts/WeaponVisuals.gd")
const ProjectileScript := preload("res://scripts/Projectile.gd")
const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")

## Weapon slot order (Weapon.gd): 0 = shotgun, 1 = rocket.
const WEAPON_SLOT_SHOTGUN := 0
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


## Plain pellet projectiles currently parented to this test root.
func _spawned_pellets() -> Array:
	var out: Array = []
	for child in get_children():
		if child.get_script() == ProjectileScript:
			out.append(child)
	return out


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Registry: the visual table moved out of Weapon.gd and carries
	# per-weapon hold config on the textured entries.
	_check(WeaponScript.HELD_STYLES == WeaponVisualsScript.STYLES,
			"Weapon.gd must consume the WeaponVisuals registry (part 2)")
	var rocket_style: Dictionary = WeaponVisualsScript.STYLES[WEAPON_SLOT_ROCKET]
	var shotgun_style: Dictionary = WeaponVisualsScript.STYLES[WEAPON_SLOT_SHOTGUN]
	_check(rocket_style.has("texture") and shotgun_style.has("texture"),
			"the rocket and shotgun styles must carry their sprites")
	_check(WeaponVisualsScript.textured(WEAPON_SLOT_ROCKET)
			and WeaponVisualsScript.textured(WEAPON_SLOT_SHOTGUN),
			"the registry must report both styles textured")
	# Per-weapon positioning: each textured entry tunes its own hold.
	_check(WeaponVisualsScript.anchor(WEAPON_SLOT_SHOTGUN)
			!= WeaponVisualsScript.anchor(WEAPON_SLOT_ROCKET),
			"the shotgun and rocket must carry DIFFERENT per-weapon anchors")
	_check(absf(WeaponVisualsScript.anchor(WEAPON_SLOT_SHOTGUN)
				- WeaponVisualsScript.STYLES[WEAPON_SLOT_SHOTGUN]["anchor"]) < 0.001
			and absf(WeaponVisualsScript.drop(WEAPON_SLOT_SHOTGUN)
				- WeaponVisualsScript.STYLES[WEAPON_SLOT_SHOTGUN]["drop"]) < 0.001,
			"the registry helpers must return the entry's own hold values")
	# Plain slots resolve to the shared defaults (the #559 anchor).
	_check(absf(WeaponVisualsScript.anchor(3) - WeaponScript.HELD_ANCHOR) < 0.001,
			"a plain style must keep the #559 default anchor (got %s)"
			% WeaponVisualsScript.anchor(3))

	# 2) Style: both sprites load at their authored sizes.
	_check(rocket_style["size"] == Vector2(52, 20),
			"the launcher sprite must sit at the authored in-game size (got %s)"
			% rocket_style["size"])
	_check(shotgun_style["size"] == Vector2(40, 16),
			"the shotgun sprite must sit at its authored in-game size (got %s)"
			% shotgun_style["size"])
	if rocket_style.has("texture"):
		var tex: Texture2D = rocket_style["texture"]
		_check(tex != null and tex.get_width() == 208 and tex.get_height() == 80,
				"the launcher texture must load at its authored 208x80")
	if shotgun_style.has("texture"):
		var stex: Texture2D = shotgun_style["texture"]
		_check(stex != null and stex.get_width() == 160 and stex.get_height() == 64,
				"the shotgun texture must load at its authored 160x64")

	# Both sprites are wired: textured styles show the Sprite2D, not the rect.
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
	var boomstick := _make_weapon(Vector2(1, 0))
	boomstick.selected_weapon = WEAPON_SLOT_SHOTGUN
	boomstick._update_held()
	_check(boomstick._held_sprite.texture != null
			and boomstick._held_sprite.texture != gun._held_sprite.texture,
			"the shotgun must render through its OWN sprite")
	_check(absf(boomstick._held_sprite.scale.x - 0.25) < 0.001,
			"the 160x64 texture must scale to the 40x16 in-game size (got %s)"
			% boomstick._held_sprite.scale)
	_check(not boomstick._held.visible,
			"the ColorRect must stay hidden for the shotgun too")
	gun.get_parent().queue_free()
	boomstick.get_parent().queue_free()
	await get_tree().physics_frame

	# 3) Aim/hold: the launcher rides the aim axis — right, then left.
	var aimer := _make_weapon(Vector2(1, 0))
	aimer.selected_weapon = WEAPON_SLOT_ROCKET
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(wrapf(aimer._held_sprite.rotation, -PI, PI)) < 0.01,
			"aiming right must keep the sprite on the aim axis (got %s rad)"
			% aimer._held_sprite.rotation)
	_check(not aimer._held_sprite.flip_v,
			"aiming right must not flip the launcher")
	var rocket_anchor := WeaponVisualsScript.anchor(WEAPON_SLOT_ROCKET)
	var rocket_lift_keep := WeaponVisualsScript.lift_keep(WEAPON_SLOT_ROCKET)
	var rocket_drop := WeaponVisualsScript.drop(WEAPON_SLOT_ROCKET)
	_check(absf(aimer._held_sprite.position.x - rocket_anchor) < 0.1,
			"the horizontal reach must stay at the per-weapon anchor (got %s)"
			% aimer._held_sprite.position.x)
	_check(absf(aimer._held_sprite.position.y - rocket_drop) < 0.1,
			"a flat aim must drop the launcher below the mid line (got %s)"
			% aimer._held_sprite.position.y)
	# Owner rework 2026-11-24 ("a little lower"): measurably lower than
	# the 2026-11-23 tuning (lift_keep 0.4, drop 6) in EVERY pose.
	_check(rocket_lift_keep < 0.4 and rocket_drop > 6.0,
			"the launcher must hold LOWER than the 2026-11-23 rework values")
	# Aiming 45 degrees up: the launcher's height along stance gravity is
	# lift * lift_keep - drop, near (or below) the body's vertical middle.
	(aimer.get_parent() as AimShooter).aim = Vector2(1, -1).normalized()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lifted: float = -aimer._held_sprite.position.dot(Vector2.DOWN)
	_check(absf(lifted - (rocket_anchor * sqrt(0.5) * rocket_lift_keep
				- rocket_drop)) < 0.1,
			"an aimed-up launcher must follow the damped-lift formula (got %s px up)"
			% lifted)
	_check(lifted < WeaponScript.HELD_ANCHOR * 0.25,
			"the damped lift must stay far below the raw anchor lift")
	# A TILTED stance (gravity down-right 45 degrees) drops along the
	# stance axis, not the world axis.
	(aimer.get_parent() as AimShooter).aim = Vector2(1, 0)
	(aimer.get_parent() as AimShooter).grav = Vector2(1, 1).normalized()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var stance_g := (aimer.get_parent() as AimShooter).grav
	var stance_h: float = -aimer._held_sprite.position.dot(stance_g)
	_check(absf(stance_h - (-rocket_anchor * sqrt(0.5) * rocket_lift_keep
				- rocket_drop)) < 0.1,
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

	# The shotgun rides ITS OWN hold values (per-weapon positioning).
	var hunter := _make_weapon(Vector2(1, 0))
	hunter.selected_weapon = WEAPON_SLOT_SHOTGUN
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(wrapf(hunter._held_sprite.rotation, -PI, PI)) < 0.01,
			"the shotgun must follow the aim axis (got %s rad)"
			% hunter._held_sprite.rotation)
	_check(absf(hunter._held_sprite.position.x
				- WeaponVisualsScript.anchor(WEAPON_SLOT_SHOTGUN)) < 0.1,
			"the shotgun's horizontal reach must use ITS anchor (got %s)"
			% hunter._held_sprite.position.x)
	_check(absf(hunter._held_sprite.position.y
				- WeaponVisualsScript.drop(WEAPON_SLOT_SHOTGUN)) < 0.1,
			"a flat aim must drop the shotgun by ITS drop (got %s)"
			% hunter._held_sprite.position.y)
	hunter.get_parent().queue_free()
	await get_tree().physics_frame

	# 4) Mechanics: every rocket and shotgun number is the pre-#680 value.
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
	await get_tree().physics_frame

	_check(WeaponScript.PELLET_SPEED == 900.0,
			"the pellet speed must stay 900 px/s")
	_check(WeaponScript.PELLET_LIFETIME == 0.5,
			"the pellet lifetime must stay 0.5 s")
	_check(WeaponScript.PELLET_DAMAGE == 6,
			"the pellet damage must stay 6")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_SHOTGUN] == 2,
			"the shotgun keeps its two shots per turn")
	var shooter3 := _make_weapon(Vector2(1, 0))
	shooter3.selected_weapon = WEAPON_SLOT_SHOTGUN
	shooter3._fire_shotgun()
	var pellets := _spawned_pellets()
	_check(pellets.size() == 5,
			"a shotgun volley must still spawn its 5 pellets (got %d)"
			% pellets.size())
	var fanned := 0
	for pellet in pellets:
		if (pellet as Area2D).velocity != Vector2(
				WeaponScript.PELLET_SPEED, 0.0):
			fanned += 1
	_check(fanned >= 4,
			"the shotgun must keep fanning its pellets around the aim (%d of 5)"
			% fanned)
	for pellet in pellets:
		pellet.queue_free()
	shooter3.get_parent().queue_free()
	await get_tree().physics_frame

	# The other weapons keep their plain rectangle fills.
	for slot in WeaponVisualsScript.STYLES.size():
		if slot == WEAPON_SLOT_SHOTGUN or slot == WEAPON_SLOT_ROCKET:
			continue
		_check(not WeaponVisualsScript.STYLES[slot].has("texture"),
				"slot %d must keep its plain rectangle fill (#680 parts 1-2 only touch the rocket and shotgun)"
				% slot)

	# 5) PART 3 — recoil: the kick-back magnitude is registry data,
	# readable for every style; melee styles carry an explicit 0.
	for slot in WeaponVisualsScript.STYLES.size():
		_check(WeaponVisualsScript.recoil(slot) >= 0.0,
				"every style must resolve a recoil magnitude (slot %d)" % slot)
	_check(WeaponVisualsScript.recoil(WEAPON_SLOT_ROCKET) >= 10.0
				and WeaponVisualsScript.recoil(WEAPON_SLOT_SHOTGUN) >= 8.0
				and WeaponVisualsScript.recoil(7) >= 10.0,
				"the rocket, shotgun and railgun must carry a readable kick")
	_check(WeaponVisualsScript.recoil(3) == 0.0
				and WeaponVisualsScript.recoil(6) == 0.0
				and WeaponVisualsScript.recoil(9) == 0.0
				and WeaponVisualsScript.recoil(11) == 0.0,
				"the spear, jackhammer, bat and shovel must carry 0 recoil (their own motion is the animation)")
	_check(WeaponScript.RECOIL_TIME < 0.5,
				"the recoil must recover fast (got %s s)" % WeaponScript.RECOIL_TIME)

	# 6) PART 3 — recoil behavior: the held visual kicks BACK along the
	# aim on a shot, then eases back to the exact hold position.
	var kicker := _make_weapon(Vector2(1, 0))
	kicker.selected_weapon = WEAPON_SLOT_ROCKET
	kicker._update_held()
	kicker._recoil_t = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var kicked: float = WeaponVisualsScript.anchor(WEAPON_SLOT_ROCKET) \
			- kicker._held_sprite.position.x
	_check(kicked > 4.0,
			"the launcher must kick back along the aim on a shot (got %.1f px)"
			% kicked)
	_check(absf(wrapf(kicker._held_sprite.rotation, -PI, PI)) < 0.01,
			"mid-recoil the launcher must stay on the aim axis (got %s rad)"
			% kicker._held_sprite.rotation)
	for i in 22:
		await get_tree().physics_frame
	_check(absf(kicker._held_sprite.position.x
				- WeaponVisualsScript.anchor(WEAPON_SLOT_ROCKET)) < 0.1
			and absf(kicker._held_sprite.position.y
				- WeaponVisualsScript.drop(WEAPON_SLOT_ROCKET)) < 0.1,
			"the recoil must fully recover to the hold position (got %s)"
			% kicker._held_sprite.position)
	kicker.get_parent().queue_free()
	await get_tree().physics_frame

	# 7) PART 3 — the cartoon muzzle flash: a code-drawn starburst pops
	# at the barrel, aimed along the shot, and frees itself shortly.
	# (Settle first so earlier test shots' flashes have faded.)
	for i in 14:
		await get_tree().physics_frame
	var flash_shooter := _make_weapon(Vector2(1, 0))
	flash_shooter.selected_weapon = WEAPON_SLOT_SHOTGUN
	flash_shooter._fire_shotgun()
	var flash: MuzzleFlash = null
	for child in get_children():
		if child is MuzzleFlash:
			flash = child
	_check(flash != null,
			"a volley must pop a cartoon muzzle flash at the barrel")
	if flash != null:
		_check(absf(flash.global_position.x
					- flash_shooter.global_position.x - 36.0) < 0.1
				and absf(flash.global_position.y
					- flash_shooter.global_position.y) < 0.1,
				"the flash must sit at the barrel (got %s)" % flash.global_position)
		_check(absf(wrapf(flash.rotation, -PI, PI)) < 0.01,
				"the flash must aim along the shot (got %s rad)" % flash.rotation)
		_check(MuzzleFlash.FLASH_TIME < 0.25,
				"the flash must be short-lived (got %s s)" % MuzzleFlash.FLASH_TIME)
		for i in 16:
				await get_tree().physics_frame
		_check(not is_instance_valid(flash),
				"the flash must free itself after its tween")
	flash_shooter.get_parent().queue_free()
	await get_tree().physics_frame

	if failures > 0:
		push_error("issue #680 test: %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("issue #680 test: all checks passed")
	get_tree().quit(0)
