extends Node
## Regression check for issue #570: the circular saw.
##
##  1. REGISTRY: the saw joins WEAPONS at index 9 ("Circular Saw", key C =
##     the weapon_10 InputMap action) with ONE throw per turn and the
##     standard 5 uses per team per round; weapon bundles can roll it at
##     the mine/pistol/bat tier; the training scaffold's attack head grew
##     to 1 + 10 weapon slots;
##  2. THROW: Weapon._throw_saw spawns a ProjectileBody of Kind.SAW with
##     the mine's lob mechanics (no fuse, no blast);
##  3. SPIN + SUCTION + GRIND: once the saw body is at rest the blade
##     spins for SAW_SPIN_TIME; a figure inside SAW_SUCK_RADIUS is PULLED
##     toward the blade every physics tick and a figure within
##     SAW_CUT_RADIUS takes SAW_CUT_DPS per second while the spin runs;
##  4. END: when the spin time is spent the saw frees itself (the turn
##     handover never waits on it forever).
##
## Run headless: godot --headless res://tests/test_issue570.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const BodyScript := preload("res://scripts/ProjectileBody.gd")
const LevelItemScript := preload("res://scripts/LevelItem.gd")

## Weapon slot order (Weapon.gd): 9 = circular saw.
const WEAPON_SLOT_SAW := 9

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A stand-in victim: plain Node2D with health + take_damage + velocity,
## so the saw's pull takes the direct-offset branch (deterministic in
## headless tests — no physics shapes needed).
class FakeFigure extends Node2D:
	var health := 100
	var velocity := Vector2.ZERO

	func take_damage(damage: int) -> void:
		health -= damage


func _make_weapon() -> Node2D:
	var shooter := Node2D.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Registry wiring: slot 9, key C action, one throw per turn,
	# 5 uses per round, bundle tier, RL attack head.
	_check(WeaponInventory.WEAPONS[WEAPON_SLOT_SAW] == "Circular Saw",
			"the circular saw must sit at weapon slot 9")
	_check(InputMap.has_action("weapon_10"),
			"the weapon_10 hotkey action (key C) must exist")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_SAW] == 1,
			"the circular saw must allow one throw per turn")
	WeaponInventory.reset_uses()
	var team := TurnController.TEAM_PLAYER
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_SAW)
			== WeaponInventory.USES_PER_ITEM,
			"the circular saw starts the round with the standard 5 uses")
	for i in WeaponInventory.USES_PER_ITEM:
		WeaponInventory.spend_weapon(team, WEAPON_SLOT_SAW)
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_SAW) == 0
			and not WeaponInventory.can_spend_weapon(team, WEAPON_SLOT_SAW),
			"after five uses the circular saw budget must be spent")
	WeaponInventory.reset_uses()
	_check(int(LevelItemScript.WEAPON_BUNDLE_WEIGHTS.get(WEAPON_SLOT_SAW, 0)) == 3,
			"weapon bundles must roll the saw at the mine/pistol/bat tier (3)")
	_check(BodyScript.BOUNCE.has(BodyScript.Kind.SAW),
			"the SAW kind must be registered in BOUNCE")
	_check(1 + WeaponInventory.WEAPONS.size() == 11,
			"the RL attack head grew to 1 + 10 weapon slots")

	# 2) Throw: a SAW body leaves the weapon with the mine's lob.
	var gun := _make_weapon()
	gun._throw_saw(1.0)
	var bodies := get_tree().get_nodes_in_group("projectiles") \
			.filter(func(n): return n is RigidBody2D and n.get_script() == BodyScript)
	var saw: RigidBody2D = null
	for body in bodies:
		if body.kind == BodyScript.Kind.SAW:
			saw = body
	_check(saw != null, "_throw_saw must spawn a SAW projectile body")
	if saw == null:
		_finish()
		return
	_check(saw.is_in_group("projectiles"),
			"a flying saw is a live projectile the turn handover waits for")

	# 3) Rest → spin: force the saw to rest, place a victim inside the
	# suction radius and one far outside it.
	saw.linear_velocity = Vector2.ZERO
	var victim := FakeFigure.new()
	victim.position = saw.global_position + Vector2(80.0, 0.0)
	add_child(victim)
	victim.add_to_group("enemy_team")
	var bystander := FakeFigure.new()
	bystander.position = saw.global_position + Vector2(500.0, 0.0)
	add_child(bystander)
	bystander.add_to_group("enemy_team")
	var spun := false
	for i in 10:
		await get_tree().physics_frame
		if saw.is_saw_spinning():
			spun = true
			break
	_check(spun, "a saw at rest must start spinning")
	# Let the suction drag the victim for a while (0.5 s of ticks: the
	# 80 px gap closes to the 40 px blade in ~0.33 s, the rest grinds).
	for i in 30:
		await get_tree().physics_frame
	if not is_instance_valid(saw):
		_check(false, "the saw must still spin 0.5 s in (SAW_SPIN_TIME is 3 s)")
		_finish()
		return
	var pulled := victim.global_position.distance_to(saw.global_position)
	_check(pulled < 80.0,
			"the spin must SUCK the nearby figure toward the blade (got %f px away)"
			% pulled)
	_check(victim.health < 100,
			"a figure dragged onto the blade must be ground for DPS (got %d)"
			% victim.health)
	_check(bystander.health == 100
			and absf(bystander.global_position.x
					- (saw.global_position.x + 500.0)) < 0.5,
			"a figure beyond SAW_SUCK_RADIUS is neither pulled nor ground")

	# 4) End: spend the spin time — the saw frees itself and the victim
	# stops being pulled.
	if is_instance_valid(saw):
		saw._saw_spin_left = 0.05
	var freed := false
	for i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(saw):
			freed = true
			break
	_check(freed, "after SAW_SPIN_TIME the saw must free itself")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("ISSUE570 ok=true (circular saw: registry, throw, spin, suction, grind, end)")
	else:
		print("ISSUE570 ok=false failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
