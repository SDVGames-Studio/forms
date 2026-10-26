extends Node2D
## Weapon handling for every team member (issue #3, reworked in #49).
##
## Four standard weapons, selectable through the WeaponInventory HUD
## (keys 1–4, HUD on the right side of the screen). The controlled member
## fires with the "shoot" action (F). Each weapon has different physics:
##  1 Shotgun       — spread of 5 fast pellets, short range, low damage each
##  2 Rocket        — fast straight rocket, big blast on impact
##  3 Grenade       — lobbed arc with gravity, explodes on fuse or impact
##  4 Melee spear   — instant short-range thrust hit in front
## Visuals are plain rectangles built in code — no extra assets.

const ProjectileScript := preload("res://Projectile.gd")

const COOLDOWN := 0.3

const PELLET_SPEED := 900.0
const PELLET_LIFETIME := 0.35
const PELLET_DAMAGE := 6
const ROCKET_SPEED := 700.0
const ROCKET_DAMAGE := 35
const ROCKET_BLAST := 90.0
const ROCKET_LIFETIME := 3.0
const GRENADE_SPEED := 550.0
const GRENADE_DAMAGE := 40
const GRENADE_BLAST := 100.0
const GRENADE_FUSE := 1.5
const SPEAR_RANGE := 70.0
const SPEAR_DAMAGE := 25

var _facing := 1.0
var _gravity_dir := 1.0
var _cooldown_left := 0.0

## Issue #99: when an NPC fires a grenade, the weapon lobs it ballistically
## at this target (cleared after one shot). Player grenades keep the
## hand-aimed arc.
var npc_target: Node2D = null

## Issue #67: current aim direction of the wielder (view angle applied).
func _aim() -> Vector2:
	var parent := get_parent() as CharacterBody2D
	if parent != null and parent.has_method("aim_dir"):
		return parent.aim_dir(_facing, _gravity_dir)
	return Vector2(_facing, 0.0)

## Issue #68: visual of the weapon currently held "in hands".
var _held: ColorRect
var _held_style := -1

## Issue #68: size and color of the held weapon per selected weapon index.
const HELD_STYLES: Array = [
	{"size": Vector2(26, 6), "color": Color(0.95, 0.85, 0.3, 1)},   # shotgun
	{"size": Vector2(30, 8), "color": Color(0.9, 0.35, 0.15, 1)},   # rocket
	{"size": Vector2(12, 12), "color": Color(0.3, 0.7, 0.3, 1)},    # grenade
	{"size": Vector2(40, 4), "color": Color(0.8, 0.8, 0.9, 1)},     # spear
]

## Currently selected weapon index (0..3), shared through the inventory HUD.
var selected_weapon := 0


func _ready() -> void:
	_held = ColorRect.new()
	_held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_held)
	_update_held()


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var parent := get_parent() as CharacterBody2D
	var new_facing := _facing
	var new_dir := _gravity_dir
	if parent and parent.velocity.x != 0.0:
		new_facing = signf(parent.velocity.x)
	if parent != null:
		var line_y = parent.get("center_line_y")
		if line_y != null and line_y > 0.0:
			new_dir = 1.0 if parent.global_position.y < line_y else -1.0
	if new_facing != _facing or new_dir != _gravity_dir:
		_facing = new_facing
		_gravity_dir = new_dir
		_update_held()

	# Issue #33: only the controlled team member fires on input, and only
	# during the player team's turn (issue #65).
	if parent != null and parent.get("controlled") == true \
			and TurnController.active_team == TurnController.TEAM_PLAYER:
		selected_weapon = WeaponInventory.selected_weapon
		if Input.is_action_just_pressed("shoot") and _cooldown_left == 0.0:
			_fire()

	# Issue #68: keep the held weapon in sync with selection and facing.
	if selected_weapon != _held_style:
		_update_held()
	# Issue #67: keep the held weapon aligned with the character's view.
	if _held != null and parent != null:
		var aim: Vector2 = parent.aim_dir(_facing, _gravity_dir)
		var style: Dictionary = HELD_STYLES[clampi(selected_weapon, 0, HELD_STYLES.size() - 1)]
		_held.position = aim * 26.0 - style["size"] / 2.0


## Issue #68: draw the currently selected weapon in front of the wielder.
func _update_held() -> void:
	if _held == null:
		return
	_held_style = selected_weapon
	var style: Dictionary = HELD_STYLES[clampi(selected_weapon, 0, HELD_STYLES.size() - 1)]
	var size: Vector2 = style["size"]
	_held.size = size
	_held.position = Vector2(_facing * 26.0, 0.0) - size / 2.0
	_held.color = style["color"]


func _fire() -> void:
	_cooldown_left = COOLDOWN
	match selected_weapon:
		0: _fire_shotgun()
		1: _fire_rocket()
		2: _fire_grenade()
		3: _thrust_spear()
	# Issue #65: a shot ends the move — hand the turn over.
	TurnController.notify_shot()


## Issue #66: NPC entry point — the enemy AI fires through the same weapon
## (same cooldown, same projectiles, same shooter pass-through).
func npc_fire() -> void:
	if _cooldown_left > 0.0:
		return
	_fire()


func _spawn_projectile(type: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float = 0.0) -> Area2D:
	var projectile := Area2D.new()
	projectile.set_script(ProjectileScript)
	projectile.setup(type, velocity, damage, lifetime, size, color, blast_radius)
	# Issue #57: remember the wielder so shots pass through them.
	projectile.shooter = get_parent()
	projectile.global_position = global_position + _aim() * 36.0
	get_parent().get_parent().add_child(projectile)
	return projectile


func _fire_shotgun() -> void:
	var aim := _aim()
	for i in 5:
		var spread := deg_to_rad(-8.0 + 4.0 * i)
		var velocity := aim.rotated(spread) * PELLET_SPEED
		_spawn_projectile(Projectile.Type.PELLET, velocity, PELLET_DAMAGE,
			PELLET_LIFETIME, Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))


func _fire_rocket() -> void:
	_spawn_projectile(Projectile.Type.ROCKET,
		_aim() * ROCKET_SPEED, ROCKET_DAMAGE, ROCKET_LIFETIME,
		Vector2(22, 8), Color(0.9, 0.35, 0.15, 1), ROCKET_BLAST)


func _fire_grenade() -> void:
	# Issue #99: NPC grenades are aimed ballistically at the target so the
	# arc lands ON the target instead of falling back onto the shooter's
	# own team (blast damage is friendly fire since issue #57).
	if npc_target != null and is_instance_valid(npc_target):
		var to := npc_target.global_position - global_position
		var t := clampf(to.length() / GRENADE_SPEED, 0.5, 1.5)
		var velocity := to / t
		velocity.y -= 0.5 * 1200.0 * t
		_spawn_projectile(Projectile.Type.GRENADE, velocity, GRENADE_DAMAGE,
			GRENADE_FUSE, Vector2(14, 14), Color(0.3, 0.7, 0.3, 1), GRENADE_BLAST)
		npc_target = null
		return
	var aim := _aim()
	var velocity := (Vector2(GRENADE_SPEED, -320.0) * Vector2(_facing, 1.0)).rotated(aim.angle())
	_spawn_projectile(Projectile.Type.GRENADE, velocity, GRENADE_DAMAGE,
		GRENADE_FUSE, Vector2(14, 14), Color(0.3, 0.7, 0.3, 1), GRENADE_BLAST)


func _thrust_spear() -> void:
	# Instant melee hit: damage the closest target in front within range.
	var parent := get_parent() as Node2D
	var targets: Array = []
	# Issue #57: friendly fire — a spear thrust can also hit teammates.
	targets.append_array(get_tree().get_nodes_in_group("player_team"))
	targets.append_array(get_tree().get_nodes_in_group("enemy_team"))
	var best: Node2D = null
	var best_distance := SPEAR_RANGE
	for node in targets:
		var body := node as Node2D
		if body == null or body == parent or not body.has_method("take_damage"):
			continue
		var offset := body.global_position - global_position
		var distance := offset.length()
		if distance <= best_distance and offset.normalized().dot(_aim()) > 0.5:
			best = body
			best_distance = distance
	if best:
		best.take_damage(SPEAR_DAMAGE)
	# Visual thrust: a short-lived rectangle in front of the wielder.
	_spawn_projectile(Projectile.Type.PELLET,
		_aim() * (SPEAR_RANGE / 0.1), 0, 0.1,
		Vector2(SPEAR_RANGE, 6), Color(0.8, 0.8, 0.9, 0.8))
