class_name ProjectileBody
extends RigidBody2D
## Physics-driven explosive projectile (issue #114).
##
## Rockets and grenades are now REAL physical objects — rigid bodies with
## their own mass, inertia, gravity and (for the grenade) bounciness —
## instead of kinematically moved areas. The shotgun keeps its old logic
## (Projectile.gd, issue #49): its rework comes later.
##  ROCKET  — mass 1.0, no gravity, explodes on any contact
##  GRENADE — mass 0.6, full gravity, bounces off surfaces, explodes on fuse
## Visuals are plain rectangles built in code — no assets.

enum Kind { ROCKET, GRENADE }

const GRAVITY_SCALE := {Kind.ROCKET: 0.0, Kind.GRENADE: 1.0}
const BOUNCE := {Kind.ROCKET: 0.0, Kind.GRENADE: 0.45}

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
	# Layer 4 = projectiles; hit the world, both teams, and walls.
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	mass = _mass
	gravity_scale = GRAVITY_SCALE[kind]
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
	queue_free()
