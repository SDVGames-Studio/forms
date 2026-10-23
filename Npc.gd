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

## Issue #14: NPCs are now fightable — they have health, a health bar and
## die when it runs out. Layer 1|2 so player bullets (mask 1) and teammate
## bullets (mask 2) both hit them, while teammates (layer 4) never do.
const MAX_HEALTH := 60
const BAR_WIDTH := 56.0
const BAR_HEIGHT := 7.0

var health: int = MAX_HEALTH
var _bar_fill: ColorRect
var _visual: ColorRect
var _dead := false


func _ready() -> void:
	collision_layer = 3
	add_to_group("enemy")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 32.0
	shape.shape = circle
	add_child(shape)

	_visual = ColorRect.new()
	_visual.offset_left = -32.0
	_visual.offset_top = -32.0
	_visual.offset_right = 32.0
	_visual.offset_bottom = 32.0
	_visual.color = Color(0.75, 0.2, 0.45, 1)
	add_child(_visual)

	_build_health_bar()


func _build_health_bar() -> void:
	var background := ColorRect.new()
	background.offset_left = -BAR_WIDTH / 2.0
	background.offset_top = -44.0
	background.offset_right = BAR_WIDTH / 2.0
	background.offset_bottom = -44.0 + BAR_HEIGHT
	background.color = Color(0.1, 0.1, 0.12, 0.85)
	add_child(background)

	_bar_fill = ColorRect.new()
	_bar_fill.offset_left = 1.0
	_bar_fill.offset_top = 1.0
	_bar_fill.offset_bottom = -1.0
	_bar_fill.color = Color(0.75, 0.2, 0.45, 1)
	background.add_child(_bar_fill)
	_update_bar()


func _update_bar() -> void:
	if _bar_fill == null:
		return
	var inner_width := BAR_WIDTH - 2.0
	var ratio := float(health) / float(MAX_HEALTH)
	_bar_fill.offset_right = 1.0 + inner_width * ratio


func take_damage(amount: int) -> void:
	if _dead:
		return
	health = clampi(health - amount, 0, MAX_HEALTH)
	_update_bar()
	# Hit flash.
	_visual.color = Color(1.0, 0.6, 0.7, 1)
	get_tree().create_timer(0.1).timeout.connect(
		func() -> void: _visual.color = Color(0.75, 0.2, 0.45, 1))
	if health == 0:
		_die()


func _die() -> void:
	_dead = true
	# Tiny death puff: shrink out, then free.
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.25)
	tween.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if _dead:
		return
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
