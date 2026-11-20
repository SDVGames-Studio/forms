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
##  4. ANCHOR (rework): the dig spot is fixed in WORLD space by the first
##     swing — a second swing after a SHORT stance shift (under
##     SHOVEL_DIG_REANCHOR) must NOT open a hole where the live aim now
##     points, and a shift past the threshold re-anchors and digs anew.
##     The first delivery re-centred the dig on the aim every swing, so
##     the five swings dragged the hole into a ragged trench;
##  5. SHAPE (rework): the carve is an EXACT ellipse — after one dig into
##     a big slab, every probe inside the ellipse is open ground and
##     every probe outside it (beyond the MIN_PIECE sliver margin) is
##     still covered by surviving pieces. The first delivery stamped a
##     fan of capped circles, which under-carved the poles and left
##     ragged ledges (the owner's screenshot);
##  6. ENDLESS: uses_left stays -1 and can_spend stays true after many
##     spends;
##  7. ENTERABLE (rework #2): the dig's horizontal diameter is the FULL
##     figure width (64) — the issue text's "half of character's width"
##     (32) was narrower than the figure's 48 px collider capsule, so
##     the dug "tunnel" was a notch the character could never move
##     into (the owner's screenshot). The mouth now spans the capsule's
##     full 48 px shoulders with clearance.
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


## True when some surviving destructible piece still covers the point
## (rectangle pieces only — the dig spawns no polygon/ring pieces).
func _covered(point: Vector2) -> bool:
	for ground in get_tree().get_nodes_in_group("destructible_ground"):
		var piece := ground as Node2D
		if piece == null or not is_instance_valid(piece):
			continue
		if not (piece.get("ring_outer") > 0.0) \
				and piece.get("polygon") != null \
				and piece.get("polygon").size() < 3:
			var rect := Rect2(piece.position - piece.rect_size / 2.0,
					piece.rect_size)
			if rect.has_point(point):
				return true
	return false


func _settle() -> void:
	for i in 4:
		await get_tree().physics_frame


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
	# Node2D shooter (aim = +x, vertical = -y, _frame_up fallback).
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

	# 3) Dig (a FRESH weapon at a fresh stance — the melee swing above
	# already fixed and carved this gun's anchor): the ellipse centre
	# sits SHOVEL_DIG_OFFSET ahead; a chunk there is destroyed, chunks
	# sideways (past half the ellipse width — the FULL figure width
	# since rework #2) and beyond the poles (past half its height)
	# survive.
	var gun_b := _make_weapon()
	var shooter_b := gun_b.get_parent() as Node2D
	shooter_b.position = Vector2(500.0, 0.0)
	var dig_centre := shooter_b.global_position \
			+ Vector2(WeaponScript.SHOVEL_DIG_OFFSET, 0.0)
	var inside := _make_chunk(dig_centre, Vector2(20, 20))
	var beside := _make_chunk(dig_centre + Vector2(56.0, 0.0), Vector2(20, 20))
	var pole_up := _make_chunk(dig_centre + Vector2(0.0, 52.0), Vector2(20, 20))
	var pole_down := _make_chunk(dig_centre + Vector2(0.0, -52.0), Vector2(20, 20))
	gun_b._swing_shovel()
	await _settle()
	_check(not is_instance_valid(inside) or not inside.is_inside_tree(),
			"a destructible chunk at the dig spot must be carved away")
	_check(is_instance_valid(beside) and beside.is_inside_tree(),
			"a chunk sideways of the ellipse (past its half width) survives")
	_check(is_instance_valid(pole_up) and pole_up.is_inside_tree(),
			"a chunk past the ellipse's pole (beyond its half height) survives")
	_check(is_instance_valid(pole_down) and pole_down.is_inside_tree(),
			"a chunk past the ellipse's other pole survives")

	# 4) ANCHOR: the first swing fixes the dig in world space. A second
	# swing after a stance shift UNDER SHOVEL_DIG_REANCHOR must not open
	# the hole the live aim now points at; a shift past the threshold
	# re-anchors and digs at the new spot.
	var gun_c := _make_weapon()
	var shooter_c := gun_c.get_parent() as Node2D
	shooter_c.position = Vector2(1000.0, 0.0)
	var first := _make_chunk(Vector2(1048.0, 0.0), Vector2(20, 20))
	gun_c._swing_shovel()
	await _settle()
	_check(not is_instance_valid(first) or not first.is_inside_tree(),
			"the first swing must dig at the anchored spot")
	shooter_c.position = Vector2(1030.0, 0.0)
	var dragged := _make_chunk(Vector2(1078.0, 0.0), Vector2(20, 20))
	gun_c._swing_shovel()
	await _settle()
	_check(is_instance_valid(dragged) and dragged.is_inside_tree(),
			"a swing within the re-anchor distance must NOT move the hole "
			+ "to the new aim spot (the dig stays one ellipse)")
	shooter_c.position = Vector2(1100.0, 0.0)
	var fresh := _make_chunk(Vector2(1148.0, 0.0), Vector2(20, 20))
	gun_c._swing_shovel()
	await _settle()
	_check(not is_instance_valid(fresh) or not fresh.is_inside_tree(),
			"a stance shift past SHOVEL_DIG_REANCHOR starts a fresh dig")

	# 5) SHAPE: one dig into a big slab leaves an EXACT elliptical hole —
	# inside probes (clear of the MIN_PIECE sliver margin) are open
	# ground, outside probes are still covered, and the slab's far
	# corners survive untouched.
	var gun_d := _make_weapon()
	var shooter_d := gun_d.get_parent() as Node2D
	shooter_d.position = Vector2(2000.0, 0.0)
	var shape_centre := shooter_d.global_position \
			+ Vector2(WeaponScript.SHOVEL_DIG_OFFSET, 0.0)
	_make_chunk(shape_centre, Vector2(200, 120))
	gun_d._swing_shovel()
	await _settle()
	var half_w := WeaponScript.SHOVEL_DIG_WIDTH / 2.0
	var half_h := WeaponScript.SHOVEL_DIG_HEIGHT / 2.0
	for probe in [Vector2(0, 0), Vector2(0, 24), Vector2(0, -24),
			Vector2(8, 0), Vector2(-8, 0), Vector2(8, 12), Vector2(-8, -12),
			Vector2(4, 20), Vector2(-4, -20),
			Vector2(24, 0), Vector2(-24, 0)]:
		var p: Vector2 = shape_centre + probe
		_check(not _covered(p), "probe %s must sit INSIDE the dug ellipse "
				% probe + "(open ground after the dig)")
	for probe in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40),
			Vector2(0, -40), Vector2(40, 40), Vector2(-40, -40)]:
		var p: Vector2 = shape_centre + probe
		_check(_covered(p), "probe %s must stay OUTSIDE the dug ellipse "
				% probe + "(still covered ground)")
	for probe in [Vector2(90, 50), Vector2(-90, -50)]:
		var p: Vector2 = shape_centre + probe
		_check(_covered(p), "the slab's far corner %s survives untouched"
				% probe)
	_check(half_w == 32.0 and half_h == 32.0,
			"the dig half axes are the full figure width/height (32 x 32) "
			+ "— rework #2: a 16 px half width could never admit the "
			+ "48 px collider capsule")

	# 6) Endless budget re-check after the swings: still selectable.
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
