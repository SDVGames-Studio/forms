extends Node
## Regression check for issue #526: the pistol.
##
##  1. REGISTRY: the pistol joins WEAPONS at index 7 ("Pistol", key P)
##     with THREE shots per turn — more than any other weapon — and the
##     standard 5 uses per team per round (spendable to zero, restored
##     by the round reset);
##  2. ACCURACY: one trigger pull spawns exactly ONE projectile flying
##     DEAD STRAIGHT along the aim (zero spread), while the shotgun's
##     trigger pull spawns 5 pellets fanned around the aim;
##  3. DAMAGE: 10 per bullet — every pistol shot deals LESS damage than
##     a shotgun trigger pull (5 pellets × 6 = 30).
##
## Run headless: godot --headless res://tests/test_issue526.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const ProjectileScript := preload("res://scripts/Projectile.gd")

## Weapon slot order (Weapon.gd): 7 = pistol.
const WEAPON_SLOT_PISTOL := 7

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A shooter without aim_dir — the weapon's aim fallback is the facing
## direction (1, 0), so every expected velocity is (+speed, 0).
func _make_weapon() -> Node2D:
	var shooter := Node2D.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


## Projectiles currently parented to this test root (the weapon spawns
## them into its parent's parent, which is this node).
func _spawned() -> Array:
	var out: Array = []
	for child in get_children():
		if child.get_script() == ProjectileScript:
			out.append(child)
	return out


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 1) Registry wiring: slot 7, three shots per turn, 5 uses per round.
	_check(WeaponInventory.WEAPONS[WEAPON_SLOT_PISTOL] == "Pistol",
			"the pistol must sit at weapon slot 7")
	_check(WeaponScript.SHOTS_PER_TURN[WEAPON_SLOT_PISTOL] == 3,
			"the pistol must allow three shots per turn")
	var max_shots := 0
	for count in WeaponScript.SHOTS_PER_TURN:
		max_shots = maxi(max_shots, int(count))
	_check(max_shots == 3 and int(WeaponScript.SHOTS_PER_TURN[
			WEAPON_SLOT_PISTOL]) == max_shots,
			"three must be the highest per-turn shot count, held by the pistol")
	WeaponInventory.reset_uses()
	var team := TurnController.TEAM_PLAYER
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_PISTOL)
			== WeaponInventory.USES_PER_ITEM,
			"the pistol starts the round with the standard 5 uses")
	_check(WeaponInventory.can_spend_weapon(team, WEAPON_SLOT_PISTOL),
			"a fresh round must afford a pistol shot")
	for i in WeaponInventory.USES_PER_ITEM:
		WeaponInventory.spend_weapon(team, WEAPON_SLOT_PISTOL)
	_check(WeaponInventory.weapon_uses_left(team, WEAPON_SLOT_PISTOL) == 0
			and not WeaponInventory.can_spend_weapon(team, WEAPON_SLOT_PISTOL),
			"after five uses the pistol budget must be spent")
	WeaponInventory.reset_uses()

	# 2) Accuracy: ONE dead-straight bullet vs the shotgun's 5-pellet fan.
	var pistol := _make_weapon()
	pistol._fire_pistol()
	var pistol_shots := _spawned()
	_check(pistol_shots.size() == 1,
			"one pistol trigger pull must spawn exactly one bullet (got %d)"
			% pistol_shots.size())
	if pistol_shots.size() == 1:
		var bullet: Area2D = pistol_shots[0]
		_check(bullet.velocity == Vector2(WeaponScript.PISTOL_SPEED, 0.0),
				"the bullet must fly dead straight along the aim, no spread (got %s)"
				% bullet.velocity)
		# 3) Damage: cheaper per shot than the shotgun volley.
		_check(bullet.damage == WeaponScript.PISTOL_DAMAGE,
				"the bullet must carry the pistol damage")
	_check(WeaponScript.PISTOL_DAMAGE
			< 5 * WeaponScript.PELLET_DAMAGE,
			"one pistol shot must deal less than a shotgun trigger pull (%d vs %d)"
			% [WeaponScript.PISTOL_DAMAGE, 5 * WeaponScript.PELLET_DAMAGE])
	for shot in pistol_shots:
		shot.queue_free()
	await get_tree().physics_frame  # let the freed bullet leave the tree

	var shotgun := _make_weapon()
	shotgun._fire_shotgun()
	var pellets := _spawned()
	_check(pellets.size() == 5,
			"the shotgun comparison volley must spawn its 5 pellets")
	var fanned := 0
	for pellet in pellets:
		if (pellet as Area2D).velocity != Vector2(
				WeaponScript.PELLET_SPEED, 0.0):
			fanned += 1
	_check(fanned >= 4,
			"the shotgun must fan its pellets around the aim (%d of 5 off-axis)"
			% fanned)
	for pellet in pellets:
		pellet.queue_free()

	# Held-visual wiring: weapon 7 maps to its own HELD_STYLES entry.
	pistol.selected_weapon = WEAPON_SLOT_PISTOL
	_check(pistol._held_style_index() == 8
			and WeaponScript.HELD_STYLES.size() == 9,
			"the pistol must have its own held-weapon style (index 8)")

	if failures == 0:
		print("PASS: issue #526 pistol")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
