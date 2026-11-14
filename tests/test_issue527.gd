extends Node
## Regression check for issue #527: the baseball bat.
##
##  1. REGISTRY: the bat joins WEAPONS at index 8 ("Baseball Bat", key B)
##     with ONE swing per turn and the standard 5 uses per team per round
##     (spendable to zero, restored by the round reset); weapon bundles
##     can roll it at the mine/pistol tier;
##  2. MELEE: the swing damages EVERY figure the corridor in front of the
##     wielder reaches (BAT_RANGE along the aim, BAT_LATERAL sideways) —
##     friendly fire included, the wielder itself exempt; a figure beyond
##     the range or off to the side is missed;
##  3. KNOCKBACK: the hit not only damages, it LAUNCHES the victim along
##     the shot direction (an acceleration that keeps pushing for
##     BAT_KNOCKBACK_TIME), and while it runs the turn-effect gate keeps
##     the post-shot handover waiting — until the push ends and the gate
##     is released.
##  4. POWER (#527 rework): the bat is a CHARGED weapon — the hold-F
##     charge picks the swing power, scaling the launch speed from 40%
##     (a tap) to the full BAT_KNOCKBACK_SPEED (the full hold), so a
##     full-charge swing sends the victim far further.
##
## Run headless: godot --headless res://tests/test_issue527.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const LevelItemScript := preload("res://scripts/LevelItem.gd")

## Weapon slot order (Weapon.gd): 8 = baseball bat.
const WEAPON_SLOT_BAT := 8

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A stand-in victim: plain Node2D with health + take_damage + velocity,
## so the bat's push takes the direct-offset branch (deterministic in
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

	# 1) Registry wiring: slot 8, one swing per turn, 5 uses per round,
	# bundle tier.
	_check(WeaponInventory.WEAPONS[WEAPON_SLOT_BAT] == "Baseball Bat",
			"the baseball bat must sit at weapon slot 8")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_BAT] == 1,
			"the baseball bat must allow one swing per turn")
	WeaponInventory.reset_uses()
	var team := TurnController.TEAM_PLAYER
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_BAT)
			== WeaponInventory.USES_PER_ITEM,
			"the baseball bat starts the round with the standard 5 uses")
	for i in WeaponInventory.USES_PER_ITEM:
		WeaponInventory.spend_weapon(team, WEAPON_SLOT_BAT)
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_BAT) == 0
			and not WeaponInventory.can_spend_weapon(team, WEAPON_SLOT_BAT),
			"after five uses the baseball bat budget must be spent")
	WeaponInventory.reset_uses()
	_check(int(LevelItemScript.WEAPON_BUNDLE_WEIGHTS.get(WEAPON_SLOT_BAT, 0)) == 3,
			"weapon bundles must roll the bat at the mine/pistol tier (3)")

	# 2) Melee: a figure in front is damaged and launched along the aim.
	var gun := _make_weapon()
	var victim := FakeFigure.new()
	victim.position = Vector2(60.0, 0.0)  # ahead along the aim (1, 0)
	add_child(victim)
	victim.add_to_group("enemy_team")
	gun._swing_bat()
	_check(victim.health == 100 - WeaponScript.BAT_DAMAGE,
			"the swing must damage the figure it reaches (got %d, want %d)"
			% [victim.health, 100 - WeaponScript.BAT_DAMAGE])
	var gated := get_tree().get_nodes_in_group(TurnController.EFFECT_GROUP)
	_check(gated.size() == 1,
			"the knockback must gate the turn handover while it runs")
	# Let the weapon's _physics_process tick the push a few times.
	for i in 3:
		await get_tree().physics_frame
	_check(victim.position.x > 60.0,
			"the hit figure must be pushed along the shot direction (x=%f)"
			% victim.position.x)
	_check(victim.velocity.x > 0.0,
			"the hit figure must carry the push velocity (got %s)"
			% victim.velocity)
	_check(absf(victim.position.y) < 0.001,
			"the push stays along the aim axis (y=%f)" % victim.position.y)

	# 3) The push is an ACCELERATION with a duration — after
	# BAT_KNOCKBACK_TIME it ends and the gate is released.
	for i in 30:
		await get_tree().physics_frame
		if gun._bat_push_left <= 0.0:
			break
	await get_tree().physics_frame  # let the queued gate actually leave the tree
	_check(gun._bat_push_left == 0.0,
			"the knockback must end after its duration")
	_check(get_tree().get_nodes_in_group(TurnController.EFFECT_GROUP).is_empty(),
			"the turn-effect gate must be released once the push ends")
	var settled_x := victim.position.x
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(absf(victim.position.x - settled_x) < 0.001,
			"the body stops being shoved once the knockback ended")
	victim.queue_free()

	# 4) Miss cases: beyond the range, and off the corridor sideways.
	var far := FakeFigure.new()
	far.position = Vector2(WeaponScript.BAT_RANGE + 30.0, 0.0)
	add_child(far)
	far.add_to_group("enemy_team")
	var aside := FakeFigure.new()
	aside.position = Vector2(40.0, WeaponScript.BAT_LATERAL + 10.0)
	add_child(aside)
	aside.add_to_group("player_team")  # friendly fire corridor applies too
	var fresh := _make_weapon()
	fresh._swing_bat()
	_check(far.health == 100 and aside.health == 100,
			"figures beyond the range or off the corridor must be missed")
	_check(get_tree().get_nodes_in_group(TurnController.EFFECT_GROUP).is_empty(),
			"a swing that hits nothing opens no turn-effect gate")
	far.queue_free()
	aside.queue_free()
	await get_tree().physics_frame  # let the misses settle

	# Held-visual wiring: weapon 8 maps to its own HELD_STYLES entry.
	fresh.selected_weapon = WEAPON_SLOT_BAT
	_check(fresh._held_style_index() == 9,
			"the baseball bat must have its own held-weapon style (index 9)")

	# 5) Power scaling (#527 rework): the hold-F charge picks the swing
	# power — a tap launches at MIN_SHOT_POWER of the knockback speed,
	# the full hold at 100%.
	var tap_gun := _make_weapon()
	var tap_victim := FakeFigure.new()
	tap_victim.position = Vector2(60.0, 0.0)
	add_child(tap_victim)
	tap_victim.add_to_group("enemy_team")
	tap_gun._swing_bat(0.0)
	var full_gun := _make_weapon()
	(full_gun.get_parent() as Node2D).position = Vector2(0.0, 500.0)
	var full_victim := FakeFigure.new()
	full_victim.position = Vector2(60.0, 500.0)
	add_child(full_victim)
	full_victim.add_to_group("enemy_team")
	full_gun._swing_bat(1.0)
	_check(absf(tap_gun._bat_push_speed
				- WeaponScript.BAT_KNOCKBACK_SPEED * WeaponScript.MIN_SHOT_POWER) < 0.001,
			"a tapped swing must launch at MIN_SHOT_POWER of the speed (got %f)"
			% tap_gun._bat_push_speed)
	_check(absf(full_gun._bat_push_speed
				- WeaponScript.BAT_KNOCKBACK_SPEED) < 0.001,
			"a full-charge swing must launch at the full speed (got %f)"
			% full_gun._bat_push_speed)
	_check(tap_victim.health == 100 - WeaponScript.BAT_DAMAGE
			and full_victim.health == 100 - WeaponScript.BAT_DAMAGE,
			"the charge must scale the launch, not the damage")
	# Wait out both knockbacks, then compare how far each victim flew.
	for i in 40:
		await get_tree().physics_frame
		if tap_gun._bat_push_left <= 0.0 and full_gun._bat_push_left <= 0.0:
			break
	await get_tree().physics_frame
	_check(full_victim.position.x - 60.0 > (tap_victim.position.x - 60.0) * 2.0,
			"a full-charge swing must send the victim far further (tap %f, full %f)"
			% [tap_victim.position.x, full_victim.position.x])
	tap_victim.queue_free()
	full_victim.queue_free()

	if failures == 0:
		print("PASS: issue #527 baseball bat")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
