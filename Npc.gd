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
const BotController := preload("res://BotController.gd")

const SPEED := Stats.SPEED
const GRAVITY := Stats.GRAVITY
## Issue #308: only the FOCUS-FIRE window (prefer the weakest figure this
## close); targeting and firing themselves are level-wide now.
const ATTACK_RANGE := 500.0
const KEEP_DISTANCE := 140.0
## Issue #66: aim slew speed (rad/s) and per-weapon range bands.
const SPEAR_RANGE_NPC := 90.0
## Issue #430: raised to the shotgun's real flight range (900 px/s *
## 0.5 s = 450; the band claimed 360 while pellets only flew 315).
const SHOTGUN_RANGE_NPC := 450.0
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

## Issue #226: figure body shape of this NPC's team (square, circle,
## triangle, star or ellipse — same vocabulary as Player.team_shape).
## Square keeps the plain ColorRect body; other shapes draw a
## ShapeVisual body (see _apply_team_shape).
@export var team_shape := "square"

## Issue #121: which side this AI fights for. "enemy" (default) behaves
## exactly as before; "player" places the figure in the player team, so a
## level can stage a computer-vs-computer duel the user only spectates.
@export var team: String = "enemy"

## Issue #293: gravity is no longer authored per figure — the level's
## indestructible grounds are the ONLY gravity source (LevelTerrain), so
## the old gravity_dir/center_line_y exports are gone.

var health: int = MAX_HEALTH
var _bar_fill: ColorRect
var _visual: ColorRect
## Issue #226: ShapeVisual body drawn instead of the ColorRect body when
## the team shape is not a square.
var _shape_visual: Control
var _dead := false
var _target: Node2D
var _cooldown_left := 0.0

## Issue #277 rework 2 ("the character is flying, but it must be
## grounded"): jump cool-down. The old trigger re-fired the jump on EVERY
## tick an NPC touched ground, so an NPC blocked beside its target (or
## with the target "above" it) hop-spammed ~2/s and spent half its turn
## airborne — "flying". With the cool-down a blocked NPC hops at most
## once a second and otherwise stays grounded, aims and shoots.
const JUMP_COOLDOWN := 1.0
var _jump_left := 0.0
## Issue #409: the shrink-out death tween, kept so an episode reset
## (BotController.reset) can cancel a death that is mid-animation
## (same field in Player.gd).
var death_tween: Tween
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
## Issue #255 rework: the shield blocks ONE attack — the block consumes
## it. Identical logic in Player.gd: every figure shields the same way,
## player's or computer's.
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

## Issue #481: this NPC already fired this turn — the weapon choice is
## locked until its next turn begins. The player-side rule of issues
## #131/#143 (the FIRST shot of the turn fixes the weapon for that
## character) now applies to the computer too: the distance-based
## re-pick must never swap guns after a shot has left, so an AI can no
## longer thrust the spear and finish the same turn with the shotgun.
var _weapon_locked := false


## Issue #277: the gravity unit vector the last physics frame used — the
## frame the aim/view lives in (see aim_dir). Mirrors Player.
var _aim_grav := Vector2.DOWN

## Issue #277 rework: the frame's walking/aiming tangent, oriented by
## CONTINUITY with the previous frame instead of the world-x pin — the
## old "flip while tangent.x < 0" rule flipped 180° at a disc's 3/9
## o'clock rims (vertical tangent) and reversed the NPC's walk/aim there.
## Mirrors Player._aim_tangent; starts at the legacy flat-frame axis.
var _aim_tangent := Vector2.RIGHT

## Issue #66/#277: aim direction — the gravity frame's surface tangent
## (facing sign applied) raised/lowered by view_angle away from the floor,
## mirroring Player.aim_dir. Flat and center-line levels keep exactly the
## old formula; on radial gravity the aim rotates with the figure so the
## indicated direction matches the character's stance. `dir` is kept for
## call compatibility only.
func aim_dir(facing: float, _dir: float) -> Vector2:
	return _aim_tangent * (cos(view_angle) * facing) \
			- _aim_grav * sin(view_angle)

## Issue #277: the current gravity frame — Weapon faces along the walking
## surface; the AI measures targets in the same frame.
func current_gravity() -> Vector2:
	return _aim_grav

## Issue #277 rework: the gravity frame's walking tangent — +x on flat
## levels (the legacy axis), along the surface on radial ones. Oriented by
## continuity with the previous frame (see _aim_tangent); public so the
## Weapon faces along the same continuous axis the NPC walks and aims on.
func current_tangent() -> Vector2:
	return _aim_tangent

## Issue #518: re-anchor the gravity frame after a DISCRETE position
## jump — the NPC's teleport-away hop (issue #221) must not carry the
## old spot's tangent orientation to the new one: on Level4 a hop from
## the bottom-right corner arc to the floor underside kept a 180°
## mirrored frame and the NPC walked the wrong way. Same anchor as a
## fresh spawn (and Player.reanchor_gravity_frame): the tangent
## orientation with a NON-NEGATIVE x component, so the walk/aim frame
## is screen-right wherever the hop lands.
func reanchor_gravity_frame() -> void:
	var grav := Vector2.DOWN
	if LevelTerrain.has_sources(self):
		grav = LevelTerrain.gravity_vector(self)
	_aim_grav = grav
	var tangent := Vector2(grav.y, -grav.x)
	if tangent.x < 0.0:
		tangent = -tangent
	_aim_tangent = tangent
	up_direction = -grav
	FigurePose.align_to_gravity(self, grav)


## Issue #60: tint every ColorRect visual authored in the scene (captured
## before the health bar adds its own ColorRects) with the team color.
func _apply_team_color() -> void:
	for child in get_children():
		var rect := child as ColorRect
		if rect != null:
			rect.color = team_color


## Issue #226: apply the team's body shape after the fact (called by
## GameConfig.apply once the level staged the teams).
func set_team_shape(value: String) -> void:
	team_shape = value
	_apply_team_shape()


## Issue #226: non-square team shapes replace the plain ColorRect body
## with a ShapeVisual drawing the team polygon (mirrors Player.gd).
func _apply_team_shape() -> void:
	if team_shape == "square" or _visual == null:
		return
	if _shape_visual == null:
		_visual.visible = false
		_shape_visual = load("res://scripts/ShapeVisual.gd").new()
		_shape_visual.name = "VisualShape"
		_shape_visual.offset_left = -32.0
		_shape_visual.offset_top = -32.0
		_shape_visual.offset_right = 32.0
		_shape_visual.offset_bottom = 32.0
		add_child(_shape_visual)
		_shape_visual.set_shape(team_shape)
		_shape_visual.set_shape_color(team_color)
	# Issue #282: the ShapeVisual body is appended after the Weapon node
	# (Npc._ready adds the weapon last, but GameConfig.apply calls
	# set_team_shape AFTER _ready) — that drew the held weapon/tool BEHIND
	# the figure. Keep the Weapon the last child; it draws in front.
	_keep_weapon_in_front()


## Issue #282: the held weapon/tool must render IN FRONT of the character
## body — every body visual (ColorRect, ShapeVisual) stays BEFORE the
## Weapon node in the child order (tree order decides which CanvasItem
## draws on top among same-z siblings). Mirrors Player.gd.
func _keep_weapon_in_front() -> void:
	var weapon := get_node_or_null("Weapon")
	if weapon != null:
		move_child(weapon, get_child_count() - 1)


## Issue #226: tint whichever body visual is active (hit flash).
func _set_body_color(value: Color) -> void:
	if _shape_visual != null:
		_shape_visual.set_shape_color(value)
	else:
		_visual.color = value


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
	# Issue #406: the body push-box is 10% shorter vertically (64 -> 57.6)
	# so figures brush past each other's shoulders more easily.
	capsule.height = 57.6
	shape.shape = capsule
	add_child(shape)

	# Issue #226 rework: Level2/3/4 author the NPC body ColorRect in the
	# scene ("NpcVisual") — ADOPT it as the one body instead of stacking a
	# second code-made square: a non-square team shape hid only the code
	# rect, so the figure wore square AND circle shapes simultaneously.
	for child in get_children():
		var authored := child as ColorRect
		if authored != null:
			_visual = authored
			break
	if _visual == null:
		_visual = ColorRect.new()
		_visual.offset_left = -32.0
		_visual.offset_top = -32.0
		_visual.offset_right = 32.0
		_visual.offset_bottom = 32.0
		add_child(_visual)
	_visual.color = team_color
	_apply_team_shape()

	_build_health_bar()
	# Issue #252: debug-mode visuals — HP number, damage popup, arrow.
	DebugInfo.attach(self)
	DebugInfo.update_hp(self, health, MAX_HEALTH)
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
	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.offset_left = -70.0
	name_label.offset_top = -62.0
	name_label.offset_right = 70.0
	name_label.offset_bottom = -46.0
	add_child(name_label)

	var background := ColorRect.new()
	# Issue #270: named so FigurePose (and any pose/HUD pass, like
	# Player.gd's) can tell the health bar from the BODY visual rect.
	background.name = "HealthBarBackground"
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
	# Issue #252: keep the debug HP number near the figure in sync.
	DebugInfo.update_hp(self, health, MAX_HEALTH)
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


## Issue #364: first aid kits heal NPCs exactly like player figures
## (Player.heal) — same clamp at MAX_HEALTH; dead figures stay dead
## (issue #151).
func heal(amount: int) -> void:
	if _dead:
		return
	health = clampi(health + amount, 0, MAX_HEALTH)
	_update_bar()


func take_damage(amount: int, attacker: Node2D = null) -> void:
	if _dead:
		return
	# Issue #221: the energy shield blocks all damage until the next turn.
	# Issue #255 rework: the shield blocks ONE attack — blocking consumes
	# it (same rule as Player.take_damage, no player/NPC difference).
	if shielded:
		set_shielded(false)
		# Issue #252: action-log line — the shield absorbed the hit.
		DebugInfo.log("%s's shield blocked %d damage" % [display_name, amount])
		return
	health = clampi(health - amount, 0, MAX_HEALTH)
	# Issue #433: the REWARD_SPEC §2 combat components (proportional
	# damage §2.1, kill bonus on the killing blow §2.2, friendly fire
	# §2.6) are credited to the attacker's controller the moment the
	# damage lands — after health is applied, so a killing blow is
	# detectable; the training framework zeroes the property per step,
	# the figures never manage it.
	BotController.credit_combat_reward(attacker, self, amount)
	_update_bar()
	# Issue #252: debug damage number + action-log line.
	DebugInfo.show_damage(self, amount)
	DebugInfo.log("%s takes %d damage (%d/%d)" % [display_name, amount, health, MAX_HEALTH])
	# Issue #335: comics line near the figure — the victim cries out (or
	# calls out an ALLY's betrayal) and a big hit makes the attacker
	# gloat; identical logic in Player.take_damage.
	CharacterLines.on_damage_taken(self, amount, attacker)
	# Hit flash.
	_set_body_color(Color(1.0, 0.6, 0.7, 1))
	get_tree().create_timer(0.1).timeout.connect(
		func() -> void: _set_body_color(team_color))
	if health == 0:
		# Issue #433: REWARD_SPEC §2.3 — the controller that plays this
		# figure takes the once-per-death penalty at the moment of death,
		# whatever killed it (_die() sets _dead right after, so it fires
		# exactly once).
		BotController.notify_figure_died(self)
		_die()


func _die() -> void:
	_dead = true
	# Issue #252: action-log line — the figure left the field.
	DebugInfo.log("%s died" % display_name)
	# Issue #335: if this leaves exactly one teammate alive, the survivor
	# is "left alone in the team" and speaks up.
	CharacterLines.on_member_death(self)
	# Issue #280: an NPC may HOST the shared camera (LevelDuel authors it
	# under an NPC figure) — rescue it exactly like Player._die does for
	# the player team (issue #222): reparent it to the level and keep it
	# enabled. Without this the death animation's queue_free() frees the
	# camera together with its host, and after the match the view is
	# blocked — no camera, no zoom, no drag-pan, no spectating.
	for child in get_children():
		if child is Camera2D and child.is_in_group("player_camera"):
			child.reparent(get_parent())
			child.enabled = true
			break
	# Tiny death puff: shrink out, then free.
	set_physics_process(false)
	death_tween = create_tween()
	death_tween.tween_property(self, "scale", Vector2.ZERO, 0.25)
	death_tween.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_jump_left = maxf(0.0, _jump_left - delta)
	# Issue #190: gravity toward the nearest indestructible surface when the
	# level authors gravity sources; legacy central-line / global-down rules
	# otherwise. Destructible ground never causes gravity.
	# Issue #293: the gravity field is no longer configured separately from
	# the terrain — indestructible grounds are the ONLY gravity source, so
	# the authored central-line/gravity_dir overrides are gone. A figure
	# standing on the underside of a ceiling ground falls UP toward it.
	var grav := Vector2.DOWN
	if LevelTerrain.has_sources(self):
		grav = LevelTerrain.gravity_vector(self)
	up_direction = -grav
	# Issue #277: the aim/view lives in the CURRENT gravity frame.
	_aim_grav = grav
	# Issue #277 rework: re-orient the tangent by continuity (see _aim_tangent).
	var tangent := Vector2(grav.y, -grav.x)
	if tangent.dot(_aim_tangent) < 0.0:
		tangent = -tangent
	_aim_tangent = tangent
	# Issue #270: rotate the BODY visual/collision so the figure's bottom
	# faces the ground under any gravity direction (radial arenas included);
	# HUD, weapon and camera keep the world frame (FigurePose for details).
	FigurePose.align_to_gravity(self, grav)
	# Issue #311: the HUD text (name, health bar, debug HP) must live in the
	# coordinate system the view CURRENTLY shows — with the character camera
	# (#289) the view itself rotates, so world-aligned text would render
	# tilted/upside-down on screen. No-op for the world-aligned static view.
	HudPose.align_to_view(self)
	# Issue #250 rework: NPC walking lives in the gravity frame's tangent,
	# not on the world x axis — on the circular arena world-x movement
	# launched figures off the curved surface into ballistic up-down
	# flights. The tangent itself (_aim_tangent, updated above) is oriented
	# by continuity, so the walk never flips 180° around a disc rim.
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
			and TurnController.active_member == self \
			and not TurnController.is_input_frozen()
	if active and not _active_last:
		_begin_my_turn()
	_active_last = active
	if not active:
		# Issue #250 rework: zero the walk along the surface (the tangent
		# frame), keep the fall/jump component along gravity.
		velocity = grav * velocity.dot(grav)
		move_and_slide()
		return

	_target = _nearest_opponent()
	if _target == null:
		# Issue #58: stop instantly instead of gliding to a halt
		# (tangent frame — see the walk step below).
		velocity = grav * velocity.dot(grav)
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
	# Issue #277: measure the target in the CURRENT gravity frame — the aim
	# rotates with radial gravity, so world-x/y deltas would slew the view
	# toward an angle that no longer points at the target. Flat and
	# center-line levels: identical to the old world-axis formula.
	var aim_offset := _target.global_position - global_position
	var vertical := aim_offset.dot(_aim_grav)
	# Issue #147: slew the aim onto the ACTUAL target (not the flank goal)
	# so the hold-fire gate below can actually converge.
	var desired_angle := atan2(-vertical, maxf(absf(aim_offset.dot(_aim_tangent)), 1.0))
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
	# Issue #250 rework: walk in the gravity frame's tangent (see above) —
	# the AI keeps its world-x heuristics, but the step itself follows the
	# surface instead of launching the figure off it.
	velocity = _aim_tangent * clampf(direction, -1.0, 1.0) * SPEED \
			+ grav * velocity.dot(grav)

	# Jump when blocked or when the target is clearly above us.
	# Issue #277 rework 2 ("the character is flying, but it must be
	# grounded"): "clearly above" is measured in the CURRENT gravity frame
	# (along the frame's up, -_aim_grav), not in world y — on the disc arena
	# the player team sits world-above from most rim positions, so the old
	# world-y test ((target.y - y) * gravity_dir < -80) made every arriving
	# NPC jump for the sky instead of standing and fighting. Flat and
	# center-line levels keep exactly the old trigger (the frame's up IS the
	# world ±y axis there, gravity_dir included); plus the jump now cools
	# down (JUMP_COOLDOWN) so a blocked NPC hops deliberately, not twice a
	# second.
	var target_above := (_target.global_position - global_position) \
				.dot(_aim_grav) < -80.0
	if _jump_left <= 0.0 and is_on_floor() \
				and (is_on_wall() or target_above):
		# Issue #202: jump must point AWAY from the floor (see Player.gd).
		velocity = grav * JUMP_VELOCITY
		_jump_left = JUMP_COOLDOWN

	# Issue #66: pick the weapon by distance and take a shot when in range.
	# Issue #147: hold fire until we actually face the target and the view
	# angle has slewed onto it — no more blind flat shots while the aim is
	# still turning (cooldown stays at 0, so the shot fires as soon as the
	# aim lines up).
	# Issue #308: the computer sees an enemy at ANY point of the level —
	# the old `distance <= ATTACK_RANGE` cap left far figures untouchable,
	# so the AI could only walk (and burned its turn standing when the way
	# was blocked). _pick_weapon resolves EVERY distance — the ballistic
	# grenade is the far band — so the gate is aim + cooldown only.
	if _cooldown_left == 0.0 and _aim_ready() and not _tool_used:
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
	# Issue #481: a fresh turn unlocks the weapon choice — the lock is
	# per turn, exactly like the player's WeaponInventory lock reset.
	_weapon_locked = false
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
			# Issue #518: re-anchor the walking/aiming frame at the hop
			# destination (same rule as the player teleport tool) — the hop
			# must not carry the old spot's tangent orientation over.
			reanchor_gravity_frame()
			# Issue #475: the NPC hop uses the same teleport sound as the
			# player tool (ToolInventory owns the player).
			ToolInventory.play_teleport_sound()
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
	# Facing: never fire away from the target (Issue #277: measured along
	# the gravity tangent — the walking/aim axis — not the world x axis).
	var facing: float = _weapon._facing if _weapon != null else 1.0
	var along := to_target.dot(_aim_tangent)
	if signf(along) != 0.0 and signf(facing) != signf(along):
		return false
	# Aim: the slewed view angle must be on the direct line to the target
	# (Issue #277: measured in the current gravity frame).
	var desired := atan2(-to_target.dot(_aim_grav), maxf(absf(along), 1.0))
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
	# Issue #446: the team blackboard's shared FOCUS TARGET wins while it
	# is still a living opponent — the whole team converges on the same
	# figure, and each bot needs only its OWN team id (TurnController's
	# team_id_of), never a reference to any other bot.
	var shared: Node2D = TeamBlackboard.get_focus_target(
			TurnController.team_id_of(self))
	if shared != null and not _same_side(shared):
		var shared_hp = shared.get("health")
		if shared_hp == null or float(shared_hp) > 0.0:
			return shared
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
## Issue #228: a team death-match — every AI team is its OWN side, so a
## computer figure only spares figures of its own team color (and, for
## the player team, other player figures). Computers on different teams
## fight each other, not just the player.
func _same_side(other: Node2D) -> bool:
	if other == self:
		return true
	if is_in_group("player_team"):
		return other.is_in_group("player_team")
	if not other.is_in_group("enemy_team"):
		return false
	var mate_color = other.get("team_color")
	return mate_color is Color and team_color == mate_color


## Issue #66: choose the weapon that fits the distance to the target.
func _pick_weapon(distance: float, height_diff: float = 0.0) -> void:
	if _weapon == null:
		return
	# Issue #481: a shot already left this NPC's hands this turn — the
	# weapon in hands stays. The first-shot lock of issues #131/#143 is
	# the player's rule; the computer re-picking by distance on every
	# attempt silently bypassed it (spear thrust, then two shotgun shots
	# in one turn on LevelDuelBig). While locked, the re-pick is a no-op.
	if _weapon_locked:
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
	# Issue #305: the team's budget for the picked weapon may be spent —
	# fall back to the spear, whose uses are infinite (there is always
	# something left to fight with).
	if not WeaponInventory.can_spend_weapon(
			TurnController.team_id_of(self), _weapon.selected_weapon):
		_weapon.selected_weapon = 3


## Issue #66: fire through the carried Weapon (it owns the cooldown,
## the projectile types and the shooter pass-through from issue #57).
## Issue #481: returns whether a shot really left — every hold-fire
## path reports false, so the caller (and the tests) can tell a locked
## held shot from a committed one.
func _shoot() -> bool:
	if _weapon == null:
		return false
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
			# Issue #481: locked to the gun already fired — hold fire instead
			# of arcing the grenade over the teammate.
			if not _switch_weapon(2):
				return false
		else:
			return false
	# Issue #120: never lob a grenade that would land inside our own blast
	# radius — hold fire at point-blank range instead (and switch to the
	# spear so the next in-range tick closes the gap rather than re-throwing).
	if cares and _weapon.selected_weapon == 2 and _grenade_unsafe():
		# Issue #481: the swap is refused while locked — a locked AI holds
		# fire at point-blank (the stall watchdog ends its turn) instead of
		# trading the locked grenade for the spear.
		_switch_weapon(3)
		return false
	# Issue #305: never hand the weapon a gun the team can't pay for —
	# the grenade fallback above (and any stale pick) may be spent.
	if not WeaponInventory.can_spend_weapon(
			TurnController.team_id_of(self), _weapon.selected_weapon):
		# Issue #481: locked to a gun the team can no longer pay for — hold
		# fire rather than swapping to the spear; nothing useful is left, so
		# the stall watchdog hands the turn over.
		if not _switch_weapon(3):
			return false
	# Issue #481: lock the choice the moment a shot REALLY leaves —
	# npc_fire() reports the commit (it can refuse on quota, cooldown or
	# budget), and a refused order must not freeze the choice it never
	# fired with.
	var fired: bool = _weapon.npc_fire()
	if fired:
		_weapon_locked = true
	return fired


## Issue #481: change the held weapon — refused once this NPC has fired
## this turn (the one-weapon-per-turn rule of issues #131/#143, applied to
## the AI: no weapon change after the use). Returns true when the switch
## actually happened.
func _switch_weapon(id: int) -> bool:
	if _weapon_locked:
		return false
	_weapon.selected_weapon = id
	return true


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
		# Issue #228: only TRUE teammates block the shot — a figure from
		# another AI team standing in the line is fair collateral damage.
		if not _same_side(mate):
			continue
		var rel: Vector2 = mate.global_position - global_position
		var along := rel.dot(dir)
		if along <= 0.0 or along >= length:
			continue
		if absf(rel.cross(dir)) <= 44.0:
			return true
	return false
