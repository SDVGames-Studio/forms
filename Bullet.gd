extends Area2D
## Projectile fired by Weapon.gd (issue #3).
##
## Flies in a straight line, frees itself after LIFETIME seconds or when it
## leaves the viewport. Built entirely in code by Weapon.gd.

const LIFETIME := 2.0
const SPEED := 900.0

var velocity := Vector2.ZERO


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)

	var visual := ColorRect.new()
	visual.offset_left = -8.0
	visual.offset_top = -8.0
	visual.offset_right = 8.0
	visual.offset_bottom = 8.0
	visual.color = Color(0.95, 0.3, 0.2, 1)
	add_child(visual)

	# Expire after a while so bullets never accumulate.
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	if not get_viewport_rect().has_point(global_position):
		queue_free()
