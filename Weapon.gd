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
## Issue #114: rockets and grenades spawn as real rigid bodies.
const ProjectileBodyScript := preload("res://ProjectileBody.gd")

const COOLDOWN := 0.3

## Issue #101: shots each weapon allows during ONE turn (index = weapon:
## shotgun 2, rocket 1, grenade 1, spear 2) and the 3-second delay after
## every shot during which the character cannot shoot again.
const SHOTS_PER_TURN: Array = [2, 1, 1, 2]
const SHOT_DELAY := 3.0

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
## Issue #114: charged shots. Holding F charges a rocket/grenade launch —
## the longer the hold, the faster it flies (from MIN_SHOT_POWER up to the
## full base speed after MAX_CHARGE_TIME seconds).
const MIN_SHOT_POWER := 0.4
const MAX_CHARGE_TIME := 1.5
const ROCKET_MASS := 1.0
const GRENADE_MASS := 0.6

var _facing := 1.0
var _gravity_dir := 1.0
var _cooldown_left := 0.0
## Issue #101: shots already made this turn by this member.
var _shots_used := 0
## Issue #101: seconds left before the character may shoot again.
var _shot_delay_left := 0.0
## Issue #114: charge state for the rocket/grenade charged launch.
var _charging := false
var _charge_time := 0.0
var _charge_bar: ColorRect

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
	# Issue #114: charge meter shown above the wielder while holding F.
	_charge_bar = ColorRect.new()
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_bar.visible = false
	_charge_bar.color = Color(1.0, 0.6, 0.1, 0.9)
	_charge_bar.offset_top = -56.0
	_charge_bar.offset_bottom = -52.0
	add_child(_charge_bar)
	_update_held()


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	# Issue #101: tick the between-shots delay.
	_shot_delay_left = maxf(0.0, _shot_delay_left - delta)

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
	var controlled: bool = parent != null and parent.get("controlled") == true \
			and TurnController.active_team == TurnController.TEAM_PLAYER
	if controlled:
		selected_weapon = WeaponInventory.selected_weapon
	# Issue #101 bugfix: ONLY the controlled member may fire on input —
	# every character has a Weapon node, so an unguarded Input check made
	# all characters holding the same weapon fire together.
	var can_shoot := _shots_used < _shot_limit() \
			and _shot_delay_left == 0.0 and _cooldown_left == 0.0
	# Issue #114: rocket (1) and grenade (2) are CHARGED — pressing F starts
	# the charge, releasing F fires with power scaled by the hold time.
	# Shotgun and spear keep their instant press-fire behavior.
	var charged := selected_weapon == 1 or selected_weapon == 2
	if controlled and can_shoot and not _charging \
			and Input.is_action_just_pressed("shoot"):
		if charged:
			_charging = true
			_charge_time = 0.0
		else:
			_fire()
	if controlled and _charging:
		if Input.is_action_just_released("shoot") or not can_shoot:
			_charging = false
			_fire(clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0))
		else:
			_charge_time = minf(_charge_time + delta, MAX_CHARGE_TIME)
			_charge_bar.visible = true
			var charge_width := 40.0 + 30.0 * (_charge_time / MAX_CHARGE_TIME)
			_charge_bar.offset_left = -charge_width / 2.0
			_charge_bar.offset_right = charge_width / 2.0
	if not _charging and _charge_bar.visible:
		_charge_bar.visible = false

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


func _shot_limit() -> int:
	return SHOTS_PER_TURN[clampi(selected_weapon, 0, SHOTS_PER_TURN.size() - 1)]


## Issue #101: called by TurnController at the start of every turn —
## restores the full shot quota for this character.
func reset_shots() -> void:
	_shots_used = 0
	_shot_delay_left = 0.0


func _fire(power := 1.0) -> void:
	_cooldown_left = COOLDOWN
	_shots_used += 1
	# Issue #101: 3-second pause before the next shot of the same turn.
	_shot_delay_left = SHOT_DELAY
	match selected_weapon:
		0: _fire_shotgun()
		1: _fire_rocket(power)
		2: _fire_grenade(power)
		3: _thrust_spear()
	# Issue #101+#65: only the LAST shot of the turn hands the turn over;
	# with quota remaining the character keeps acting after the pause.
	if _shots_used >= _shot_limit():
		TurnController.notify_shot()


## Issue #66: NPC entry point — the enemy AI fires through the same weapon
## (same cooldown, same projectiles, same shooter pass-through).
func npc_fire() -> void:
	if _cooldown_left > 0.0 or _shot_delay_left > 0.0 \
			or _shots_used >= _shot_limit():
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


func _fire_rocket(power := 1.0) -> void:
	# Issue #114: the rocket is a rigid body — its speed scales with the
	# shot power (how long F was held).
	var speed := ROCKET_SPEED * lerpf(MIN_SHOT_POWER, 1.0, power)
	_spawn_body(ProjectileBody.Kind.ROCKET,
		_aim() * speed, ROCKET_DAMAGE, ROCKET_LIFETIME,
		Vector2(22, 8), Color(0.9, 0.35, 0.15, 1), ROCKET_BLAST, ROCKET_MASS)


func _fire_grenade(power := 1.0) -> void:
	# Issue #99: NPC grenades are aimed ballistically at the target so the
	# arc lands ON the target instead of falling back onto the shooter's
	# own team (blast damage is friendly fire since issue #57).
	if npc_target != null and is_instance_valid(npc_target):
		var to := npc_target.global_position - global_position
		var t := clampf(to.length() / GRENADE_SPEED, 0.5, 1.5)
		var velocity := to / t
		velocity.y -= 0.5 * 1200.0 * t
		_spawn_body(ProjectileBody.Kind.GRENADE, velocity, GRENADE_DAMAGE,
			GRENADE_FUSE, Vector2(14, 14), Color(0.3, 0.7, 0.3, 1),
			GRENADE_BLAST, GRENADE_MASS)
		npc_target = null
		return
	# Issue #114: player grenades are charged too — power scales the launch
	# speed, the grenade itself is a bouncing rigid body under gravity.
	var speed := GRENADE_SPEED * lerpf(MIN_SHOT_POWER, 1.0, power)
	var aim := _aim()
	var velocity := (Vector2(speed, -320.0 * lerpf(MIN_SHOT_POWER, 1.0, power)) \
			* Vector2(_facing, 1.0)).rotated(aim.angle())
	_spawn_body(ProjectileBody.Kind.GRENADE, velocity, GRENADE_DAMAGE,
		GRENADE_FUSE, Vector2(14, 14), Color(0.3, 0.7, 0.3, 1),
		GRENADE_BLAST, GRENADE_MASS)


## Issue #114: spawn a physics-driven explosive projectile (rigid body).
func _spawn_body(kind: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float, mass: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(ProjectileBodyScript)
	body.setup(kind, velocity, damage, lifetime, size, color, blast_radius, mass)
	# Issue #57: remember the wielder so shots pass through them.
	body.shooter = get_parent()
	body.global_position = global_position + _aim() * 36.0
	get_parent().get_parent().add_child(body)
	return body


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
