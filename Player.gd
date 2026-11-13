extends CharacterBody2D
## Playable figure for the simple level (issue #1).
##
## Left/right movement plus jump, driven by the move_left/move_right/jump
## actions (WASD and arrow keys, Space); gravity is applied while airborne.
##
## Issue #33: the player controls their WHOLE team — every team member uses
## this script. Exactly one member is `controlled` (driven by input); the
## rest just stay in place (issue #40). TeamController (autoload) hands
## control between members — via the Switch tool (issue #170) or its N/P
## key shortcuts (issue #215). All members share the same shape and color
## and show a name above the health bar.

## Issue #108: all characteristics come from the shared CharacterStats —
## enemy figures are the SAME class of character as player figures.
const Stats := preload("res://scripts/CharacterStats.gd")
const BotController := preload("res://BotController.gd")
const SPEED := Stats.SPEED
const JUMP_VELOCITY := Stats.JUMP_VELOCITY
const GRAVITY := Stats.GRAVITY

## Issue #293: gravity is no longer authored per figure — the level's
## indestructible grounds are the ONLY gravity source (LevelTerrain), so
## the old center_line_y/gravity_dir exports are gone.

## Issue #40: non-controlled team members just stay where they are.

signal health_changed(health: int, max_health: int)

const MAX_HEALTH := Stats.MAX_HEALTH
const BAR_WIDTH := Stats.BAR_WIDTH
const BAR_HEIGHT := Stats.BAR_HEIGHT

## Issue #33: name shown above the health bar.
@export var display_name := "Player"

## Issue #60: every member of a team wears the same team color — all
## scene-authored body visuals are tinted with it in _ready.
@export var team_color := Color(1, 0.84, 0.2, 1)

## Issue #169: figure body shape: square, circle, triangle, star or ellipse.
@export var team_shape := "square"

var health: int = MAX_HEALTH

## Issue #170: energy shield — while true the figure takes no damage.
## Set by the Shield tool; TurnController clears it at the start of the
## team's next turn ("defends until its next turn begins").
## Issue #255 rework: the shield blocks ONE attack — the block consumes
## it. Identical logic in Npc.gd: every figure shields the same way,
## player's or computer's.
var shielded := false
var _shield_rect: ColorRect

## Issue #67: character's view (aim) angle in radians, 0 = horizontal.
## Positive raises the view, negative lowers it. Controlled with the
## view_up/view_down actions (W/S and Arrow Up/Down).
const VIEW_SPEED := Stats.VIEW_SPEED
const VIEW_MAX := Stats.VIEW_MAX
var view_angle := 0.0

## Issue #277: the gravity unit vector the last physics frame used — the
## frame the aim/view lives in (see aim_dir). DOWN until the first tick
## (the legacy default).
var _aim_grav := Vector2.DOWN

## Issue #277 rework: the walking/aiming tangent of the CURRENT gravity
## frame. It is oriented by CONTINUITY — the raw tangent (grav.y, -grav.x)
## keeps whichever orientation is closest to the previous frame's — instead
## of the old "flip while tangent.x < 0" rule. That rule pinned the basis
## to the world x axis and flipped 180° exactly where the tangent is
## vertical (a disc's 3/9 o'clock rims): there the gravity's tiny numeric
## wobble reversed the basis between frames, so the weapon direction
## flipped up/down at those POSITIONS and holding D made the figure
## oscillate instead of walking on around the rim. Starting at RIGHT (the
## legacy flat-frame axis), flat and center-line levels keep the exact old
## behaviour — under the center line the raw tangent flips to (-1, 0) and
## continuity keeps it (1, 0), so "right" stays screen-right upside-down.
var _aim_tangent := Vector2.RIGHT

## Issue #67/#277: direction the character looks/aims in — the gravity
## frame's surface tangent (facing sign applied) raised/lowered by
## view_angle AWAY from the floor. Issue #270 rotated the figure body to
## the level's real gravity (radial arenas included), but the aim kept the
## world-vertical frame with only the legacy center-line flip — the weapon
## then indicated a direction that didn't correspond to the character's
## stance. With the real gravity vector, flat and center-line levels keep
## EXACTLY the old formula (the tangent is the world x axis there); on
## radial gravity the aim rotates with the figure. `dir` (the legacy
## gravity sign) is kept for call compatibility only.
func aim_dir(facing: float, _dir: float) -> Vector2:
	return _aim_tangent * (cos(view_angle) * facing) \
			- _aim_grav * sin(view_angle)

## Issue #277: the current gravity frame — Weapon uses it to face along
## the walking surface instead of the world x axis.
func current_gravity() -> Vector2:
	return _aim_grav

## Issue #277 rework: the current frame's walking tangent — Weapon faces
## along the same continuous axis the figure walks and aims on.
func current_tangent() -> Vector2:
	return _aim_tangent

## Issue #518: re-anchor the gravity frame after a DISCRETE position
## jump (teleport). The walking/aiming tangent is oriented by CONTINUITY
## with the previous physics frame (see _aim_tangent) — right while a
## figure walks or falls to a place, but a teleport arrives carrying
## whatever orientation the OLD position had. On Level4 a figure
## standing on the bottom-right corner arc (tangent rotated steeply
## downward) that teleports to the underside of the level floor kept a
## 180°-mirrored frame there: pressing D walked LEFT, A walked RIGHT.
## This snaps the frame to the same anchor a freshly spawned figure
## starts with: the tangent orientation whose x component is
## NON-NEGATIVE, so "right" is screen-right wherever the teleport
## lands — flat ground, the underside of a floor, a disc rim (the exact
## vertical rim tangent is the degenerate tie and keeps its raw
## orientation, like a fresh spawn's first tick would). Level-agnostic:
## every level whose gravity comes from indestructible ground benefits,
## not only Level4.
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
var _bar_fill: ColorRect
var _camera: Camera2D

## Issue #33: true for the member currently driven by player input.
var controlled := false


func _ready() -> void:
	# One group for every member of the player's team; the NPC team AI
	# targets "player"/"team" so all members are valid opponents.
	add_to_group("player")
	add_to_group("team")
	add_to_group("player_team")
	# Issue #33: if no team member ended up controlled (fresh scene),
	# the first one takes control.
	if not controlled:
		call_deferred("_claim_control_if_none")
	# Issue #39 rework: characters collide with each other but never push —
	# a walking figure is simply BLOCKED by another figure (issue #144:
	# one character must not move or displace another during its move).
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	# Issue #155: a character must never be carried by another character —
	# only terrain (layer 1) acts as a platform, so a walking figure cannot
	# drag a rider standing on it (characters still block each other).
	platform_floor_layers = 1
	_apply_team_color()
	_apply_team_shape()
	_build_health_bar()
	# Issue #252: debug-mode visuals — HP number, damage popup, arrow.
	_build_debug_visuals()
	set_controlled(controlled)


## Issue #169: apply color, shape and name customisation after the fact
## (called by GameConfig.apply once the level trimmed the team).
func apply_team_setup() -> void:
	display_name = GameConfig.member_names[mini(
		get_tree().get_nodes_in_group("player_team").find(self),
		GameConfig.member_names.size() - 1)]
	team_color = GameConfig.team_color
	team_shape = GameConfig.team_shape
	_apply_team_color()
	_apply_team_shape()


## Issue #60: tint every ColorRect visual authored in the scene (captured
## before the health bar adds its own ColorRects) with the team color.
func _apply_team_color() -> void:
	for child in get_children():
		var rect := child as ColorRect
		if rect != null and rect.name != "Shield" and rect.name != "HealthBarBackground":
			rect.color = team_color


## Issue #169: non-square body shapes replace the square ColorRect visual
## with a ShapeVisual drawing the picked polygon.
func _apply_team_shape() -> void:
	if team_shape == "square":
		return
	for child in get_children():
		var rect := child as ColorRect
		# Issue #178: the health bar background must stay a bar — converting
		# it drew a second body shape over each figure.
		if rect != null and rect.name != "HealthBarBackground":
			rect.visible = false
			var visual_name := String(rect.name) + "Shape"
			if get_node_or_null(NodePath(visual_name)) != null:
				continue
			var visual: Control = load("res://scripts/ShapeVisual.gd").new()
			visual.name = String(rect.name) + "Shape"
			for anchor in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom"]:
				visual.set(anchor, rect.get(anchor))
			visual.position = rect.position
			visual.size = rect.size
			visual.set_shape(team_shape)
			visual.set_shape_color(team_color)
			add_child(visual)
	# Issue #282: the ShapeVisual body was appended AFTER the Weapon node,
	# so the held weapon/tool drew BEHIND the figure — keep the Weapon the
	# last child; it draws in front of every body visual.
	_keep_weapon_in_front()


## Issue #282: the held weapon/tool must render IN FRONT of the character
## body. All body visuals (scene ColorRect, ShapeVisual) stay BEFORE the
## Weapon node in the child order — tree order decides which CanvasItem
## draws on top among same-z siblings.
func _keep_weapon_in_front() -> void:
	var weapon := get_node_or_null("Weapon")
	if weapon != null:
		move_child(weapon, get_child_count() - 1)


## Issue #33: if no team member ended up controlled (fresh scene), the
## first one takes control.
func _claim_control_if_none() -> void:
	for member in get_tree().get_nodes_in_group("player_team"):
		if member.get("controlled") == true:
			return
	set_controlled(true)


## Issue #33: switch input control to/from this member.
## Issue #63: zoom belongs to the player's VIEW, not to a character — every
## member uses the ONE shared team camera (group "player_camera"): the
## scene-authored one if present, otherwise one created on demand. The
## camera itself follows the controlled member (see ZoomCamera.gd).
func set_controlled(value: bool) -> void:
	controlled = value
	if _camera == null:
		for camera in get_tree().get_nodes_in_group("player_camera"):
			_camera = camera
			break
	if _camera == null:
		_camera = get_node_or_null("Camera") as Camera2D
		if _camera == null:
			_camera = load("res://ZoomCamera.gd").new()
			_camera.name = "Camera"
			add_child(_camera)
		if not _camera.is_in_group("player_camera"):
			_camera.add_to_group("player_camera")
	# Only the member hosting the camera node toggles it with control;
	# the shared camera itself just follows the controlled member.
	if _camera.get_parent() == self:
		_camera.enabled = value
	else:
		# Non-hosting member takes control: make sure the shared camera is on.
		_camera.enabled = _camera.enabled or value


## Issue #6: apply damage and update the health bar.
## Issue #151: health 0 means DEAD — flagged immediately so win checks
## stop counting this figure before its death animation frees the node.
var _dead := false


func take_damage(amount: int, attacker: Node2D = null) -> void:
	if _dead:
		return
	# Issue #170: the energy shield blocks all damage until next turn.
	# Issue #255 rework: the shield blocks ONE attack — blocking consumes
	# it (same rule as Npc.take_damage, no player/NPC difference).
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
	_hit_flash()
	# Issue #252: debug damage number + action-log line.
	DebugInfo.show_damage(self, amount)
	DebugInfo.log("%s takes %d damage (%d/%d)" % [display_name, amount, health, MAX_HEALTH])
	# Issue #335: comics line near the figure — the victim cries out (or
	# calls out an ALLY's betrayal) and a big hit makes the attacker
	# gloat; identical logic in Npc.take_damage.
	CharacterLines.on_damage_taken(self, amount, attacker)
	if health == 0:
		_dead = true
		# Issue #433: REWARD_SPEC §2.3 — the controller that plays this
		# figure takes the once-per-death penalty at the moment of death,
		# whatever killed it.
		BotController.notify_figure_died(self)
		_die()
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


## Issue #252: attach the debug visuals (HP number, damage popup,
## centre-to-top arrow) — a no-op with the debug mode off.
func _build_debug_visuals() -> void:
	DebugInfo.attach(self)
	DebugInfo.update_hp(self, health, MAX_HEALTH)


## Issue #186: player-team characters flash on damage exactly like NPCs
## (Npc.take_damage) — blast visuals must not differ between teams.
func _hit_flash() -> void:
	var visual: Node = null
	for child in get_children():
		var rect := child as ColorRect
		if rect != null and rect.name != "Shield" \
				and rect.name != "HealthBarBackground" and rect.visible:
			visual = rect
			break
		var shape := child as Node
		# Issue #222: the scene's collision shape is named "PlayerShape" —
		# it ends with "Shape" but is a CollisionShape2D, not a ShapeVisual,
		# so it must never take the shape-visual branch (every hit on a
		# player used to throw a script error and skip the flash).
		if shape != null and shape.name.ends_with("Shape") and shape.visible \
				and shape.has_method("set_shape_color"):
			visual = shape
			break
	if visual == null:
		return
	if visual is ColorRect:
		visual.color = Color(1.0, 0.6, 0.7, 1)
		get_tree().create_timer(0.1).timeout.connect(
			func() -> void:
				if is_instance_valid(visual):
					visual.color = team_color)
	else:
		visual.set_shape_color(Color(1.0, 0.6, 0.7, 1))
		get_tree().create_timer(0.1).timeout.connect(
			func() -> void:
				if is_instance_valid(visual):
					visual.set_shape_color(team_color))


## Issue #181: a player-team member that reaches 0 HP must DISAPPEAR like
## an NPC does (Npc._die) — shrink out, then free the node, so the corpse
## never stays on the field and win checks / turn flow see it as gone.
## Issue #409: the shrink-out tween is kept in a field so an episode
## reset (BotController.reset) can cancel a death that is mid-animation.
var death_tween: Tween

func _die() -> void:
	set_physics_process(false)
	# Issue #252: action-log line — the figure left the field.
	DebugInfo.log("%s died" % display_name)
	# Issue #335: if this leaves exactly one teammate alive, the survivor
	# is "left alone in the team" and speaks up.
	CharacterLines.on_member_death(self)
	# Issue #222: the shared camera must survive EVERY dying member — its
	# host may die while someone else is controlled, or when the whole team
	# is wiped at the end of the game. Reparent it to the level and keep it
	# ENABLED: with nobody left controlled it becomes the free spectator
	# camera (issue #126), so the view never freezes after the win and the
	# field stays watchable.
	if _camera != null and is_instance_valid(_camera) \
			and _camera.get_parent() == self:
		_camera.reparent(get_parent())
		_camera.enabled = true
	# Issue #187: a dying CONTROLLED member must not keep control — the
	# camera would follow the shrinking corpse and, until the node is
	# freed, switch/input logic would still see it as the active character.
	# Hand control and the view to the first living teammate immediately.
	if controlled:
		controlled = false
		var successor: Node = null
		for member in get_tree().get_nodes_in_group("player_team"):
			if is_instance_valid(member) and member != self \
					and member.has_method("set_controlled") \
					and (member.get("health") is int) and member.get("health") > 0:
				successor = member
				break
		if successor != null:
				successor.set_controlled(true)
	death_tween = create_tween()
	death_tween.tween_property(self, "scale", Vector2.ZERO, 0.25)
	death_tween.tween_callback(queue_free)


func heal(amount: int) -> void:
	# Issue #151: dead characters cannot be healed back.
	if _dead:
		return
	health = clampi(health + amount, 0, MAX_HEALTH)
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


## Issue #170: toggle the energy shield (and its visual bubble).
func set_shielded(value: bool) -> void:
	shielded = value
	if shielded and _shield_rect == null:
		_shield_rect = ColorRect.new()
		_shield_rect.name = "Shield"
		_shield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shield_rect.offset_left = -BAR_WIDTH / 2.0 - 4.0
		_shield_rect.offset_top = -BAR_HEIGHT - 40.0
		_shield_rect.offset_right = BAR_WIDTH / 2.0 + 4.0
		_shield_rect.offset_bottom = BAR_HEIGHT + 16.0
		_shield_rect.color = Color(0.25, 0.4, 0.95, 0.35)
		add_child(_shield_rect)
	if _shield_rect != null:
		_shield_rect.visible = shielded


# Small bar above the player, built in code like the other visuals.
# Issue #33: a name label sits above the bar.
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
	# Issue #178: named so the team shape/color passes skip it.
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
	_bar_fill.color = Color(0.25, 0.75, 0.3, 1)
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
	# Turn more red as health drops.
	_bar_fill.color = Color(0.75 - 0.5 * ratio, 0.25 + 0.5 * ratio, 0.3, 1)


func _physics_process(delta: float) -> void:
	# Issue #293: the gravity field is no longer configured separately
	# from the terrain — the level's indestructible grounds are the ONLY
	# gravity source (LevelTerrain): gravity always pulls toward the
	# nearest ground surface, exactly what a player sees. Levels without
	# any gravity source fall straight down. The old central-line/
	# gravity_dir authored overrides are gone (the #277 center-line
	# contract was the last consumer).
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

	if not is_on_floor():
		velocity += grav * GRAVITY * delta

	# Issue #244: while the handover waits for effects (after a shot or
	# when the turn timer ran out) the character is BLOCKED — no moving,
	# jumping or aiming until the next turn begins.
	if controlled and TurnController.is_player_team(TurnController.active_team) \
				and not TurnController.is_input_frozen():
		if Input.is_action_just_pressed("jump") and is_on_floor():
			# Issue #202: JUMP_VELOCITY is negative, so grav * JUMP_VELOCITY
			# points AWAY from the floor (up for grav = DOWN). The old
			# inverted form pushed the figure INTO the floor and jump never
			# lifted the character.
			velocity = grav * JUMP_VELOCITY

		var direction := Input.get_axis("move_left", "move_right")
		# Issue #104: any move or aim action locks character switching for
		# the rest of the turn (N/P) — the player is committed to this member.
		var view_axis := Input.get_axis("view_down", "view_up")
		if direction != 0.0 or view_axis != 0.0 \
				or (Input.is_action_just_pressed("jump") and is_on_floor()):
			TurnController.notify_member_action()
		# Issue #359: charging the railgun slows the wielder to half speed
		# (Weapon.move_speed_factor) while F is held and the charge builds.
		var weapon := get_node_or_null("Weapon")
		var speed := SPEED
		if weapon != null and weapon.has_method("move_speed_factor"):
			speed *= float(weapon.move_speed_factor())
		if direction != 0.0:
			# Issue #250 rework: walk along the SURFACE — the input maps onto
			# the current gravity frame's tangent, not the world x axis. With
			# world-x movement on the circular arena the figure launched off
			# the curved slope and flew up and down ballistically; on flat
			# levels the tangent IS the x axis, so nothing changes there. The
			# tangent orientation follows the previous frame by continuity (see
			# _aim_tangent), so "right" stays right under flipped gravity AND
			# never flips 180° mid-walk around a disc rim.
			velocity = _aim_tangent * direction * speed \
					+ grav * velocity.dot(grav)
		else:
			velocity = grav * velocity.dot(grav)
		# Issue #67: raise/lower the view with W/S / Arrow Up/Down.
		view_angle = clampf(view_angle + view_axis * VIEW_SPEED * delta, -VIEW_MAX, VIEW_MAX)
		# Issue #359: charging the railgun SHAKES the sight — a small random
		# wobble piles onto the view angle every tick while the charge builds
		# (Weapon.sight_shake), so a full charge is harder to aim precisely.
		if weapon != null and weapon.has_method("sight_shake"):
			var shake := float(weapon.sight_shake())
			if shake != 0.0:
				view_angle = clampf(view_angle + shake, -VIEW_MAX, VIEW_MAX)
	else:
		# Issue #316: a DRILLING wielder is the one frozen-input exception —
		# the aim keys (W/S) still steer the running jackhammer (the drill
		# direction follows the live aim, see Weapon._tick_jackhammer), and
		# the drill's velocity must survive the clamp below: Weapon owns it
		# until the drill ends. There is no cancel — the drill runs its full
		# aimed time or stalls against indestructible ground.
		var drill := get_node_or_null("Weapon")
		if controlled and TurnController.is_player_team(TurnController.active_team) \
					and drill != null and drill.has_method("is_drilling") \
					and drill.is_drilling():
			var steer := Input.get_axis("view_down", "view_up")
			if steer != 0.0:
				view_angle = clampf(view_angle + steer * VIEW_SPEED * delta,
						-VIEW_MAX, VIEW_MAX)
		else:
			# Issue #40/#58: uncontrolled team member just stays put (no glide
			# along the surface — only the component along gravity survives,
			# which on flat levels is exactly the old velocity.y).
			velocity = grav * velocity.dot(grav)

	move_and_slide()

