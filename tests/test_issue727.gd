extends Node
## Regression check for issue #727: a mine/grenade thrown at the ground
## from close range ended up INSIDE the terrain, and a fast projectile
## could pass THROUGH ground as thin as the carved pieces get
## (DestructibleGround.MIN_PIECE = 2 px).
##
## Root causes fixed:
##  1. Weapon._spawn_body placed the projectile 36 px ahead of the
##     weapon along the aim — inside the ground whenever a steep,
##     close-range throw cleared the surface sooner (the figure centre
##     sits ~29 px above the floor). The spawn is now clamped back to
##     the surface (Weapon._safe_spawn_position).
##  2. A lobbed body moves 20+ px per physics step (550 px/s throw,
##     1200 gravity after a fall) — more than the 14 px body, so a
##     discrete step could jump clean across a 2 px strip. Godot 4.7's
##     solver already catches the plain fall via speculative contacts;
##     the fix adds continuous collision detection (shape casting) so
##     thin ground is a guarantee, not a solver accident
##     (ProjectileBody.continuous_cd; the ROCKET stays discrete — its
##     contact detonation must not fire on CCD's speculative contacts).
##
## Run headless: godot --headless res://tests/test_issue727.tscn
## Exit code 0 = pass.

const WeaponFire := preload("res://scripts/Weapon.gd")
const BodyScript := preload("res://scripts/ProjectileBody.gd")

## Stand-in wielder (test_issue495 pattern): provides the aim frame the
## Weapon reads — aim straight DOWN, level gravity down — without a
## full figure scene.
const WielderScript := "
extends CharacterBody2D
func aim_dir(f: float, d: float) -> Vector2:
	return Vector2(0, 1)
func current_gravity() -> Vector2:
	return Vector2.DOWN
"

## A ground slab on layer 1, centred at `centre` (top = centre.y - h/2).
func _make_ground(centre: Vector2, width: float, height: float) -> StaticBody2D:
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	shape.shape = rect
	ground.add_child(shape)
	ground.position = centre
	add_child(ground)
	return ground


func _spawn_body(kind: int, at: Vector2, velocity: Vector2,
		lifetime := 0.0) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(BodyScript)
	body.setup(kind, velocity, 40, lifetime, Vector2(14, 14),
		Color(0.3, 0.7, 0.3, 1), 100.0, 0.8)
	body.global_position = at
	add_child(body)
	return body


func _ready() -> void:
	var ok := true

	# --- 1. CCD flags: every bouncing projectile sweeps its motion; the
	# rocket (contact detonation) stays discrete. ---
	var probe_mine := _spawn_body(ProjectileBody.Kind.MINE,
		Vector2(0, -400), Vector2.ZERO)
	var probe_grenade := _spawn_body(ProjectileBody.Kind.GRENADE,
		Vector2(0, -400), Vector2.ZERO)
	var probe_rocket := _spawn_body(ProjectileBody.Kind.ROCKET,
		Vector2(0, -400), Vector2.ZERO)
	var ccd_ok: bool = probe_mine.continuous_cd \
			and probe_grenade.continuous_cd and not probe_rocket.continuous_cd
	print("ISSUE727 ccd_flags=", ccd_ok)
	ok = ok and ccd_ok
	probe_mine.free()
	probe_grenade.free()
	probe_rocket.free()

	# --- 2. Point-blank downward throw: the mine spawns at the SURFACE,
	# not buried in the floor, then lands ON the floor. ---
	# Floor: top at y=280, spanning x in [-1000, 1000].
	_make_ground(Vector2(0, 300), 2000.0, 40.0)
	var wielder := CharacterBody2D.new()
	var script := GDScript.new()
	script.source_code = WielderScript
	script.reload()
	wielder.set_script(script)
	# A real figure's centre sits ~29 px above the floor it stands on.
	wielder.global_position = Vector2(0, 251.0)
	add_child(wielder)
	var weapon := WeaponFire.new()
	wielder.add_child(weapon)
	# One physics frame so the floor registers in the ray's space.
	await get_tree().physics_frame
	var mine: RigidBody2D = weapon._spawn_body(ProjectileBody.Kind.MINE,
		Vector2(0, 300), 40, 0.0, Vector2(14, 14),
		Color(0.22, 0.24, 0.3, 1), 100.0, 0.8)
	# Old behaviour: 251 + 36 = 287 — 7 px INSIDE the floor (top 280).
	# New behaviour: backed off the surface (ray hit 280, minus the
	# half-diagonal + margin), above the floor and in front of the wielder.
	var spawn_y: float = mine.global_position.y
	var spawn_ok: bool = spawn_y > 251.0 and spawn_y + 7.0 <= 280.0
	print("ISSUE727 spawn_y=", spawn_y, " (weapon 251, surface 280) ok=", spawn_ok)
	ok = ok and spawn_ok
	# It then drops, bounces and settles ON the floor — it never buries
	# itself (centre stays above the surface line while at rest).
	var settled := false
	for i in 240:
		await get_tree().physics_frame
		if is_instance_valid(mine) and not mine.is_in_group("projectiles"):
			settled = true
	var resting_ok: bool = is_instance_valid(mine) and settled \
			and mine.global_position.y < 280.0 and not mine._exploded
	print("ISSUE727 settled=", settled, " rest_y=",
		mine.global_position.y if is_instance_valid(mine) else -1.0,
		" ok=", resting_ok)
	ok = ok and resting_ok

	# --- 3. Thin ground (2 px, the thinnest a carved piece gets) under a
	# FAST falling body: CCD catches the strip instead of stepping over
	# it. The strip sits at x=3000 (beyond the floor) with nothing below
	# for ~800 px — a body that tunnels keeps falling forever. ---
	# Strip top at y=199, bottom at y=201 (width 400).
	_make_ground(Vector2(3000, 200), 400.0, 2.0)
	var grenade := _spawn_body(ProjectileBody.Kind.GRENADE,
		Vector2(3000, 100), Vector2(0, 1400), 3.0)
	var mine2 := _spawn_body(ProjectileBody.Kind.MINE,
		Vector2(3100, 100), Vector2(0, 1400))
	# 23+ px per step vs a 2 px strip: discrete stepping would hop clean
	# across it. Caught bodies stay above the strip (y < 215); a tunnelled
	# one is past 400 within eight frames.
	var g_lowest := 0.0
	var m_lowest := 0.0
	for i in 40:
		await get_tree().physics_frame
		if is_instance_valid(grenade):
			g_lowest = maxf(g_lowest, grenade.global_position.y)
		if is_instance_valid(mine2):
			m_lowest = maxf(m_lowest, mine2.global_position.y)
	var tunnel_ok: bool = g_lowest < 215.0 and m_lowest < 215.0
	print("ISSUE727 grenade_lowest=", g_lowest, " mine_lowest=", m_lowest,
		" (strip 199..201, tunneled would pass 400) ok=", tunnel_ok)
	ok = ok and tunnel_ok

	print("ISSUE727 ok=", ok)
	get_tree().quit(0 if ok else 1)
