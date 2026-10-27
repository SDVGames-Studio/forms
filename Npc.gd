extends CharacterBody2D
## First NPC (issue #5).
##
## An enemy figure that holds a weapon and tries to hit the player:
## Issue #66: smarter enemy AI — each NPC carries a real Weapon (the same
## arsenal the player team uses) and plays by the rules:
##  - TARGET: the lowest-health opposing figure in attack range (focus
##    fire), otherwise the nearest one, re-evaluated every frame;
##  - AIM: a view angle like the player (aim_dir) instead of flat shots;
##  - WEAPONS: switched by distance — spear up close, shotgun at medium
##    range, rocket farther, grenade lobbed at the farthest targets.
## The main goal stays: eliminate all other teams.

const WeaponScript := preload("res://Weapon.gd")

## Issue #108: all characteristics come from the shared CharacterStats —
## enemy figures are the SAME class of character as player figures
## (same health, speed, jump, gravity, aim and health bar).
const Stats := preload("res://scripts/CharacterStats.gd")

const SPEED := Stats.SPEED
const GRAVITY := Stats.GRAVITY
const ATTACK_RANGE := 500.0
const KEEP_DISTANCE := 140.0
## Issue #66: aim slew speed (rad/s) and per-weapon range bands.
const SPEAR_RANGE_NPC := 90.0
const SHOTGUN_RANGE_NPC := 360.0
const ROCKET_RANGE_NPC := 620.0

## Issue #35: team coordination constants.
const FLANK_SPACING := 110.0
const SEPARATION := 90.0
const JUMP_VELOCITY := Stats.JUMP_VELOCITY

## Issue #14: NPCs are now fightable — they have health, a health bar and
## die when it runs out. Layer 1|2 so player bullets (mask 1) and teammate
## bullets (mask 2) both hit them, while teammates (layer 4) never do.
const MAX_HEALTH := Stats.MAX_HEALTH
const BAR_WIDTH := Stats.BAR_WIDTH
const BAR_HEIGHT := Stats.BAR_HEIGHT

## Issue #33: name shown above the health bar.
@export var display_name := "Enemy"

## Issue #60: every member of a team wears the same team color — body,
## health bar fill and hit flash all derive from it.
@export var team_color := Color(0.75, 0.2, 0.45, 1)

## Issue #121: which side this AI fights for. "enemy" (default) behaves
## exactly as before; "player" places the figure in the player team, so a
## level can stage a computer-vs-computer duel the user only spectates.
@export var team: String = "enemy"

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
var _cooldown_left := 0.0
## Issue #137: AI difficulty — 0 = easy, 1 = normal, 2 = hard. Scales
## aim slew speed and the pause between shots (set by the level
## configuration menu via GameConfig).
@export_range(0, 2) var difficulty := 1
var _flank_slot := 0.0  # Per-instance offset so team members spread out.
## Issue #66: current aim (view) angle in radians, like Player.gd.
var view_angle := 0.0
const AIM_SPEED := Stats.VIEW_SPEED
## Issue #137: per-difficulty aim slew and between-shot pause.
const AIM_SPEED_MULT := [0.5, 1.0, 1.5]
const FIRE_PAUSE := [2.0, 0.9, 0.0]
const VIEW_MAX := Stats.VIEW_MAX
## Issue #66: the weapon carried by this NPC (created in _ready).
var _weapon: Node2D


## Issue #66: aim direction — facing raised/lowered by view_angle and
## oriented against the current gravity side (mirrors Player.aim_dir).
func aim_dir(facing: float, dir: float) -> Vector2:
	return Vector2(cos(view_angle) * facing, -sin(view_angle) * dir)


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
	if team == "enemy":
		add_to_group("enemy")
	add_to_group("enemy_team" if team == "enemy" else "player_team")
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
	# Issue #66: give this NPC the standard weapon so it can use the full
	# arsenal (shotgun / rocket / grenade / spear), not just plain bullets.
	if get_node_or_null("Weapon") == null:
		_weapon = WeaponScript.new()
		_weapon.name = "Weapon"
		add_child(_weapon)
	else:
		_weapon = get_node("Weapon")


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


var _climb_tween: Tween


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	# Issue #39 rework: while a climb animation plays, hold position.
	if _climb_tween != null and _climb_tween.is_valid():
		velocity = Vector2.ZERO
		return
	var dir := 1.0
	if center_line_y > 0.0:
		dir = 1.0 if global_position.y < center_line_y else -1.0
		up_direction = Vector2.UP if dir > 0.0 else Vector2.DOWN
	elif gravity_dir < 0.0:
		dir = -1.0
	if not is_on_floor():
		velocity.y += GRAVITY * dir * delta

	# Issue #65/#121: only the active character of the team on turn may
	# act — regardless of which team that is, so AI vs AI duels work.
	if TurnController.game_over or TurnController.active_member != self:
		velocity.x = 0.0
		move_and_slide()
		return

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

	# Issue #66: slew the view angle toward the target so the weapon aims
	# where the NPC looks (positive angle raises the muzzle).
	var vertical := (_target.global_position.y - global_position.y) * dir
	var desired_angle := atan2(-vertical, maxf(absf(to_target.x), 1.0))
	view_angle = move_toward(view_angle, clampf(desired_angle, -VIEW_MAX, VIEW_MAX), AIM_SPEED * AIM_SPEED_MULT[difficulty] * delta)

	var direction := 0.0
	if absf(to_target.x) > 16.0:
		direction = signf(to_target.x)
	# Separation: back off from other enemies we are stacking on.
	for other in get_tree().get_nodes_in_group("enemy_team"):
		if other == self:
			continue
		var away: float = global_position.x - other.global_position.x
		if absf(away) < SEPARATION and absf(global_position.y - other.global_position.y) < 40.0:
			direction += signf(away) * 0.5
	velocity.x = clampf(direction, -1.0, 1.0) * SPEED

	# Jump when blocked or when the target is clearly above us.
	if is_on_floor() and (is_on_wall() or (_target.global_position.y - global_position.y) * gravity_dir < -80.0):
		velocity.y = JUMP_VELOCITY * dir

	# Issue #66: pick the weapon by distance and take a shot when in range.
	if distance <= ATTACK_RANGE and _cooldown_left == 0.0:
		_pick_weapon(distance, absf(_target.global_position.y - global_position.y))
		_shoot()
		_cooldown_left = FIRE_PAUSE[difficulty]

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
		# Smooth climb: animate up over a fraction of a second instead of
		# snapping instantly.
		velocity = Vector2.ZERO
		_climb_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_climb_tween.tween_property(self, "global_position", other.global_position - Vector2(0.0, 64.0) * dir, 0.2)
		return


## Issue #66 rework: pick an opposing figure — the lowest-health one within
## attack range (focus fire), otherwise the nearest one. Re-evaluated every
## frame, so when a target dies the NPC naturally switches to another.
func _nearest_opponent() -> Node2D:
	var best: Node2D = null
	var nearest_distance := INF
	var best_health := INF
	for group in ["player", "team", "player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node2D
			if candidate == null:
				continue
			# Issue #121: never target a figure from our own side.
			if _same_side(candidate):
				continue
			var d := global_position.distance_to(candidate.global_position)
			# Track the plain nearest figure as the fallback target.
			if d < nearest_distance:
				nearest_distance = d
				if best == null:
					best = candidate
			# Focus fire: prefer the weakest figure in attack range.
			if d <= ATTACK_RANGE and candidate.get("health") != null \
					and float(candidate.get("health")) < best_health:
				best_health = float(candidate.get("health"))
				best = candidate
	return best


## Issue #121: true when the figure fights for the same team as we do.
func _same_side(other: Node2D) -> bool:
	if other == self:
		return true
	if is_in_group("player_team"):
		return other.is_in_group("player_team")
	return other.is_in_group("enemy_team")


## Issue #66: choose the weapon that fits the distance to the target.
func _pick_weapon(distance: float, height_diff: float = 0.0) -> void:
	if _weapon == null:
		return
	if distance <= SPEAR_RANGE_NPC:
		_weapon.selected_weapon = 3  # spear
	elif distance <= SHOTGUN_RANGE_NPC and height_diff <= 60.0:
		_weapon.selected_weapon = 0  # shotgun (flat line of sight only)
	else:
		# Issue #99: prefer the ballistic grenade for long range or any
		# height difference — its arc reaches targets over terrain, while a
		# straight rocket just hits the platform underside (or the blast
		# catches the shooter's own team below instead of the target).
		_weapon.selected_weapon = 2  # grenade


## Issue #66: fire through the carried Weapon (it owns the cooldown, the
## projectile types and the shooter pass-through from issue #57).
func _shoot() -> void:
	if _weapon == null:
		return
	# Issue #99: hand the current target to the weapon so grenades are
	# lobbed ballistically at it (see Weapon._fire_grenade).
	_weapon.npc_target = _target
	# Issue #99: never fire a straight-line weapon through a teammate — the
	# projectile hits the teammate first (friendly fire since #57) and the
	# enemy team wipes itself out while the players stay untouched. Switch
	# to the ballistic grenade, which arcs over the row; at spear-close
	# range the grenade blast would catch our own team, so hold fire there
	# (the separation steering opens the line instead).
	if _weapon.selected_weapon != 2 and _teammate_blocks_shot():
		if _target != null and is_instance_valid(_target) \
				and global_position.distance_to(_target.global_position) > 160.0:
			_weapon.selected_weapon = 2
		else:
			return
	_weapon.npc_fire()


## Issue #99: true when a living teammate stands inside the corridor a
## straight projectile would travel between us and the current target.
func _teammate_blocks_shot() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var to := _target.global_position - global_position
	var length := to.length()
	if length < 1.0:
		return false
	var dir := to / length
	for mate in get_tree().get_nodes_in_group(
			"player_team" if is_in_group("player_team") else "enemy_team"):
		if mate == self or not is_instance_valid(mate):
			continue
		var rel: Vector2 = mate.global_position - global_position
		var along := rel.dot(dir)
		if along <= 0.0 or along >= length:
			continue
		if absf(rel.cross(dir)) <= 44.0:
			return true
	return false
