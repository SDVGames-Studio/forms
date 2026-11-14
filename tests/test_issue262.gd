extends Node
## Regression check for issue #262: the mine's activation radius is
## DOUBLED — MINE_TRIGGER went from 0.6 x 64 = 38.4 px to 1.2 x 64 = 76.8 px.
##
## A character standing 60 px from a settled mine (deadly now, safely out
## of the OLD 38.4 px trigger) arms and detonates it; a character 100 px
## away (outside even the new radius) leaves it dormant.
##
## Run headless: godot --headless res://tests/test_issue262.tscn
## Exit code 0 = pass.

const MineScript := preload("res://scripts/ProjectileBody.gd")

## Stand-in figure: member of a team that records blast damage.
class Victim:
	extends Node2D
	var damage_taken := 0

	# Issue #335: figures take_damage(amount, attacker) — stubs take the
	# optional attacker too.
	func take_damage(amount: int, attacker: Node2D = null) -> void:
		damage_taken += amount


func _make_floor() -> void:
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000, 40)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(0, 300)
	add_child(floor_body)


func _spawn_mine(at: Vector2) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(MineScript)
	# No launch velocity — the mine simply drops onto the floor below.
	body.setup(ProjectileBody.Kind.MINE, Vector2.ZERO, 40, 0.0,
		Vector2(14, 14), Color(0.22, 0.24, 0.3, 1), 100.0, 0.8)
	body.global_position = at
	add_child(body)
	return body


func _ready() -> void:
	var ok := true
	_make_floor()

	# --- The constant itself: the trigger radius is exactly 1.2 x 64. ---
	var radius_ok: bool = ProjectileBody.MINE_TRIGGER == 1.2 * 64.0 \
			and ProjectileBody.MINE_TRIGGER == 76.8
	print("ISSUE262 radius=", ProjectileBody.MINE_TRIGGER, " radius_ok=", radius_ok)
	ok = ok and radius_ok

	# --- The mine lands and settles dormant. ---
	var mine := _spawn_mine(Vector2(0, 0))
	var settled := false
	for i in 300:  # 5 s of physics frames at most
		await get_tree().physics_frame
		if is_instance_valid(mine) and not mine.is_in_group("projectiles"):
			settled = true
			break
	print("ISSUE262 settled=", settled)
	ok = ok and settled

	var guy := Victim.new()
	guy.add_to_group("player_team")
	add_child(guy)

	# --- 100 px away: OUTSIDE the doubled trigger (76.8 px) — the mine
	# stays dormant even after a full second. ---
	guy.global_position = mine.global_position + Vector2(100, 0)
	for i in 60:
		await get_tree().physics_frame
	var dormant: bool = is_instance_valid(mine) and not mine._armed
	print("ISSUE262 dormant_at_100px=", dormant)
	ok = ok and dormant

	# --- 60 px away: inside the DOUBLED trigger (76.8 px) but outside the
	# OLD one (38.4 px) — the mine arms, counts its fuse and explodes,
	# damaging the character. ---
	guy.global_position = mine.global_position + Vector2(60, 0)
	var boom := false
	for i in 240:  # arm + 2 s fuse, with margin
		await get_tree().physics_frame
		if not is_instance_valid(mine) or mine.is_queued_for_deletion():
			boom = true
			break
	# One extra frame so take_damage from the explosion lands.
	await get_tree().physics_frame
	var hit: bool = guy.damage_taken == 40
	print("ISSUE262 boom_at_60px=", boom, " damage_taken=", guy.damage_taken)
	ok = ok and boom and hit

	guy.queue_free()
	print("ISSUE262 ok=", ok)
	get_tree().quit(0 if ok else 1)
