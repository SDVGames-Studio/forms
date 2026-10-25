extends CharacterBody2D
## First NPC (issue #5).
##
## An enemy figure that holds a weapon and tries to hit the player:
## Issue #35: NPCs now fight as a computer-controlled TEAM — each NPC
## targets the nearest opposing figure (player or teammate), keeps its
## own flank slot so team members spread out instead of stacking, and
## jumps when blocked or when its target is above it.

const BulletScript := preload("res://Bullet.gd")

const SPEED := 160.0
const GRAVITY := 1200.0
const ATTACK_RANGE := 500.0
const COOLDOWN := 1.2
const BULLET_SPEED := 500.0
const KEEP_DISTANCE := 140.0

## Issue #35: team coordination constants.
const FLANK_SPACING := 110.0
const SEPARATION := 90.0
const JUMP_VELOCITY := -560.0

## Issue #14: NPCs are now fightable — they have health, a health bar and
## die when it runs out. Layer 1|2 so player bullets (mask 1) and teammate
## bullets (mask 2) both hit them, while teammates (layer 4) never do.
const MAX_HEALTH := 60
const BAR_WIDTH := 56.0
const BAR_HEIGHT := 7.0

## Issue #33: name shown above the health bar.
@export var display_name := "Enemy"

## Issue #60: every member of a team wears the same team color — body,
## health bar fill and hit flash all derive from it.
@export var team_color := Color(0.75, 0.2, 0.45, 1)

## Issue #48: 1.0 = normal downward gravity, -1.0 = reversed (the figure
## stands upside-down on the underside of a ceiling/line).
@export var gravity_dir := 1.0

## Issue #48 rework: y of the level's central line. When > 0, gravity side is
## chosen every frame from the position relative to the line (normal above,
## reversed below) instead of the static gravity_dir.
@export var center_line_y := 0.0

var health: int = MAX_HEALTH
var _bar_fill: ColorRect
var _visual: ColorRect
var _dead := false
var _target: Node2D
var _flank_slot := 0.0  # Per-instance offset so team members spread out.


## Issue #60: tint every ColorRect visual authored in the scene (captured
## before the health bar adds its own ColorRects) with the team color.
func _apply_team_color() -> void:
	for child in get_children():
		var rect := child as ColorRect
		if rect != null:
			rect.color = team_color


func _ready() -> void:
	# Issue #39 rework: characters collide with each other (world + both
	# character layers) but never push — walking into another figure steps
	# up ON TOP of it instead (see _climb_on_characters).
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	if gravity_dir < 0.0:
		up_direction = Vector2.DOWN
	add_to_group("enemy")
	add_to_group("enemy_team")
	_apply_team_color()
	# Stable per-instance flank slot (index within the enemy team).
	var members := get_tree().get_nodes_in_group("enemy_team")
	_flank_slot = float(members.find(self)) - (float(members.size() - 1) / 2.0)
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
	_visual.color = team_color
	add_child(_visual)

	_build_health_bar()


func _build_health_bar() -> void:
	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.offset_left = -70.0
	name_label.offset_top = -62.0
	name_label.offset_right = 70.0
	name_label.offset_bottom = -46.0
	add_child(name_label)

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
	_bar_fill.color = team_color
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
		func() -> void: _visual.color = team_color)
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
	var dir := 1.0
	if center_line_y > 0.0:
		dir = 1.0 if global_position.y < center_line_y else -1.0
		up_direction = Vector2.UP if dir > 0.0 else Vector2.DOWN
	elif gravity_dir < 0.0:
		dir = -1.0
	if not is_on_floor():
		velocity.y += GRAVITY * dir * delta

	_target = _nearest_opponent()
	if _target == null:
		# Issue #58: stop instantly instead of gliding to a halt.
		velocity.x = 0.0
		move_and_slide()
		return

	# Aim at the chosen target, offset by this NPC's flank slot so the
	# team surrounds the opponents instead of forming a single column.
	var goal := _target.global_position \
		+ Vector2(KEEP_DISTANCE + absf(_flank_slot) * FLANK_SPACING, 0.0) \
			* (1.0 if _flank_slot >= 0.0 else -1.0)
	var to_target := goal - global_position
	var distance := _target.global_position.distance_to(global_position)

	var direction := 0.0
	if absf(to_target.x) > 16.0:
		direction = signf(to_target.x)
	# Separation: back off from other enemies we are stacking on.
	for other in get_tree().get_nodes_in_group("enemy_team"):
		if other == self:
			continue
		var away := global_position.x - other.global_position.x
		if absf(away) < SEPARATION and absf(global_position.y - other.global_position.y) < 40.0:
			direction += signf(away) * 0.5
	velocity.x = clampf(direction, -1.0, 1.0) * SPEED

	# Jump when blocked or when the target is clearly above us.
	if is_on_floor() and (is_on_wall() or (_target.global_position.y - global_position.y) * gravity_dir < -80.0):
		velocity.y = JUMP_VELOCITY * dir

	# Take a shot when in range and cooled down.
	if distance <= ATTACK_RANGE and _cooldown_left == 0.0:
		_shoot((_target.global_position - global_position).normalized())

	move_and_slide()
	_climb_on_characters(dir)


## Issue #39 rework: when moving into another character, climb on top of it
## instead of being blocked — figures can walk over each other's heads.
func _climb_on_characters(dir: float) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider() as CharacterBody2D
		if other == null or other == self:
			continue
		if not (other.is_in_group("player_team") or other.is_in_group("enemy_team")):
			continue
		# Only a frontal hit (normal pointing back at us) while grounded.
		if absf(col.get_normal().x) < 0.7 or not is_on_floor():
			continue
		if absf(velocity.x) > 1.0 and signf(col.get_normal().x) != -signf(velocity.x):
			continue
		# Both figures are 64 px circles — stack the centers 64 px apart,
		# offset along the current gravity direction.
		global_position = other.global_position - Vector2(0.0, 64.0) * dir
		velocity.y = 0.0
		return


## Issue #35: nearest opposing figure — the player or any teammate.
func _nearest_opponent() -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for group in ["player", "team"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node2D
			if candidate == null:
				continue
			var d := global_position.distance_to(candidate.global_position)
			if d < best_distance:
				best_distance = d
				best = candidate
	return best


func _shoot(direction: Vector2) -> void:
	_cooldown_left = COOLDOWN
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	# Issue #39: enemies are on layer 2, world is layer 1 — hit both.
	bullet.collision_mask = 3
	bullet.velocity = direction * BULLET_SPEED
	# Issue #57: never hit the shooter itself.
	bullet.shooter = self
	bullet.global_position = global_position + direction * 40.0
	get_parent().add_child(bullet)
