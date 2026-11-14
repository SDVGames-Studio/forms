extends Node
## Regression check for issue #281: the mine is destructible — 1 HP, and
## any weapon damage detonates it INSTANTLY (no fuse countdown).
##
## 1. MINE_HP == 1.
## 2. A settled dormant mine hit by weapon damage (a pellet or blast hit)
##    explodes immediately — far sooner than the 2 s proximity fuse would
##    allow — and damages characters inside its blast radius.
## 3. Another mine inside the blast radius chain-detonates too.
## 4. A mine far outside the blast radius survives untouched.
##
## Run headless: godot --headless res://tests/test_issue281.tscn
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

	# --- 1. The constant: a mine has exactly ONE hit point. ---
	var hp_ok: bool = ProjectileBody.MINE_HP == 1
	print("ISSUE281 hp_ok=", hp_ok)
	ok = ok and hp_ok

	# --- Three dormant mines: A (the victim of a weapon hit), B 60 px
	# away (inside A's 100 px blast radius — chain), C 400 px away (safe
	# from the blast; mines never arm each other, only characters do). ---
	var mine_a := _spawn_mine(Vector2(0, 0))
	var mine_b := _spawn_mine(Vector2(60, 0))
	var mine_c := _spawn_mine(Vector2(400, 0))
	var settled := false
	for i in 300:  # 5 s of physics frames at most
		await get_tree().physics_frame
		if is_instance_valid(mine_a) and not mine_a.is_in_group("projectiles") \
				and is_instance_valid(mine_b) and not mine_b.is_in_group("projectiles") \
				and is_instance_valid(mine_c) and not mine_c.is_in_group("projectiles"):
			settled = true
			break
	print("ISSUE281 settled=", settled)
	ok = ok and settled

	# A figure 90 px from A: OUTSIDE the 76.8 px proximity trigger (so A
	# stays dormant), but INSIDE A's 100 px blast radius (so it gets hit).
	var guy := Victim.new()
	guy.add_to_group("player_team")
	add_child(guy)
	guy.global_position = mine_a.global_position + Vector2(90, 0)
	for i in 10:
		await get_tree().physics_frame
	var dormant: bool = is_instance_valid(mine_a) and not mine_a._armed
	print("ISSUE281 dormant_before_hit=", dormant)
	ok = ok and dormant

	# --- 2. A weapon hit (pellet damage) destroys the 1-HP mine AT ONCE —
	# within a fraction of the 2 s fuse (12 frames = 0.2 s cap). ---
	mine_a.take_damage(10)
	var boom := false
	for i in 12:
		await get_tree().physics_frame
		if not is_instance_valid(mine_a) or mine_a.is_queued_for_deletion():
			boom = true
			break
	print("ISSUE281 instant_boom=", boom)
	ok = ok and boom

	# Extra frames so the blast (and the chain into B) fully lands.
	for i in 10:
		await get_tree().physics_frame
	var hit: bool = is_instance_valid(guy) and guy.damage_taken >= 40
	var chain: bool = not is_instance_valid(mine_b) or mine_b.is_queued_for_deletion()
	var survivor: bool = is_instance_valid(mine_c) and not mine_c._exploded \
			and mine_c.is_in_group("mines")
	print("ISSUE281 blast_damage=", guy.damage_taken, " chain=", chain,
			" survivor=", survivor)
	ok = ok and hit and chain and survivor

	print("ISSUE281 ok=", ok)
	get_tree().quit(0 if ok else 1)
