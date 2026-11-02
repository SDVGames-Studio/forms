extends Node
## Regression check for issue #246: the MINE weapon.
##
## A thrown mine lies dormant once it comes to rest — it leaves the
## "projectiles" group (so the turn handover never waits on it) and does
## NOT explode on any fuse. It only arms when a character steps within
## MINE_TRIGGER (1.2 of the 64 px figure width, doubled in issue #262)
## and then explodes after
## the 2-second countdown, damaging everyone in the blast.
##
## Run headless: godot --headless res://tests/test_issue246.tscn
## Exit code 0 = pass.

const MineScript := preload("res://ProjectileBody.gd")

## Stand-in figure: member of a team that records blast damage.
class Victim:
	extends Node2D
	var damage_taken := 0

	func take_damage(amount: int) -> void:
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

	# --- The mine lands, settles and goes DORMANT: no fuse, no explosion,
	# and it stops counting as a live projectile (issue #119 group). ---
	var mine := _spawn_mine(Vector2(0, 0))
	var settled := false
	for i in 300:  # 5 s of physics frames at most
		await get_tree().physics_frame
		if is_instance_valid(mine) and not mine.is_in_group("projectiles"):
			settled = true
			break
	var resting: bool = settled and is_instance_valid(mine) and not mine._exploded
	print("ISSUE246 settled=", settled, " resting=", resting)
	ok = ok and resting

	# --- Nobody near: even after a full second the mine stays dormant —
	# it explodes ONLY when a character is inside the trigger radius. ---
	var far_guy := Victim.new()
	far_guy.add_to_group("player_team")
	far_guy.global_position = mine.global_position + Vector2(120, 0)
	add_child(far_guy)
	for i in 60:
		await get_tree().physics_frame
	var still_dormant: bool = is_instance_valid(mine) and not mine._armed
	print("ISSUE246 still_dormant=", still_dormant)
	ok = ok and still_dormant

	# --- A character steps within MINE_TRIGGER (1.2 x 64 = 76.8 px since
	# issue #262): the
	# mine arms, counts 2 seconds and explodes — the victim takes damage. ---
	far_guy.global_position = mine.global_position + Vector2(30, 0)
	var boom := false
	for i in 240:  # arm + 2 s fuse, with margin
		await get_tree().physics_frame
		if not is_instance_valid(mine) or mine.is_queued_for_deletion():
			boom = true
			break
	# One extra frame so take_damage from the explosion lands.
	await get_tree().physics_frame
	var hit: bool = far_guy.damage_taken == 40
	print("ISSUE246 boom=", boom, " damage_taken=", far_guy.damage_taken)
	ok = ok and boom and hit

	far_guy.queue_free()
	print("ISSUE246 ok=", ok)
	get_tree().quit(0 if ok else 1)
