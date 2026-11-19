extends Node
## Regression check for issue #656: the entrenching shovel.
##
##  1. REGISTRY: the shovel joins WEAPONS at index 10 ("Entrenching
##     Shovel", key E = the weapon_11 InputMap action) with FIVE swings
##     per turn, LESS range than the spear, damage 20% of the spear's,
##     and ENDLESS uses (never on the team budget, like the spear); the
##     training scaffold's attack head grew to 1 + 11 weapon slots;
##  2. MELEE: one swing damages a figure inside the shovel's reach for
##     SHOVEL_DAMAGE; a figure past SHOVEL_RANGE (but inside the
##     spear's) stays untouched;
##  3. DIG: a swing carves the upright ellipse in front — a destructible
##     chunk at the dig spot is destroyed, chunks sideways of it and
##     past its poles (outside the ellipse half width / half height) survive;
##  4. ENDLESS: uses_left stays -1 and can_spend stays true after many
##     spends.
##
## Run headless: godot --headless res://tests/test_issue656.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")

## Weapon slot order (Weapon.gd): 10 = entrenching shovel.
const WEAPON_SLOT_SHOVEL := 10

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A stand-in victim: plain Node2D with health + take_damage (the
## melee corridor only duck-types those, like the saw/bat tests).
class FakeFigure extends Node2D:
	var health := 100

	func take_damage(damage: int) -> void:
		health -= damage


func _make_weapon() -> Node2D:
	var shooter := Node2D.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _make_chunk(at: Vector2, size: Vector2) -> Node:
	var chunk: Node2D = load("res://scripts/DestructibleGround.gd").new()
	chunk.rect_size = size
	chunk.position = at
	add_child(chunk)
	return chunk


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Registry wiring: slot 10, key E action, five swings, endless
	# uses, the melee/dig constants, the RL attack head.
	_check(WeaponInventory.WEAPONS[WEAPON_SLOT_SHOVEL] == "Entrenching Shovel",
			"the entrenching shovel must sit at weapon slot 10")
	_check(InputMap.has_action("weapon_11"),
			"the weapon_11 hotkey action (key E) must exist")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_SHOVEL] == 5,
			"the entrenching shovel must allow five swings per turn")
	_check(WeaponScript.SHOVEL_RANGE < WeaponScript.SPEAR_RANGE,
			"the shovel's range must be LESS than the spear's")
	_check(WeaponScript.SHOVEL_DAMAGE == int(0.2 * WeaponScript.SPEAR_DAMAGE),
			"the shovel's damage must be 20%% of the spear's shot damage")
	WeaponInventory.reset_uses()
	var team := TurnController.TEAM_PLAYER
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_SHOVEL) == -1,
			"the shovel's uses are endless (-1) like the spear's")
	for i in 12:
		WeaponInventory.spend_weapon(team, WEAPON_SLOT_SHOVEL)
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_SHOVEL) == -1
			and WeaponInventory.can_spend_weapon(team, WEAPON_SLOT_SHOVEL),
			"spending never touches the endless shovel budget")
	WeaponInventory.reset_uses()
	_check(1 + WeaponInventory.WEAPONS.size() == 12,
			"the RL attack head grew to 1 + 11 weapon slots")

	# 2) Melee: the dig spot sits SHOVEL_DIG_OFFSET ahead of a bare
	# Node2D shooter (aim = +x, vertical = +y, _frame_up fallback).
	var gun := _make_weapon()
	var victim := FakeFigure.new()
	victim.position = gun.get_parent().global_position + Vector2(40.0, 0.0)
	add_child(victim)
	victim.add_to_group("enemy_team")
	var beyond := FakeFigure.new()
	beyond.position = gun.get_parent().global_position + Vector2(60.0, 0.0)
	add_child(beyond)
	beyond.add_to_group("enemy_team")
	gun._swing_shovel()
	_check(victim.health == 100 - WeaponScript.SHOVEL_DAMAGE,
			"a figure within the shovel's reach takes SHOVEL_DAMAGE (got %d)"
			% victim.health)
	_check(beyond.health == 100,
			"a figure past the shovel's (shorter) reach stays untouched")
	victim.queue_free()
	beyond.queue_free()

	# 3) Dig: the ellipse centre sits SHOVEL_DIG_OFFSET ahead; a chunk
	# there is destroyed, chunks sideways (past half the ellipse width)
	# and above (past half its height) survive.
	var shooter := gun.get_parent() as Node2D
	var dig_centre := shooter.global_position \
			+ Vector2(WeaponScript.SHOVEL_DIG_OFFSET, 0.0)
	var inside := _make_chunk(dig_centre, Vector2(20, 20))
	var beside := _make_chunk(dig_centre + Vector2(40.0, 0.0), Vector2(20, 20))
	var pole := _make_chunk(dig_centre + Vector2(0.0, 52.0), Vector2(20, 20))
	gun._swing_shovel()
	for i in 4:
		await get_tree().physics_frame
	_check(not is_instance_valid(inside) or not inside.is_inside_tree(),
			"a destructible chunk at the dig spot must be carved away")
	_check(is_instance_valid(beside) and beside.is_inside_tree(),
			"a chunk sideways of the ellipse (past its half width) survives")
	_check(is_instance_valid(pole) and pole.is_inside_tree(),
			"a chunk past the ellipse's pole (beyond its half height) survives")

	# 4) Endless budget re-check after the swings: still selectable.
	_check(WeaponInventory.held_weapon_for(team) != WEAPON_SLOT_SHOVEL
			or WeaponInventory.can_spend_weapon(team, WEAPON_SLOT_SHOVEL),
			"the endless shovel stays payable for every team")
	_finish()


func _finish() -> void:
	if failures > 0:
		print("ISSUE656 ok=false (%d failures)" % failures)
		get_tree().quit(1)
		return
	print("ISSUE656 ok=true")
	get_tree().quit(0)
