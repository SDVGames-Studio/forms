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
var _cooldown_left := 0.0

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
	if parent and parent.velocity.x != 0.0:
		new_facing = signf(parent.velocity.x)

	# Issue #33: only the controlled team member fires on input.
	if parent != null and parent.get("controlled") == true:
		selected_weapon = WeaponInventory.selected_weapon
		if Input.is_action_just_pressed("shoot") and _cooldown_left == 0.0:
			_fire()

	# Issue #68: keep the held weapon in sync with selection and facing.
	if new_facing != _facing or selected_weapon != _held_style:
		_facing = new_facing
		_update_held()


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


func _spawn_projectile(type: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float = 0.0) -> Area2D:
	var projectile := Area2D.new()
	projectile.set_script(ProjectileScript)
	projectile.setup(type, velocity, damage, lifetime, size, color, blast_radius)
	# Issue #57: remember the wielder so shots pass through them.
	projectile.shooter = get_parent()
	projectile.global_position = global_position + Vector2(_facing * 36.0, 0.0)
	get_parent().get_parent().add_child(projectile)
	return projectile


func _fire_shotgun() -> void:
	for i in 5:
		var spread := deg_to_rad(-8.0 + 4.0 * i)
		var velocity := Vector2(PELLET_SPEED * _facing, 0.0).rotated(spread)
		_spawn_projectile(Projectile.Type.PELLET, velocity, PELLET_DAMAGE,
			PELLET_LIFETIME, Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))


func _fire_rocket() -> void:
	_spawn_projectile(Projectile.Type.ROCKET,
		Vector2(ROCKET_SPEED * _facing, 0.0), ROCKET_DAMAGE, ROCKET_LIFETIME,
		Vector2(22, 8), Color(0.9, 0.35, 0.15, 1), ROCKET_BLAST)


func _fire_grenade() -> void:
	var velocity := Vector2(GRENADE_SPEED * _facing, -320.0)
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
		if distance <= best_distance and signf(offset.x) == _facing:
			best = body
			best_distance = distance
	if best:
		best.take_damage(SPEAR_DAMAGE)
	# Visual thrust: a short-lived rectangle in front of the wielder.
	_spawn_projectile(Projectile.Type.PELLET,
		Vector2(SPEAR_RANGE / 0.1 * _facing, 0.0), 0, 0.1,
		Vector2(SPEAR_RANGE, 6), Color(0.8, 0.8, 0.9, 0.8))
