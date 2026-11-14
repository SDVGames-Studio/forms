extends Node
## Regression check for issue #359: the railgun.
##
##  1. DAMAGE: the charge scales the damage — 60 on an instant tap,
##     105 at half charge, 150 at full charge (no falloff: charge only);
##  2. BEAM COLOR: a tap keeps the iridescent rainbow (first stop red,
##     none white), a full charge turns every stop pure white;
##  3. BUDGET: the railgun joins WEAPONS at index 6 with 1 shot per turn
##     and exactly ONE use per team per round (5 for the standard
##     weapons, the spear stays infinite);
##  4. HITSCAN: the beam is instant — a figure on the aim line takes the
##     damage in the same frame the trigger is released, and a Line2D
##     tracer (with the 7-stop gradient) appears and frees itself after
##     the 1-second linger, releasing the turn-effects gate with it;
##  5. FIRST HIT STOPS THE BEAM: terrain between the shooter and a
##     figure absorbs the shot — the figure behind the wall is untouched.
##
## Run headless: godot --headless res://tests/test_issue359.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")

## Weapon slot order (Weapon.gd): 6 = railgun.
const WEAPON_SLOT_RAILGUN := 6

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A figure that records every hit — stands in for a real character.
class DamageProbe extends CharacterBody2D:
	var taken := 0

	func take_damage(amount: int, _attacker: Node2D = null) -> void:
		taken += amount


func _make_weapon() -> Node2D:
	var shooter := Node2D.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _make_probe(at: Vector2) -> DamageProbe:
	var probe := DamageProbe.new()
	probe.collision_layer = 8
	probe.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 48)
	shape.shape = rect
	probe.add_child(shape)
	add_child(probe)
	probe.global_position = at
	return probe


func _make_wall(at: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = at


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Damage scales with the charge: 60 / 105 / 150.
	_check(WeaponScript.railgun_damage(0.0) == 60,
			"an instant tap must deal the 60 base damage")
	_check(WeaponScript.railgun_damage(0.5) == 105,
			"half charge must deal 105")
	_check(WeaponScript.railgun_damage(1.0) == 150,
			"a full charge must deal 150")

	# 2) The beam's gradient: rainbow on a tap, white at full charge.
	var tap: PackedColorArray = WeaponScript.railgun_beam_colors(0.0)
	var full: PackedColorArray = WeaponScript.railgun_beam_colors(1.0)
	_check(tap.size() == 7 and tap[0] == Color.RED
			and not tap.has(Color.WHITE),
			"a plain shot must keep the iridescent rainbow (7 stops)")
	var all_white := full.size() == 7
	for color in full:
		all_white = all_white and color.is_equal_approx(Color.WHITE)
	_check(all_white,
			"a full charge must turn the whole line white")

	# 3) Inventory wiring: slot 6, 1 shot per turn, ONE use per team.
	_check(WeaponInventory.WEAPONS[WEAPON_SLOT_RAILGUN] == "Railgun",
			"the railgun must sit at weapon slot 6")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_RAILGUN] == 1,
			"the railgun must allow one shot per turn")
	WeaponInventory.reset_uses()
	var team := TurnController.TEAM_PLAYER
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_RAILGUN) == 1,
			"each team must start the round with exactly ONE railgun shot")
	_check(WeaponInventory.weapon_uses_left(team, 0) == 5,
			"the standard weapons keep their 5 uses")
	_check(WeaponInventory.weapon_uses_left(team,
			WeaponInventory.WEAPON_SPEAR) == -1,
			"the spear stays unlimited")
	WeaponInventory.spend_weapon(team, WEAPON_SLOT_RAILGUN)
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_RAILGUN) == 0
			and not WeaponInventory.can_spend_weapon(team,
					WEAPON_SLOT_RAILGUN),
			"after the single use the railgun budget must be spent")
	WeaponInventory.reset_uses()

	# 4) Hitscan: the figure is damaged instantly and the tracer beam
	# appears, lingers, and frees itself (with its turn-effects gate).
	var gun := _make_weapon()
	var probe := _make_probe(Vector2(400, 0))
	await get_tree().physics_frame
	gun._fire_railgun(1.0)
	_check(probe.taken == 150,
			"the beam must hit the figure on the aim line for the full 150")
	var beam: Line2D = get_node_or_null("RailgunBeam")
	var gate: Node = get_node_or_null("RailgunBeamGate")
	_check(beam != null and beam.gradient != null
			and beam.gradient.colors.size() == 7,
			"the thick tracer Line2D with the 7-stop gradient must appear")
	_check(gate != null,
			"the turn-effects gate must hold the handover while the beam shows")
	await get_tree().create_timer(1.7).timeout
	_check(not is_instance_valid(beam) and not is_instance_valid(gate),
			"the beam must disappear after its one-second linger")

	# 5) Terrain stops the beam: the figure behind the wall is untouched.
	_make_wall(Vector2(200, 0))
	await get_tree().physics_frame
	gun._fire_railgun(0.0)
	_check(probe.taken == 150,
			"a wall between shooter and figure must absorb the shot")
	var stopped: Line2D = get_node_or_null("RailgunBeam")
	_check(stopped != null and stopped.points[1].x < 250.0,
			"the beam must end at the wall, not run through it")

	if failures == 0:
		print("PASS: issue #359 railgun")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
