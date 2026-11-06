extends Node
## Regression check for issue #316: the jackhammer rework.
##
## 1. The drill runs along the AIM direction the character directs it in
##    (a level aim drills HORIZONTALLY — not just down the gravity).
## 2. The maximum drill time dropped to 3 seconds (the min stays 1 s).
## 3. The drill direction follows the LIVE aim while it runs: steering
##    the aim (the W/S view keys in the real game) turns a running
##    drill, and there is no cancel — over open ground the drill always
##    runs out its full aimed time.
## 4. Rework: the damage corridor REACHES a touching figure (contact at
##    48 px, the new reach is 64) — a drill aimed at an adjacent enemy
##    damages them instead of grinding against their body harmlessly.
##
## Run headless: godot --headless res://tests/test_issue316.tscn
## Exit code 0 = pass.

const WeaponFire := preload("res://Weapon.gd")

## Stand-in wielder: a REAL-SIZE figure (capsule radius 24, height 64 —
## exactly Npc.gd / the Player scenes' body). Mirrors Player.gd's #316
## drilling branch: while the drill runs the aim input steers
## `view_angle` (the `steer` var stands in for the view_up/view_down
## axis at 1 rad/s) and the drill velocity is kept intact; otherwise the
## frozen-input clamp keeps only the along-gravity component.
const WielderScript := "
extends CharacterBody2D
var view_angle := 0.0
var steer := 0.0
func aim_dir(f: float, d: float) -> Vector2:
	return Vector2(cos(view_angle) * f, -sin(view_angle) * d)
func current_gravity() -> Vector2:
	return Vector2.DOWN
func _physics_process(delta: float) -> void:
	var weapon := get_node_or_null(\"Weapon\")
	if weapon != null and weapon.has_method(\"is_drilling\") and weapon.is_drilling():
		view_angle = clampf(view_angle + steer * delta, -1.2, 1.2)
	else:
		velocity = Vector2(0.0, velocity.y)
	move_and_slide()
"


## Stand-in victim (issue #316 rework): records take_damage calls.
const VictimScript := "
extends Node2D
var hits := 0
var damage := 0
func take_damage(amount: int) -> void:
	hits += 1
	damage += amount
"


func _make_victim(at: Vector2, group := "enemy_team") -> Node2D:
	var script := GDScript.new()
	script.source_code = VictimScript
	script.reload()
	var victim := Node2D.new()
	victim.set_script(script)
	victim.add_to_group(group)
	victim.global_position = at
	return victim


func _make_wielder(at: Vector2) -> CharacterBody2D:
	var script := GDScript.new()
	script.source_code = WielderScript
	script.reload()
	var wielder := CharacterBody2D.new()
	wielder.set_script(script)
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 64.0
	shape.shape = capsule
	wielder.add_child(shape)
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.set_script(WeaponFire)
	wielder.add_child(weapon)
	wielder.global_position = at
	return wielder


func _ready() -> void:
	await get_tree().process_frame
	var failures := 0
	var level := Node2D.new()
	add_child(level)

	# --- The charge maps onto 1..3 s (#316: the max dropped from 5 s),
	# and the drill starts along the AIM direction (level aim here). ---
	var charge_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(charge_wielder)
	await get_tree().process_frame
	var charge_weapon: Node2D = charge_wielder.get_node("Weapon")
	charge_weapon.call("_start_jackhammer", 0.0)
	var min_left: float = charge_weapon.get("_drill_left")
	charge_weapon.call("_end_jackhammer")
	charge_weapon.call("_start_jackhammer", 1.0)
	var max_left: float = charge_weapon.get("_drill_left")
	var start_dir: Vector2 = charge_weapon.get("_drill_dir")
	charge_weapon.call("_end_jackhammer")
	var charge_ok: bool = absf(min_left - WeaponFire.JACKHAMMER_MIN_TIME) < 0.01 \
			and absf(max_left - 3.0) < 0.01
	var aimed_ok: bool = start_dir.distance_to(Vector2(1, 0)) < 0.01
	print("ISSUE316 charge min=", min_left, " max=", max_left,
			" start_dir=", start_dir)
	if not charge_ok:
		printerr("FAIL: charge fraction must map to 1..3 s of drilling")
		failures += 1
	if not aimed_ok:
		printerr("FAIL: the drill must start along the aim direction")
		failures += 1
	charge_wielder.queue_free()

	# --- A level aim drills HORIZONTALLY through open ground — any
	# direction the character directs, not just down the gravity. ---
	var side_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(side_wielder)
	await get_tree().process_frame
	var side_weapon: Node2D = side_wielder.get_node("Weapon")
	side_weapon.call("_start_jackhammer", 1.0)
	for i in 200:
		await get_tree().physics_frame
		if side_weapon.get("_drill_left") == 0.0:
			break
	var sideways: bool = side_wielder.global_position.x > 100.0
	var flat: bool = absf(side_wielder.global_position.y) < 10.0
	print("ISSUE316 horizontal drill end=", side_wielder.global_position)
	if not sideways:
		printerr("FAIL: a level-aimed drill must carry the wielder sideways")
		failures += 1
	if not flat:
		printerr("FAIL: a level-aimed drill must not drift along the gravity")
		failures += 1
	side_wielder.queue_free()

	# --- Issue #316 rework: the damage corridor REACHES a touching
	# figure. Two figure capsules (radius 24) touch at 48 px, so the old
	# forward window (< 40 px) ended before body contact — a drill aimed
	# at a nearby enemy (not into the ground) ground against them and
	# dealt NO damage. A victim 60 px along a LEVEL aim (beyond the old
	# 40 px window, inside body contact + the new JACKHAMMER_REACH) must
	# take the drill damage within the first ticks. ---
	var reach_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(reach_wielder)
	await get_tree().process_frame
	var reach_weapon: Node2D = reach_wielder.get_node("Weapon")
	var reach_victim := _make_victim(Vector2(60, 0))
	level.add_child(reach_victim)
	reach_weapon.call("_start_jackhammer", 0.0)
	for i in 3:  # the hit must land on the very first ticks
		await get_tree().physics_frame
	reach_weapon.call("_end_jackhammer")
	var reach_hit: bool = reach_victim.get("hits") == 1 \
			and reach_victim.get("damage") == WeaponFire.JACKHAMMER_DAMAGE
	print("ISSUE316 reach hits=", reach_victim.get("hits"))
	if not reach_hit:
		printerr("FAIL: a touching figure ahead of the drill must take its damage")
		failures += 1
	reach_wielder.queue_free()
	reach_victim.queue_free()

	# --- Steering: the drill direction follows the LIVE aim mid-run —
	# the running drill turns upward while `steer` raises the view. ---
	var steer_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(steer_wielder)
	await get_tree().process_frame
	steer_wielder.set("steer", 1.0)
	var steer_weapon: Node2D = steer_wielder.get_node("Weapon")
	steer_weapon.call("_start_jackhammer", 1.0)
	var before: Vector2 = steer_weapon.get("_drill_dir")
	for i in 70:  # ~1.2 s of steering toward the view clamp
		await get_tree().physics_frame
		if steer_weapon.get("_drill_left") == 0.0:
			break
	var after: Vector2 = steer_weapon.get("_drill_dir")
	var still_running: bool = steer_weapon.get("_drill_left") > 0.0
	var steered: bool = before.y > -0.01 and after.y < -0.3
	print("ISSUE316 steer before=", before, " after=", after,
			" still_running=", still_running)
	if not steered:
		printerr("FAIL: steering the aim must turn a running drill")
		failures += 1
	if not still_running:
		printerr("FAIL: steering must not end the drill (no cancel)")
		failures += 1
	steer_weapon.call("_end_jackhammer")
	steer_wielder.queue_free()

	# --- No cancel over open ground: the full 3 s runs out — nothing
	# the wielder does ends the drill before its time. ---
	var full_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(full_wielder)
	await get_tree().process_frame
	var full_weapon: Node2D = full_wielder.get_node("Weapon")
	full_weapon.call("_start_jackhammer", 1.0)
	var frames := 0
	for i in 200:
		await get_tree().physics_frame
		frames = i + 1
		if full_weapon.get("_drill_left") == 0.0:
			break
	var ran_full: bool = frames >= 170
	print("ISSUE316 no-cancel frames=", frames)
	if not ran_full:
		printerr("FAIL: over open ground the drill must run its full 3 s")
		failures += 1
	full_wielder.queue_free()

	if failures == 0:
		print("ISSUE316 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE316 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
