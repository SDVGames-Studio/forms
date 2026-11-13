extends Node
## Regression check for issue #363: the jackhammer push rework.
##
## 1. A figure the moving drill MEETS is PUSHED in the direction of
##    aiming — a real physics body (CharacterBody2D with the idle clamp
##    of an uncontrolled figure: only the along-gravity velocity
##    component survives) is still shoved along the aim, because the
##    drill moves the body itself every tick.
## 2. While the pushed figure stays in contact it takes 10 damage per
##    SECOND — the grind streams in whole-number chunks, there is no
##    one-shot burst any more (a full 1 s min-charge contact grinds
##    ~10, never 30 at once).
## 3. The push follows the LIVE aim direction — a downward aim drives
##    the met figure straight down, a level aim straight ahead.
##
## Run headless: godot --headless res://tests/test_issue363.tscn
## Exit code 0 = pass.

const WeaponFire := preload("res://scripts/Weapon.gd")

## Stand-in wielder: a REAL-SIZE figure (capsule radius 24, height 64),
## mirroring Player.gd's #316 drilling branch — while the drill runs the
## aim input steers `view_angle` (the `steer` var stands in for the
## view_up/view_down axis) and the drill velocity is kept intact;
## otherwise the frozen-input clamp keeps only the along-gravity part.
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

## Stand-in met figure: a REAL CharacterBody2D with the idle clamp of an
## UNCONTROLLED figure (Player/Npc: `velocity = grav * velocity.dot(grav)`
## — on flat levels only velocity.y survives), recording take_damage
## calls. Collision layer/mask 0 isolates the push from body-to-body
## contact so the test measures the DRILL's shove alone.
const BodyVictimScript := "
extends CharacterBody2D
var hits := 0
var damage := 0
func take_damage(amount: int) -> void:
	hits += 1
	damage += amount
func _physics_process(_delta: float) -> void:
	velocity = Vector2(0.0, velocity.y)
	move_and_slide()
"

## Plain stand-in victim (no physics): records take_damage calls.
const NodeVictimScript := "
extends Node2D
var hits := 0
var damage := 0
func take_damage(amount: int) -> void:
	hits += 1
	damage += amount
"


func _make_node_victim(at: Vector2, group := "enemy_team") -> Node2D:
	var script := GDScript.new()
	script.source_code = NodeVictimScript
	script.reload()
	var victim := Node2D.new()
	victim.set_script(script)
	victim.add_to_group(group)
	victim.global_position = at
	return victim


func _make_body_victim(at: Vector2, group := "enemy_team") -> CharacterBody2D:
	var script := GDScript.new()
	script.source_code = BodyVictimScript
	script.reload()
	var victim := CharacterBody2D.new()
	victim.set_script(script)
	victim.collision_layer = 0
	victim.collision_mask = 0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 64.0
	shape.shape = capsule
	victim.add_child(shape)
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

	# --- A met PHYSICS body is pushed along the level aim even though
	# its own idle clamp eats tangential velocity writes — and the grind
	# streams while the contact lasts. ---
	var body_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(body_wielder)
	var body_victim := _make_body_victim(Vector2(60, 0))
	level.add_child(body_victim)
	await get_tree().process_frame
	var body_weapon: Node2D = body_wielder.get_node("Weapon")
	body_weapon.call("_start_jackhammer", 0.0)
	for i in 30:  # ~0.5 s of contact
		await get_tree().physics_frame
	body_weapon.call("_end_jackhammer")
	var body_pushed: bool = body_victim.global_position.x > 90.0 \
			and absf(body_victim.global_position.y) < 10.0
	var body_ground: int = body_victim.get("damage")
	var body_streamed: bool = body_ground >= 3 and body_ground <= 7 \
			and body_victim.get("hits") == body_ground
	print("ISSUE363 body-push end=", body_victim.global_position,
			" hits=", body_victim.get("hits"), " damage=", body_ground)
	if not body_pushed:
		printerr("FAIL: a met figure must be pushed in the aiming direction despite its idle clamp")
		failures += 1
	if not body_streamed:
		printerr("FAIL: the pushed figure must take ~10 damage per second of contact, in streamed chunks")
		failures += 1
	body_wielder.queue_free()
	body_victim.queue_free()
	await get_tree().process_frame

	# --- The grind rate over a FULL min-charge drill (1 s): ~10 total
	# streamed damage — never the old 30 one-shot burst. ---
	var rate_wielder := _make_wielder(Vector2(0, 0))
	level.add_child(rate_wielder)
	var rate_victim := _make_node_victim(Vector2(60, 0))
	level.add_child(rate_victim)
	await get_tree().process_frame
	var rate_weapon: Node2D = rate_wielder.get_node("Weapon")
	rate_weapon.call("_start_jackhammer", 0.0)
	for i in 100:  # 1 s drill + margin
		await get_tree().physics_frame
		if rate_weapon.get("_drill_left") == 0.0:
			break
	rate_weapon.call("_end_jackhammer")
	var grind: int = rate_victim.get("damage")
	var rate_ok: bool = grind >= 8 and grind <= 12 \
			and rate_victim.get("hits") == grind
	var still_pushed: bool = rate_victim.global_position.x > 150.0 \
			and absf(rate_victim.global_position.y) < 10.0
	print("ISSUE363 grind-rate hits=", rate_victim.get("hits"),
			" damage=", grind, " victim=", rate_victim.global_position)
	if not rate_ok:
		printerr("FAIL: 1 s of contact must grind ~10 damage (10/s), not a one-shot burst")
		failures += 1
	if not still_pushed:
		printerr("FAIL: the pushed figure must travel ahead of the drill for the whole run")
		failures += 1
	rate_wielder.queue_free()
	rate_victim.queue_free()
	await get_tree().process_frame

	# --- The push follows the AIM direction: the steepest downward aim
	# (view_angle -1.2, the VIEW_MAX clamp of the real game) drives the
	# met figure along that exact diagonal, not just "somewhere down". ---
	var down_wielder := _make_wielder(Vector2(0, 0))
	down_wielder.view_angle = -1.2  # steepest aim below the horizon
	level.add_child(down_wielder)
	var down_victim := _make_node_victim(Vector2(0, 60))
	level.add_child(down_victim)
	await get_tree().process_frame
	var down_weapon: Node2D = down_wielder.get_node("Weapon")
	down_weapon.call("_start_jackhammer", 0.0)
	for i in 18:  # ~0.3 s of contact
		await get_tree().physics_frame
	down_weapon.call("_end_jackhammer")
	var moved := down_victim.global_position - Vector2(0, 60)
	var aim := Vector2(cos(-1.2), -sin(-1.2))
	var perp := Vector2(-aim.y, aim.x)
	var down_pushed: bool = moved.dot(aim) > 25.0 \
			and absf(moved.dot(perp)) < 5.0
	var down_ground: bool = down_victim.get("damage") >= 1
	print("ISSUE363 down-push moved=", moved,
			" damage=", down_victim.get("damage"))
	if not down_pushed:
		printerr("FAIL: the push must run exactly along the aiming direction")
		failures += 1
	if not down_ground:
		printerr("FAIL: the downward push must grind damage too")
		failures += 1
	down_wielder.queue_free()
	down_victim.queue_free()

	if failures == 0:
		print("ISSUE363 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE363 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
