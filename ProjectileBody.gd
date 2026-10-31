class_name ProjectileBody
extends RigidBody2D
## Physics-driven explosive projectile (issue #114).
##
## Rockets and grenades are now REAL physical objects — rigid bodies with
## their own mass, inertia, gravity and (for the grenade) bounciness —
## instead of kinematically moved areas. The shotgun keeps its old logic
## (Projectile.gd, issue #49): its rework comes later.
##  ROCKET  — mass 1.0, no gravity, explodes on any contact
##  GRENADE — mass 0.6, LEVEL gravity (issue #216: terrain sources or the
##             center-line rule, exactly like the figures), bounces off
##             surfaces, explodes on fuse
## Visuals are plain rectangles built in code — no assets.

enum Kind { ROCKET, GRENADE }

const BOUNCE := {Kind.ROCKET: 0.0, Kind.GRENADE: 0.45}
## Issue #216: grenade acceleration matches the figures (Stats.GRAVITY).
const Stats := preload("res://scripts/CharacterStats.gd")
const GRAVITY := Stats.GRAVITY
## Issue #216: gravity context captured from the wielder — the center line
## height and the static gravity direction of levels without terrain sources.
var _center_line_y := 0.0
var _shoot_gravity_dir := 1.0

var kind: int = Kind.ROCKET
## Launch velocity applied once the body enters the tree.
var launch_velocity := Vector2.ZERO
var damage := 30
var blast_radius := 0.0
var lifetime := 3.0
## Issue #57: the character that fired us — we pass through it.
var shooter: Node2D = null
var _size := Vector2(16, 8)
var _color := Color.WHITE
var _mass := 1.0
var _exploded := false


func setup(p_kind: int, p_velocity: Vector2, p_damage: int, p_lifetime: float,
		p_size: Vector2, p_color: Color, p_blast_radius: float = 0.0,
		p_mass: float = 1.0) -> void:
	kind = p_kind
	launch_velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	_size = p_size
	_color = p_color
	blast_radius = p_blast_radius
	_mass = p_mass


func _ready() -> void:
	# Issue #119: register with TurnController so the turn handover waits
	# until every projectile has exploded/been freed.
	add_to_group("projectiles")
	# Layer 4 = projectiles; hit the world, both teams, and walls.
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	mass = _mass
	# Issue #216: engine gravity is always OFF for projectiles — the grenade
	# gets the LEVEL's gravity in _integrate_forces instead (the rocket stays
	# gravity-free and flies straight).
	gravity_scale = 0.0
	if shooter != null:
		_center_line_y = float(shooter.get("center_line_y") or 0.0)
		_shoot_gravity_dir = float(shooter.get("gravity_dir") or 1.0)
	var mat := PhysicsMaterial.new()
	mat.bounce = BOUNCE[kind]
	physics_material_override = mat
	linear_velocity = launch_velocity
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size
	shape.shape = rect
	add_child(shape)

	var visual := ColorRect.new()
	visual.offset_left = -_size.x / 2.0
	visual.offset_top = -_size.y / 2.0
	visual.offset_right = _size.x / 2.0
	visual.offset_bottom = _size.y / 2.0
	visual.color = _color
	add_child(visual)

	get_tree().create_timer(lifetime).timeout.connect(_on_fuse)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Issue #216: the grenade obeys the level's gravity — terrain sources
	# first, then the center-line rule, then the static direction — the same
	# ladder the figures use (Player.gd / Npc.gd).
	if kind == Kind.GRENADE:
		state.linear_velocity += _level_gravity() * GRAVITY * state.step


## Unit gravity direction at the grenade's position (issue #216).
func _level_gravity() -> Vector2:
	if LevelTerrain.has_sources(self):
		return LevelTerrain.gravity_vector(self)
	if _center_line_y > 0.0:
		return Vector2.DOWN if global_position.y < _center_line_y else Vector2.UP
	return Vector2.UP if _shoot_gravity_dir < 0.0 else Vector2.DOWN


func _on_body_entered(body: Node2D) -> void:
	# Issue #57: never interact with the character that fired us.
	if body == shooter:
		return
	if kind == Kind.ROCKET:
		_explode()


func _on_fuse() -> void:
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	# Area damage to everything with health inside the blast radius.
	var targets: Array = []
	targets.append_array(get_tree().get_nodes_in_group("player_team"))
	targets.append_array(get_tree().get_nodes_in_group("enemy_team"))
	for node in targets:
		var body := node as Node2D
		if body and body.has_method("take_damage") \
				and body.global_position.distance_to(global_position) <= blast_radius:
			body.take_damage(damage)
	_spawn_blast_visual()
	queue_free()


## Issue #150: brief expanding ring showing the blast radius at the
## moment of explosion. Drawn in code — no assets.
func _spawn_blast_visual() -> void:
	if blast_radius <= 0.0:
		return
	var ring := BlastRing.new()
	ring.radius = blast_radius
	ring.position = global_position
	ring.z_index = 50
	get_parent().add_child(ring)


class BlastRing:
	extends Node2D

	const LIFETIME := 0.4

	var radius := 100.0
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := _age / LIFETIME
		var alpha := 1.0 - t
		var r := radius * (0.6 + 0.4 * t)
		# Filled flash fading out fast.
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.6, 0.2, 0.35 * alpha))
		# Bright expanding outline.
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48,
				Color(1.0, 0.8, 0.3, alpha), 3.0, true)
