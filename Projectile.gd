class_name Projectile
extends Area2D
## Projectile for the standard weapons (issue #49).
##
## One script covers all ranged weapon types; physics differ per type:
## pellets fly straight and short, the rocket flies fast and explodes on
## impact, the grenade flies in a gravity arc and explodes on a fuse or on
## impact. Visuals are plain rectangles built in code — no assets.

enum Type { PELLET, ROCKET, GRENADE }

var type: int = Type.PELLET
var velocity := Vector2.ZERO
var damage := 10
var blast_radius := 0.0
var lifetime := 2.0
var _size := Vector2(12, 6)
var _color := Color.WHITE


func setup(p_type: int, p_velocity: Vector2, p_damage: int, p_lifetime: float, p_size: Vector2, p_color: Color, p_blast_radius: float = 0.0) -> void:
	type = p_type
	velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	_size = p_size
	_color = p_color
	blast_radius = p_blast_radius


func _ready() -> void:
	collision_mask = 3
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size
	shape.shape = rect
	add_child(shape)

	body_entered.connect(_on_body_entered)

	var visual := ColorRect.new()
	visual.offset_left = -_size.x / 2.0
	visual.offset_top = -_size.y / 2.0
	visual.offset_right = _size.x / 2.0
	visual.offset_bottom = _size.y / 2.0
	visual.color = _color
	add_child(visual)

	get_tree().create_timer(lifetime).timeout.connect(_on_expire)


func _physics_process(delta: float) -> void:
	if type == Type.GRENADE:
		velocity.y += 1200.0 * delta
	global_position += velocity * delta
	if not get_viewport_rect().has_point(global_position):
		queue_free()


func _on_expire() -> void:
	if type == Type.GRENADE:
		_explode()
	else:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if blast_radius > 0.0:
		_explode()
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _explode() -> void:
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
