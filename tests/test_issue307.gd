extends Node
## Regression check for issue #307: the JACKHAMMER weapon.
##
## Hold F to charge (0..1), release: the wielder drills along the AIM
## direction (issue #316: any direction the character directs — this
## test aims steepest down, VIEW_MAX) for JACKHAMMER_MIN..MAX seconds
## (1–3 s, scaled by the charge), carving destructible ground ahead and
## damaging every other character on the way — each victim once per
## drill. The drill grinds to an early halt against indestructible
## ground, and while it runs a turn-effects gate node keeps the post-shot
## handover waiting.
##
## Run headless: godot --headless res://tests/test_issue307.tscn
## Exit code 0 = pass.

const WeaponFire := preload("res://Weapon.gd")
const Dirt := preload("res://scripts/DestructibleGround.gd")

## Stand-in wielder: a REAL-SIZE figure — capsule radius 24, height 64,
## exactly Npc.gd / the Player scenes' body (48 px wide, 64 px tall).
## Issue #307 rework: the original stand-in was a 24x24 box, so the old
## 16 px tunnel (32 px wide) still fit it and the wedge bug — a 48 px
## figure cannot enter its own 32 px tunnel — never reproduced. Keeps the
## drill's velocity while the drill runs (exactly Player.gd's #316
## drilling branch) and clamps to the along-gravity component otherwise
## (Player.gd's frozen-input branch), then moves with it.
const WielderScript := "
extends CharacterBody2D
var view_angle := 0.0
func aim_dir(f: float, d: float) -> Vector2:
	return Vector2(cos(view_angle) * f, -sin(view_angle) * d)
func current_gravity() -> Vector2:
	return Vector2.DOWN
func _physics_process(_delta: float) -> void:
	var weapon := get_node_or_null(\"Weapon\")
	if weapon != null and weapon.has_method(\"is_drilling\") \
			and weapon.is_drilling():
		pass
	else:
		velocity = Vector2(0.0, velocity.y)
	move_and_slide()
"

## Stand-in victim: records take_damage calls.
const VictimScript := "
extends Node2D
var hits := 0
var damage := 0
func take_damage(amount: int) -> void:
	hits += 1
	damage += amount
"


func _make_wielder(at: Vector2) -> CharacterBody2D:
	var script := GDScript.new()
	script.source_code = WielderScript
	script.reload()
	var wielder := CharacterBody2D.new()
	wielder.set_script(script)
	var shape := CollisionShape2D.new()
	# Issue #307 rework: real figure dimensions (Npc.gd builds the same
	# capsule; the Player scenes author radius 24 too).
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


func _make_victim(at: Vector2, group: String) -> Node2D:
	var script := GDScript.new()
	script.source_code = VictimScript
	script.reload()
	var victim := Node2D.new()
	victim.set_script(script)
	victim.add_to_group(group)
	victim.global_position = at
	return victim


func _effects_alive() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("turn_effects"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func _ready() -> void:
	await get_tree().process_frame
	var failures := 0
	var level := Node2D.new()
	add_child(level)

	# --- The charge maps onto the drill duration (1 s .. 5 s), and the
	# drill gates the turn handover while it runs. ---
	var charge_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(charge_wielder)
	await get_tree().process_frame
	var charge_weapon: Node2D = charge_wielder.get_node("Weapon")
	charge_weapon.call("_start_jackhammer", 0.0)
	var min_left: float = charge_weapon.get("_drill_left")
	charge_weapon.call("_end_jackhammer")
	charge_weapon.call("_start_jackhammer", 1.0)
	var max_left: float = charge_weapon.get("_drill_left")
	var gated: bool = _effects_alive() > 0
	charge_weapon.call("_end_jackhammer")
	await get_tree().process_frame
	var released: bool = _effects_alive() == 0
	var charge_ok: bool = absf(min_left - WeaponFire.JACKHAMMER_MIN_TIME) < 0.01 \
			and absf(max_left - WeaponFire.JACKHAMMER_MAX_TIME) < 0.01
	print("ISSUE307 charge min=", min_left, " max=", max_left,
			" gated=", gated, " released=", released)
	if not charge_ok:
		printerr("FAIL: charge fraction must map to 1..3 s of drilling")
		failures += 1
	if not (gated and released):
		printerr("FAIL: the drill must gate the turn handover only while running")
		failures += 1
	charge_wielder.queue_free()

	# --- The drill carves destructible ground and moves the wielder along
	# the AIMED direction (issue #316: steepest downward aim, VIEW_MAX);
	# a figure inside the tunnel is damaged EXACTLY once.
	# Issue #307 rework: start ABOVE the dirt — the capsule's front cap
	# reaches center+32, so (0,-40) keeps the body clear of the top edge
	# at y=10 exactly like a figure standing on the surface.
	var wielder := _make_wielder(Vector2(0, -40))
	wielder.view_angle = -1.2  # steepest aim below the horizon (#316)
	level.add_child(wielder)
	var dirt := Dirt.new()
	dirt.rect_size = Vector2(240, 300)
	dirt.position = Vector2(0, 160)  # top edge at y = 10
	level.add_child(dirt)
	var victim := _make_victim(Vector2(38, 60), "enemy_team")
	level.add_child(victim)
	await get_tree().process_frame
	var weapon: Node2D = wielder.get_node("Weapon")
	weapon.call("_start_jackhammer", 1.0)
	for i in 400:  # 5 s drill + margin
		await get_tree().physics_frame
		if weapon.get("_drill_left") == 0.0:
			break
	await get_tree().physics_frame
	var drilled_through: bool = wielder.global_position.y > 150.0
	var hit_once: bool = victim.get("hits") == 1 \
			and victim.get("damage") == WeaponFire.JACKHAMMER_DAMAGE
	var dirt_gone: bool = not is_instance_valid(dirt) or dirt.is_queued_for_deletion()
	print("ISSUE307 drill y=", wielder.global_position.y,
			" hits=", victim.get("hits"), " dirt_gone=", dirt_gone)
	if not drilled_through:
		printerr("FAIL: the wielder did not drill down through the ground")
		failures += 1
	if not hit_once:
		printerr("FAIL: a figure on the way must take the drill damage exactly once")
		failures += 1
	if not dirt_gone:
		printerr("FAIL: the original chunk below the wielder was not carved away")
		failures += 1
	if _effects_alive() != 0:
		printerr("FAIL: drill effect gate leaked after the drill ended")
		failures += 1

	# --- Indestructible ground stops the drill early: no progress for
	# JACKHAMMER_STALL_TIME seconds grinds it to a halt. Issue #316: the
	# drill runs along the aim — a level aim (view_angle 0) into a
	# VERTICAL wall grinds the wielder to a clean halt with no slide.
	wielder.velocity = Vector2.ZERO
	wielder.global_position = Vector2(0, 0)
	wielder.view_angle = 0.0
	var slab := StaticBody2D.new()
	slab.collision_layer = 1
	slab.collision_mask = 0
	var slab_shape := CollisionShape2D.new()
	var slab_rect := RectangleShape2D.new()
	slab_rect.size = Vector2(40, 400)
	slab_shape.shape = slab_rect
	slab.add_child(slab_shape)
	slab.position = Vector2(60, 0)  # left edge at x = 40
	level.add_child(slab)
	var bystander := _make_victim(Vector2(90, 20), "enemy_team")
	level.add_child(bystander)
	await get_tree().process_frame
	weapon.call("_start_jackhammer", 1.0)
	var frames := 0
	for i in 200:  # a full 3 s drill would need ~180 frames (#316)
		await get_tree().physics_frame
		frames = i + 1
		if weapon.get("_drill_left") == 0.0:
			break
	await get_tree().physics_frame
	var stopped_early: bool = frames < 150
	var resting: bool = wielder.global_position.x < 30.0
	var untouched: bool = bystander.get("hits") == 0
	print("ISSUE307 stall frames=", frames, " y=", wielder.global_position.y,
			" bystander_hits=", bystander.get("hits"))
	if not stopped_early:
		printerr("FAIL: indestructible ground must end the drill early")
		failures += 1
	if not resting:
		printerr("FAIL: the wielder drilled through indestructible ground")
		failures += 1
	if not untouched:
		printerr("FAIL: a figure outside the tunnel radius was damaged")
		failures += 1

	if failures == 0:
		print("ISSUE307 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE307 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
