extends Node
## Regression check for issue #374: items on the level must collide
## with other objects —
##  - mask: the item's collision mask spans the world terrain (1), both
##    character layers (2 NPCs / 8 players) and layer 4 (other items,
##    mines, projectiles), with contact monitoring on;
##  - item vs item: a bundle dropped onto a resting bundle stacks on it
##    — centres keep about one body size apart, no overlap, and mere
##    item-item contact detonates nothing;
##  - item vs character: a bundle dropped straight onto a standing
##    figure's head is TAKEN on contact instead of balancing on it
##    (contact happens at ~SIZE px, outside the 0.75 * SIZE radius);
##  - item vs projectile: a rocket flying into a floating item detonates
##    on contact and destroys the 1-HP item.
##
## Run headless: godot --headless res://tests/test_issue374.tscn
## Exit code 0 = pass.

const FLOOR_Y := 300.0
const WAIT_FRAMES := 150

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE374 %s — %s" % ["ok" if ok else "FAIL", what])


## Issue #374: a static floor slab on layer 1, like every test world in
## this suite (test_issue281 and friends) — the item must rest on it.
func _make_floor() -> StaticBody2D:
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(400, FLOOR_Y)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1600, 40)
	shape.shape = rect
	floor_body.add_child(shape)
	add_child(floor_body)
	return floor_body


func _spawn_item(x: float, y: float) -> LevelItem:
	var item := LevelItem.new()
	item.kind = LevelItem.Kind.FIRST_AID
	item.global_position = Vector2(x, y)
	add_child(item)
	return item


func _ready() -> void:
	seed(374)
	_make_floor()

	# 1) The mask itself — the issue orders collision with items,
	# characters and projectiles, all through the item's mask.
	var probe := _spawn_item(150, 100)
	_check("item mask covers terrain, characters, items and projectiles",
		probe.collision_mask == 1 | 2 | 4 | 8)
	_check("item watches body contacts", probe.contact_monitor)
	probe.queue_free()
	await get_tree().physics_frame

	# 2) Item vs item: a first bundle comes to rest on the floor, a
	# second drops onto it from directly above.
	var lower := _spawn_item(300, FLOOR_Y - 64)
	for i in WAIT_FRAMES:
		await get_tree().physics_frame
		if lower.linear_velocity.length() < 2.0:
			break
	_check("the lower item rests on the floor",
		is_instance_valid(lower)
			and absf(lower.global_position.y - (FLOOR_Y - 52.0)) < 16.0)
	var upper := _spawn_item(300, FLOOR_Y - 260)
	for i in WAIT_FRAMES:
		await get_tree().physics_frame
		if is_instance_valid(upper) and upper.linear_velocity.length() < 2.0:
			break
	_check("the upper item rests ON the lower one (no overlap, no pass-through)",
		is_instance_valid(upper) and is_instance_valid(lower)
			and lower.global_position.distance_to(upper.global_position)
			>= LevelItem.SIZE - 8.0)
	_check("item-item contact detonates nothing",
		is_instance_valid(upper) and is_instance_valid(lower))

	# 3) Item vs projectile: a rocket flies into a floating item and its
	# contact detonation destroys the 1-HP item (blast 90 >= the gap).
	var floating := _spawn_item(500, 120)
	var rocket := ProjectileBody.new()
	rocket.setup(ProjectileBody.Kind.ROCKET, Vector2(700, 0), 35, 3.0,
		Vector2(22, 8), Color(0.9, 0.35, 0.15, 1), 90.0, 1.0)
	rocket.global_position = Vector2(330, 120)
	add_child(rocket)
	for i in WAIT_FRAMES:
		await get_tree().physics_frame
		if not is_instance_valid(floating):
			break
	_check("a rocket hitting an item destroys it on contact",
		not is_instance_valid(floating))
	if is_instance_valid(rocket):
		rocket.queue_free()

	# 4) Item vs character: a figure-like body (layer 8, player_team,
	# health 100) stands on the floor; a bundle dropped onto its head
	# is TAKEN on contact — two 64 px bodies touch at about SIZE px
	# between centres, farther than the 0.75 * SIZE pickup radius, so
	# without contact pickup the bundle would balance on the head
	# forever instead of being taken.
	var fig_script := GDScript.new()
	fig_script.source_code = "extends CharacterBody2D\nvar health := 100\n"
	fig_script.reload()
	var figure := CharacterBody2D.new()
	figure.set_script(fig_script)
	figure.collision_layer = 8
	figure.collision_mask = 0
	figure.add_to_group("player_team")
	var fig_shape := CollisionShape2D.new()
	var fig_rect := RectangleShape2D.new()
	fig_rect.size = Vector2(LevelItem.SIZE, LevelItem.SIZE)
	fig_shape.shape = fig_rect
	figure.add_child(fig_shape)
	figure.global_position = Vector2(700, FLOOR_Y - 52.0 - LevelItem.SIZE / 2.0)
	add_child(figure)
	var inv: Node = get_node("/root/WeaponInventory")
	var uses_before := 0
	for w in [0, 1, 2, 4, 5, 6]:
		uses_before += int(inv.weapon_uses_left("player", w))
	var drop := LevelItem.new()
	drop.kind = LevelItem.Kind.WEAPON_BUNDLE
	drop.global_position = Vector2(700, FLOOR_Y - 260.0)
	add_child(drop)
	var taken := false
	for i in 240:
		await get_tree().physics_frame
		if not is_instance_valid(drop):
			taken = true
			break
	_check("a bundle landing on a figure's head is taken on contact",
		taken and is_instance_valid(figure))
	var uses_after := 0
	for w in [0, 1, 2, 4, 5, 6]:
		uses_after += int(inv.weapon_uses_left("player", w))
	_check("the contact pickup grants the bundle to the team",
		uses_after == uses_before + 1)

	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE374 ALL OK")
		get_tree().quit(0)
	else:
		for what in _fails:
			push_error("ISSUE374 FAIL: " + what)
		get_tree().quit(1)
