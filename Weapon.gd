extends Node2D
## Simple weapon for the player (issue #3).
##
## Pressing the "shoot" action (F) fires a small projectile in the direction
## the player last faced. Bullets are simple Area2D bodies built in code —
## no extra assets. A short cooldown prevents spam.

const BulletScript := preload("res://Bullet.gd")

const COOLDOWN := 0.3
const BULLET_SPEED := 900.0

var _facing := 1.0
var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var parent := get_parent() as CharacterBody2D
	if parent and parent.velocity.x != 0.0:
		_facing = signf(parent.velocity.x)

	if Input.is_action_just_pressed("shoot") and _cooldown_left == 0.0:
		_shoot()


func _shoot() -> void:
	_cooldown_left = COOLDOWN
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.velocity = Vector2(BULLET_SPEED * _facing, 0.0)
	bullet.global_position = global_position + Vector2(_facing * 36.0, 0.0)
	get_parent().get_parent().add_child(bullet)
