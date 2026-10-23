extends CharacterBody2D
## Teammate figure for the player's team (issue #7).
##
## Follows the player character at a loose offset, with gravity and simple
## jump assistance. Movement is code-driven AI; the follow target is found
## via the "player" group, same as the NPC uses.
##
## Issue #14: teammates now join the fight — they fire at the nearest NPC
## within range using Bullet.gd. Their bullets only collide with the NPC
## layer (mask 2), so they never friendly-fire the player or each other.

const FOLLOW_DISTANCE := 90.0
const SPEED := 300.0
const JUMP_VELOCITY := -560.0
const GRAVITY := 1200.0

const BODY_WIDTH := 56.0
const BODY_HEIGHT := 56.0

const ATTACK_RANGE := 480.0
const COOLDOWN := 0.9
const BULLET_SPEED := 600.0

var _target: Node2D
var _body: ColorRect
var _cooldown_left := 0.0


func _ready() -> void:
	_build_visual()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_target = players[0]


func _build_visual() -> void:
	_body = ColorRect.new()
	_body.offset_left = -BODY_WIDTH / 2.0
	_body.offset_top = -BODY_HEIGHT / 2.0
	_body.offset_right = BODY_WIDTH / 2.0
	_body.offset_bottom = BODY_HEIGHT / 2.0
	add_child(_body)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Combat: shoot at the nearest enemy (NPC) in range.
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _cooldown_left == 0.0:
		var enemy := _nearest_enemy()
		if enemy != null:
			_shoot_at(enemy)
	var to_target := Vector2.ZERO
	if _target != null:
		# Follow the player but keep a small gap; alternate sides so
		# multiple teammates naturally spread out.
		var side := 1.0 if int(get_instance_id()) % 2 == 0 else -1.0
		to_target = _target.global_position + Vector2(FOLLOW_DISTANCE * side, 0.0) - global_position

	var direction := 0.0
	if absf(to_target.x) > 16.0:
		direction = signf(to_target.x)
	velocity.x = direction * SPEED

	# Jump when the player is clearly above us or we are blocked by a wall.
	if is_on_floor() and (to_target.y < -80.0 or is_on_wall()):
		velocity.y = JUMP_VELOCITY

	move_and_slide()


func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance := ATTACK_RANGE
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node2D
		if enemy == null:
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _shoot_at(enemy: Node2D) -> void:
	_cooldown_left = COOLDOWN
	var direction := (enemy.global_position - global_position).normalized()
	var bullet := Area2D.new()
	bullet.set_script(preload("res://Bullet.gd"))
	bullet.collision_mask = 2  # Only hit the NPC layer — no friendly fire.
	bullet.velocity = direction * BULLET_SPEED
	bullet.global_position = global_position + direction * 36.0
	get_parent().add_child(bullet)
