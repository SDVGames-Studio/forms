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

## Issue #180: AI friendly-fire, from the TEAM configuration — 0 = always
## avoid hitting teammates, 10 = does not care at all (in between the
## avoidance checks are applied probabilistically per shot).
@export_range(0, 10) var ai_friendly_fire := 0
var _flank_slot := 0.0  # Per-instance offset so team members spread out.
## Issue #221: energy shield — while true the figure takes no damage
## (the same Shield tool the player team has, issue #170).
var shielded := false
var _shield_rect: ColorRect
## Issue #221: per-turn AI state — a tool already spent this turn's
## action, the "nothing useful left" watchdog and the last position used
## to detect REAL movement (a blocked walk does not count).
var _tool_used := false
var _turn_stall := 0.0
var _last_pos := Vector2.ZERO
var _active_last := false
## Issue #66: current aim (view) angle in radians, like Player.gd.
var view_angle := 0.0
const AIM_SPEED := Stats.VIEW_SPEED
## Issue #137: per-difficulty aim slew and between-shot pause.
const AIM_SPEED_MULT := [0.5, 1.0, 1.5]
const FIRE_PAUSE := [2.0, 0.9, 0.0]
## Issue #120: grenade blasts are lethal at point-blank — never lob one
## that would land inside our own blast radius. Below this distance the
## NPC holds grenade fire (the spear closes the gap instead).
const GRENADE_MIN_RANGE := 130.0
## Issue #120: below this health fraction the AI kites — backs away from
## the target instead of walking deeper into danger, while still shooting.
## Issue #221: raised from 0.3 — the hurt AI now plays a TOOL (shield or
## teleport) and keeps its distance instead of trading blows.
const KITE_HEALTH_FRACTION := 0.35
## Issue #221: tool play — a badly hurt AI (health fraction at or below
## KITE_HEALTH_FRACTION) defends itself with its tools instead of firing:
## TELEPORT away when an enemy is breathing down its neck, SHIELD when
## the threat is merely near. The tool spends the turn's action (tool OR
## weapon, mirroring the player rule of issue #207). Easy AI (difficulty
## 0) fights as before.
const TOOL_THREAT_RANGE := 360.0
const TELEPORT_THREAT_RANGE := 170.0
## Issue #221: seconds of "nothing useful left" (not really moving, not
## firing, weapon idle) before the AI ends its own turn early instead of
## standing around until the turn timer runs out.
const STALL_SKIP_AFTER := 3.0
## Issue #221: inside this band only the spear or the flat shotgun are
## allowed — a grenade or rocket detonating that close self-harms.
const SHOTGUN_CLOSE_NPC := 200.0
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
	# character layers) but never push — a walking figure is simply BLOCKED
	# by another figure (issue #144: one character must not move or
	# displace another during its move).
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	# Issue #155: characters are never platforms for each other (see
	# Player.gd) — a walking figure cannot carry an enemy standing on it.
	platform_floor_layers = 1
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
	# Issue #154: capsule instead of a circle — a round figure wedges into
	# the notch between the ground and another figure/wall and gets stuck;
	# the flat capsule sides slide along obstacles instead.
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 64.0
	shape.shape = capsule
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


## Issue #221: toggle the energy shield (and its visual bubble) — the
## same Shield tool the player team has (issue #170). TurnController
## clears it when this team's next turn begins.
func set_shielded(value: bool) -> void:
	shielded = value
	if shielded and _shield_rect == null:
		_shield_rect = ColorRect.new()
		_shield_rect.name = "Shield"
		_shield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shield_rect.offset_left = -BAR_WIDTH / 2.0 - 4.0
		_shield_rect.offset_top = -44.0 - BAR_HEIGHT - 8.0
		_shield_rect.offset_right = BAR_WIDTH / 2.0 + 4.0
		_shield_rect.offset_bottom = -44.0 + 24.0
		_shield_rect.color = Color(0.25, 0.4, 0.95, 0.35)
		add_child(_shield_rect)
	if _shield_rect != null:
		_shield_rect.visible = shielded


func take_damage(amount: int) -> void:
	if _dead:
		return
	# Issue #221: the energy shield blocks all damage until the next turn.
	if shielded:
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
	# Issue #190: gravity toward the nearest indestructible surface when the
	# level authors gravity sources; legacy central-line / global-down rules
	# otherwise. Destructible ground never causes gravity.
	var grav := Vector2.DOWN
	if LevelTerrain.has_sources(self):
		grav = LevelTerrain.gravity_vector(self)
		dir = 1.0 if grav.y >= 0.0 else -1.0
	else:
		if center_line_y > 0.0:
			dir = 1.0 if global_position.y < center_line_y else -1.0
			up_direction = Vector2.UP if dir > 0.0 else Vector2.DOWN
		elif gravity_dir < 0.0:
			dir = -1.0
		grav = Vector2.DOWN if dir > 0.0 else Vector2.UP
	up_direction = -grav
	if not is_on_floor():
		velocity += grav * GRAVITY * delta

	# Issue #65/#121: only the active character of the team on turn may
	# act — regardless of which team that is, so AI vs AI duels work.
	# Issue #183: the team check is explicit — an NPC must never act while
	# the OPPONENT's turn is active, even if a stale/lost active_member
	# still points at it (that desync let the computer move and shoot
	# during the player's move).
	var my_team: String = TurnController.team_id_of(self)
	# Issue #221: track the activation edge — the first tick of this NPC's
	# OWN turn runs the tool decisions and resets the per-turn AI state.
	var active: bool = not TurnController.game_over \
			and TurnController.active_team == my_team \
			and TurnController.active_member == self
	if active and not _active_last:
		_begin_my_turn()
	_active_last = active
	if not active:
		velocity.x = 0.0
		move_and_slide()
		return

	_target = _nearest_opponent()
	if _target == null:
		# Issue #58: stop instantly instead of gliding to a halt.
		velocity.x = 0.0
		move_and_slide()
		# Issue #221: nothing left to fight — hand the turn over at once
		# instead of burning the whole timer (the win check follows).
		TurnController.skip_turn(self)
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
	# Issue #147: slew the aim onto the ACTUAL target (not the flank goal)
	# so the hold-fire gate below can actually converge.
	var desired_angle := atan2(-vertical, maxf(absf(_target.global_position.x - global_position.x), 1.0))
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
	# Issue #120: kite at low health — back away from the target instead of
	# pressing into it, while still shooting from the safety of range.
	if _wants_retreat(distance):
		direction = -signf(to_target.x)
	# Issue #221: after a defensive tool the AI does not re-engage — it
	# holds its safe distance and lets the stall watchdog hand the turn
	# over once nothing useful is left.
	if _tool_used and not _wants_retreat(distance):
		direction = 0.0
	velocity.x = clampf(direction, -1.0, 1.0) * SPEED

	# Jump when blocked or when the target is clearly above us.
	if is_on_floor() and (is_on_wall() or (_target.global_position.y - global_position.y) * gravity_dir < -80.0):
		# Issue #202: jump must point AWAY from the floor (see Player.gd).
		velocity = grav * JUMP_VELOCITY

	# Issue #66: pick the weapon by distance and take a shot when in range.
	# Issue #147: hold fire until we actually face the target and the view
	# angle has slewed onto it — no more blind flat shots while the aim is
	# still turning (cooldown stays at 0, so the shot fires as soon as the
	# aim lines up).
	if distance <= ATTACK_RANGE and _cooldown_left == 0.0 and _aim_ready() \
			and not _tool_used:
		_pick_weapon(distance, absf(_target.global_position.y - global_position.y))
		_shoot()
		_cooldown_left = FIRE_PAUSE[difficulty]

	# Issue #221: stall watchdog — ended turns instead of idle standing.
	_update_stall(delta)

	move_and_slide()


## Issue #221: the AI's own turn just began — reset the per-turn state
## and play a TOOL when badly hurt near the enemy: teleport out of
## point-blank trouble, otherwise raise the shield. The tool spends the
## turn's action (tool OR weapon, like the player rule of issue #207),
## so a hurt AI retreats and hands over instead of trading blows it
## would lose. Easy AI (difficulty 0) skips the tool play.
func _begin_my_turn() -> void:
	_tool_used = false
	_turn_stall = 0.0
	_last_pos = global_position
	if difficulty < 1 \
			or float(health) > float(MAX_HEALTH) * KITE_HEALTH_FRACTION:
		return
	var enemy := _nearest_opponent()
	if enemy == null:
		return
	var distance := global_position.distance_to(enemy.global_position)
	if distance <= TELEPORT_THREAT_RANGE and _try_teleport_away(enemy):
		_tool_used = true
		return
	if distance <= TOOL_THREAT_RANGE:
		set_shielded(true)
		_tool_used = true


## Issue #221: TELEPORT tool — hop away from the threatening enemy to
## the nearest collision-free spot that keeps every opponent at a safe
## distance. Returns true when a hop was made.
func _try_teleport_away(enemy: Node2D) -> bool:
	var away := signf(global_position.x - enemy.global_position.x)
	if away == 0.0:
		away = 1.0 if randf() < 0.5 else -1.0
	var space := get_world_2d().direct_space_state
	for dist in [260.0, 330.0, 190.0, 400.0, 130.0]:
		for lift in [0.0, -80.0, 80.0]:
			var candidate := Vector2(global_position.x + away * dist,
					global_position.y + lift)
			if not _teleport_spot_free(space, candidate):
				continue
			if _nearest_opponent_distance_at(candidate) < TELEPORT_THREAT_RANGE:
				continue
			global_position = candidate
			velocity = Vector2.ZERO
			return true
	return false


## Issue #221: true when the point is clear of solid world geometry
## (layer 1 = terrain, layer 8 = borders — characters may be overlapped,
## the body slides out of them).
func _teleport_spot_free(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1 | 8
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_point(query, 1).is_empty()


## Issue #221: distance from `point` to the closest living opponent
## (INF when there is none).
func _nearest_opponent_distance_at(point: Vector2) -> float:
	var best := INF
	for group in ["player", "team", "player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node2D
			if candidate == null or _same_side(candidate):
				continue
			var d: float = point.distance_to(candidate.global_position)
			if d < best:
				best = d
	return best


## Issue #221: the stall watchdog — when the AI is not really moving and
## its weapon is idle, it has nothing useful left to do: after
## STALL_SKIP_AFTER seconds it ends its own turn (the AI analogue of the
## player's Tab skip, #102) instead of standing idle until the timer
## runs out. REAL movement counts (distance from the last tick), so a
## walk blocked by a wall still accumulates the stall.
func _update_stall(delta: float) -> void:
	var moved := global_position.distance_to(_last_pos) > 0.5
	_last_pos = global_position
	if moved or (_weapon != null and _weapon.is_busy()):
		_turn_stall = 0.0
		return
	_turn_stall += delta
	if _turn_stall >= STALL_SKIP_AFTER:
		_turn_stall = 0.0
		TurnController.skip_turn(self)


## Issue #147: true when the shot direction matches the target — the NPC
## is turned toward it and the view angle is within tolerance of the
## direct aim angle at the target.
const AIM_TOLERANCE := 0.12  # rad

func _aim_ready() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var to_target := _target.global_position - global_position
	# Facing: never fire away from the target.
	var facing: float = _weapon._facing if _weapon != null else 1.0
	if signf(to_target.x) != 0.0 and signf(facing) != signf(to_target.x):
		return false
	# Aim: the slewed view angle must be on the direct line to the target.
	var dir := 1.0 if (center_line_y <= 0.0 or global_position.y < center_line_y) else -1.0
	var desired := atan2(-(to_target.y * dir), maxf(absf(to_target.x), 1.0))
	return absf(view_angle - clampf(desired, -VIEW_MAX, VIEW_MAX)) <= AIM_TOLERANCE



## Issue #120: true when this NPC is badly hurt and the target is close
## enough that pressing the attack is riskier than falling back.
func _wants_retreat(distance: float) -> bool:
	if health > int(float(MAX_HEALTH) * KITE_HEALTH_FRACTION):
		return false
	# Issue #221: the hurt AI keeps its distance as soon as the threat is
	# merely NEAR (not already on top of it) — it played a tool this turn
	# and now disengages instead of trading blows.
	return distance < TOOL_THREAT_RANGE



## Issue #66 rework: pick an opposing figure — the lowest-health one within
## attack range (focus fire), otherwise the nearest one. Re-evaluated every
## frame, so when a target dies the NPC naturally switches to another.
func _nearest_opponent() -> Node2D:
	var fallback: Node2D = null
	var nearest_distance := INF
	var focus: Node2D = null
	var best_health := INF
	for group in ["player", "team", "player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node2D
			if candidate == null:
				continue
			# Issue #121: never target a figure from our own side.
			if _same_side(candidate):
				continue
			# Issue #221: dying (0-health) figures are skipped outright.
			var hp = candidate.get("health")
			if hp != null and float(hp) <= 0.0:
				continue
			var d := global_position.distance_to(candidate.global_position)
			# Track the plain nearest figure as the fallback target
			# (issue #221: the TRUE nearest — the old code kept the
			# first-seen figure and ignored a closer enemy).
			if d < nearest_distance:
				nearest_distance = d
				fallback = candidate
			# Focus fire: prefer the weakest figure in attack range.
			if d <= ATTACK_RANGE and hp != null and float(hp) < best_health:
				best_health = float(hp)
				focus = candidate
	return focus if focus != null else fallback


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
		_weapon.selected_weapon = 3  # spear (melee)
	elif distance <= SHOTGUN_CLOSE_NPC:
		# Issue #221: at close range only melee or the flat shotgun — a
		# lobbed grenade or a rocket detonating that near self-harms, even
		# when the target sits above us.
		_weapon.selected_weapon = 0  # shotgun
	elif distance <= SHOTGUN_RANGE_NPC and height_diff <= 60.0:
		_weapon.selected_weapon = 0  # shotgun (flat line of sight only)
	elif distance <= ROCKET_RANGE_NPC and height_diff <= 40.0 \
			and not _teammate_blocks_shot():
		# Issue #221: the flat rocket finally gets used — it reaches farther
		# than the pellets on an open lane with no teammate in the corridor.
		_weapon.selected_weapon = 1  # rocket
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
	# Issue #180: the friendly-fire parameter gates the avoidance checks —
	# care = 10 - friendly_fire; the checks are skipped with probability
	# friendly_fire / 10 per shot (always run at 0, never at 10).
	var cares := randf() * 10.0 >= ai_friendly_fire
	# Issue #99: never fire a straight-line weapon through a teammate — the
	# projectile hits the teammate first (friendly fire since #57) and the
	# enemy team wipes itself out while the players stay untouched. Switch
	# to the ballistic grenade, which arcs over the row; at spear-close
	# range the grenade blast would catch our own team, so hold fire there
	# (the separation steering opens the line instead).
	if cares and _weapon.selected_weapon != 2 and _teammate_blocks_shot():
		if _target != null and is_instance_valid(_target) \
				and global_position.distance_to(_target.global_position) > 160.0:
			_weapon.selected_weapon = 2
		else:
			return
	# Issue #120: never lob a grenade that would land inside our own blast
	# radius — hold fire at point-blank range instead (and switch to the
	# spear so the next in-range tick closes the gap rather than re-throwing).
	if cares and _weapon.selected_weapon == 2 and _grenade_unsafe():
		_weapon.selected_weapon = 3
		return
	_weapon.npc_fire()


## Issue #120: true when the grenade would land within our own blast
## radius — point-blank lobs damage us more than the target.
func _grenade_unsafe() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	return global_position.distance_to(_target.global_position) < GRENADE_MIN_RANGE


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
