extends Node
## Regression check for issue #536: "pistol and shotgun don't shoot —
## there is a shot's sound, flash but the bullet doesn't come out."
##
## The bullets DID fire: on the first level every shot aimed at the
## enemy side landed on TEAMMATE2 standing ~100 px in the line of fire —
## friendly fire (#57, by design) — and the pellet vanished with NO
## impact feedback, hidden under the 0.12 s muzzle flash: exactly
## "sound, flash, no bullet". The fix marks the impact with a hit spark
## (Projectile._on_body_entered).
##
##  1. the bullet really COMES OUT: a pistol shot into open air keeps a
##     live projectile flying well past the muzzle-flash window;
##  2. the blocked shot still lands on the figure in the line of fire
##     (friendly fire intact) — health drops by the bullet damage;
##  3. the impact now SHOWS: a shot-light spark flashes at the hit point
##     the moment the bullet lands (pistol bullet AND shotgun volley).
##
## All shots fire from the Player (its gravity frame near the level
## start is flat: tangent (1, 0)), straight right at Teammate2.
##
## Run headless: godot --headless res://tests/test_issue536.tscn
## Exit code 0 = pass.

const LevelScene := preload("res://scenes/levels/Level.tscn")

## Weapon slot order (Weapon.gd): 0 = shotgun, 7 = pistol.
const WEAPON_SLOT_SHOTGUN := 0
const WEAPON_SLOT_PISTOL := 7
const PELLET_DAMAGE := 6
const PISTOL_DAMAGE := 10

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## True when a hit-spark light (a DIRECT child of the level, like the
## impact flash and the muzzle flash — unlike the glow that travels as
## the projectile's child) sits within 30 px of `figure`.
func _spark_near(level: Node, figure: Node2D) -> bool:
	for light in get_tree().get_nodes_in_group("shot_lights"):
		if is_instance_valid(light) and light.get_parent() == level \
				and (light as Node2D).global_position.distance_to(
					figure.global_position) < 30.0:
			return true
	return false


func _ready() -> void:
	await get_tree().physics_frame
	var level: Node = LevelScene.instantiate()
	add_child(level)
	for _i in 10:
		await get_tree().physics_frame
	var player := level.get_node("Player") as Node2D
	var mate2 := level.get_node("Teammate2") as Node2D
	var gun := player.get_node("Weapon")
	# Freeze the panel sync: Weapon._physics_process overwrites a
	# CONTROLLED member's selected_weapon from the team panel every frame
	# (WeaponInventory.held_weapon_for) until the first shot of the turn
	# locks it — locking the player up front keeps OUR weapon choice in
	# force, so the test's shots are deterministic.
	WeaponInventory.lock_for(player)

	# --- 1) The bullet comes out: pistol into open air (up-left). -----
	gun.selected_weapon = WEAPON_SLOT_PISTOL
	gun._facing = -1.0
	player.set("view_angle", 0.6)
	var committed_air: bool = gun.npc_fire()
	for _i in 10:
		await get_tree().physics_frame
	var flying := 0
	for p in get_tree().get_nodes_in_group("projectiles"):
		if is_instance_valid(p):
			flying += 1
	_check(committed_air and flying >= 1,
			"the pistol bullet must spawn and keep flying in open air")

	# --- 2)+3) Pistol straight right: the bullet lands on Teammate2 ---
	# (~110 px ahead, in the line of fire) — damage AND a hit spark. ---
	gun._shot_delay_left = 0.0
	gun._cooldown_left = 0.0
	var hp0: int = mate2.get("health")
	gun._facing = 1.0
	player.set("view_angle", 0.0)
	var committed_pistol: bool = gun.npc_fire()
	var spark_pistol := false
	for _i in 15:
		await get_tree().physics_frame
		if _spark_near(level, mate2):
			spark_pistol = true
	_check(committed_pistol, "the blocked pistol shot must commit")
	_check(int(mate2.get("health")) == hp0 - PISTOL_DAMAGE,
			"the bullet must land on the figure in the line of fire (hp %d -> %d)"
			% [hp0, int(mate2.get("health"))])
	_check(spark_pistol, "a hit spark must flash where the bullet lands")

	# --- Same for the shotgun volley: 5 pellets into Teammate2. -------
	gun._shot_delay_left = 0.0
	gun._cooldown_left = 0.0
	var hp1: int = mate2.get("health")
	gun.selected_weapon = WEAPON_SLOT_SHOTGUN
	var committed_volley: bool = gun.npc_fire()
	var spark_volley := false
	for _i in 15:
		await get_tree().physics_frame
		if _spark_near(level, mate2):
			spark_volley = true
	_check(committed_volley, "the shotgun volley must commit")
	_check(int(mate2.get("health")) == hp1 - 5 * PELLET_DAMAGE,
			"the volley must land on Teammate2 (hp %d -> %d)"
			% [hp1, int(mate2.get("health"))])
	_check(spark_volley, "a hit spark must flash where the pellets land")

	level.queue_free()
	if failures == 0:
		print("PASS: issue #536 pistol/shotgun visible impact")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
