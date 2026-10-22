extends CharacterBody2D
## First NPC (issue #5).
##
## An enemy figure that holds a weapon and tries to hit the player:
## it walks toward the player, keeps a preferred distance, and fires
## projectiles at them when in range (line of sight is not checked in this
## first slice). Reuses Bullet.gd so no new assets are needed.

const BulletScript := preload("res://Bullet.gd")

const SPEED := 160.0
const GRAVITY := 1200.0
const ATTACK_RANGE := 500.0
const COOLDOWN := 1.2
const BULLET_SPEED := 500.0
const KEEP_DISTANCE := 140.0

var _cooldown_left := 0.0
var _player: Node2D


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 32.0
	shape.shape = circle
	add_child(shape)

	var visual := ColorRect.new()
	visual.offset_left = -32.0
	visual.offset_top = -32.0
	visual.offset_right = 32.0
	visual.offset_bottom = 32.0
	visual.color = Color(0.75, 0.2, 0.45, 1)
	add_child(visual)


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * delta)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	var distance := to_player.length()

	# Walk toward the player, stopping at KEEP_DISTANCE.
	if distance > KEEP_DISTANCE:
		velocity.x = signf(to_player.x) * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * delta)

	# Take a shot when in range and cooled down.
	if distance <= ATTACK_RANGE and _cooldown_left == 0.0:
		_shoot(to_player.normalized())

	move_and_slide()


func _shoot(direction: Vector2) -> void:
	_cooldown_left = COOLDOWN
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.velocity = direction * BULLET_SPEED
	bullet.global_position = global_position + direction * 40.0
	get_parent().add_child(bullet)
