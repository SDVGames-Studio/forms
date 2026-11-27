class_name Character
extends CharacterBody2D
## Unified figure body — issue #611, slice 1 of the controller-pattern
## refactor. Everything a figure IS lives here: physics, health, the
## health bar, the shield, damage/death flow, the gravity frame and the
## team-look plumbing shared by EVERY figure, player's or computer's.
##
## The base is a PURE BODY: it never reads Input and carries no AI —
## the "brains" (player input in Player.gd, the scripted AI in Npc.gd,
## the RL policy via BotController.gd) drive it through the public
## controller API at the bottom of this file:
##
##   move(axis)  — walk the gravity frame's tangent (0 = stand)
##   aim(delta)  — slew the view angle (clamped to ±VIEW_MAX)
##   jump()      — leave the floor along the current gravity frame
##   fire(power) — trigger the carried Weapon
##
## Player.gd and Npc.gd extend this class and override `_control(delta)`
## for their per-tick decisions; the shared tick (gravity frame, fall
## acceleration, move_and_slide) stays here so no physics code is ever
## duplicated between them again.

const Stats := preload("res://scripts/CharacterStats.gd")
const BotController := preload("res://scripts/BotController.gd")

const SPEED := Stats.SPEED
const JUMP_VELOCITY := Stats.JUMP_VELOCITY
const GRAVITY := Stats.GRAVITY
const MAX_HEALTH := Stats.MAX_HEALTH
const BAR_WIDTH := Stats.BAR_WIDTH
const BAR_HEIGHT := Stats.BAR_HEIGHT
const VIEW_SPEED := Stats.VIEW_SPEED
const VIEW_MAX := Stats.VIEW_MAX
## Weapon slot order (Weapon.gd's fire dispatch): 5 = jackhammer,
## 10 = entrenching shovel (#656).
const WEAPON_SLOT_JACKHAMMER := 5
const WEAPON_SLOT_SHOVEL := 10

## Issue #161/#611: health changes are observable — the HUD (and the
## tests) listen for the updated health/max pair.
signal health_changed(health: int, max_health: int)

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
## it. Every figure shields the same way, player's or computer's.
var shielded := false
var _shield_rect: ColorRect

## Issue #67: character's view (aim) angle in radians, 0 = horizontal.
## Positive raises the view, negative lowers it. Controlled with the
## view_up/view_down actions (W/S and Arrow Up/Down) on the player side,
## slewed by the AI on the computer side, set by the policy on the RL side.
var view_angle := 0.0

## Issue #277: the gravity unit vector the last physics frame used — the
## frame the aim/view lives in (see aim_dir). DOWN until the first tick
## (the legacy default).
var _aim_grav := Vector2.DOWN

## Issue #277 rework / #518 rework: the walking/aiming tangent of the
## CURRENT gravity frame — the CHARACTER'S LOCAL +X. The body children
## are rotated to the gravity frame by FigurePose.align_to_gravity (angle
## grav.angle() - PI/2) and the character camera (#289) renders exactly
## that local frame as the screen frame — rotating Vector2.RIGHT by that
## angle gives precisely the raw perpendicular (grav.y, -grav.x), so THIS
## tangent is the character's own right hand. The owner directive for the
## #518 rework: "each character has a local coordinate system, which used
## by the character's cam, so use this local coordinate system to choose
## where should a/d keys lead" — pressing D walks the character's local
## right, which is ALWAYS screen-right in the character camera, flat
## ground, a floor's underside or a disc rim alike. The tangent is a pure
## function of gravity (no sign state, no hysteresis): it rotates smoothly
## with the gravity around a disc rim by construction.
var _aim_tangent := Vector2.RIGHT

var _bar_fill: ColorRect

## Issue #558: procedural idle/walk/jump animation driver — a purely
## visual Node that bends the body visual from this figure's movement
## state (see CharacterAnimator.gd). Never touches physics or input.
var _animator: CharacterAnimator = null

## Issue #700: the walk axis the brain last commanded along the gravity
## frame's tangent (move()'s clamped argument; 0.0 = planted). Weapon
## faces the figure by this COMMAND, not by the physical velocity —
## only the player/computer can turn a figure to the opposite side.
var _walk_command := 0.0

## Issue #151: health 0 means DEAD — flagged immediately so win checks
## stop counting this figure before its death animation frees the node.
var _dead := false

## Issue #409: the shrink-out death tween is kept in a field so an
## episode reset (BotController.reset) can cancel a death that is
## mid-animation.
var death_tween: Tween


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


## Issue #700: the walk axis the brain last commanded through move()
## (0.0 = planted). The figure's facing (Weapon._facing) follows THIS,
## never the raw velocity — on curved ground move_and_slide's slide
## after a key release leaves a one-tick BACKWARDS tangential velocity
## and the figure turned on its own. Ground shape never flips a figure;
## only a player/computer walk order may.
func walk_command() -> float:
	return _walk_command


## Issue #518 rework: refresh the gravity frame right after a DISCRETE
## position jump (teleport) instead of waiting for the next physics tick,
## so same-frame consumers (aim, sight) see the destination's frame. The
## tangent is the character's LOCAL +x (see _aim_tangent): with the owner's
## #518 directive the teleport destination inherits the same local-frame
## rule every other position uses — under upward gravity the local +x is
## world (-1, 0), which the rotated character camera renders screen-RIGHT
## (the previous world-x "screen-right" anchor was exactly the bug).
func reanchor_gravity_frame() -> void:
	var grav := Vector2.DOWN
	if LevelTerrain.has_sources(self):
		grav = LevelTerrain.gravity_vector(self)
	_aim_grav = grav
	_aim_tangent = Vector2(grav.y, -grav.x)
	up_direction = -grav
	FigurePose.align_to_gravity(self, grav)


## Issue #641: the walkable-surface rule from Stats — a surface whose
## angle with the gravity vector is under 135° counts as FLOOR, not wall,
## so a figure walks up and down steep inclines (and jumps off them)
## instead of grinding to a halt against the engine's default 45° limit.
## The snap length keeps it glued to the surface while descending.
func _enter_tree() -> void:
	floor_max_angle = Stats.FLOOR_MAX_ANGLE
	floor_snap_length = Stats.FLOOR_SNAP_LENGTH


## Issue #611: the shared figure tick — the gravity frame refresh, the
## fall acceleration and the slide live HERE, once, for every figure.
## What the figure DOES with them comes from the controller side via
## `_control(delta)` (player input, scripted AI, RL policy). Dead figures
## stop moving immediately (issue #151).
func _physics_process(delta: float) -> void:
	if _dead:
		return
	_refresh_gravity_frame()
	if not is_on_floor():
		velocity += _aim_grav * GRAVITY * delta
	_control(delta)
	move_and_slide()


## Issue #293: the gravity field is no longer configured separately
## from the terrain — the level's indestructible grounds are the ONLY
## gravity source (LevelTerrain): gravity always pulls toward the
## nearest ground surface, exactly what a player sees. Levels without
## any gravity source fall straight down.
## Issue #270: rotate the BODY visual/collision so the figure's bottom
## faces the ground under any gravity direction (radial arenas included);
## HUD, weapon and camera keep the world frame (FigurePose for details).
## Issue #311: the HUD text (name, health bar, debug HP) must live in the
## coordinate system the view CURRENTLY shows — with the character camera
## (#289) the view itself rotates, so world-aligned text would render
## tilted/upside-down on screen. No-op for the world-aligned static view.
func _refresh_gravity_frame() -> void:
	var grav := Vector2.DOWN
	if LevelTerrain.has_sources(self):
		grav = LevelTerrain.gravity_vector(self)
	up_direction = -grav
	_aim_grav = grav
	_aim_tangent = Vector2(grav.y, -grav.x)
	FigurePose.align_to_gravity(self, grav)
	HudPose.align_to_view(self)


## Issue #611: the per-tick "brain" hook — the subclasses' decisions.
## The base never reads input and never decides: by the time this runs
## the gravity frame is fresh and gravity is applied; move_and_slide()
## follows after it returns.
func _control(_delta: float) -> void:
	pass


## Issue #60: tint every ColorRect visual authored in the scene (captured
## before the health bar adds its own ColorRects) with the team color.
func _apply_team_color() -> void:
	for child in get_children():
		var rect := child as ColorRect
		if rect != null and rect.name != "Shield" and rect.name != "HealthBarBackground":
			rect.color = team_color


## Issue #282: the held weapon/tool must render IN FRONT of the character
## body. All body visuals (scene ColorRect, the modular character) stay BEFORE the
## Weapon node in the child order — tree order decides which CanvasItem
## draws on top among same-z siblings.
func _keep_weapon_in_front() -> void:
	var weapon := get_node_or_null("Weapon")
	if weapon != null:
		move_child(weapon, get_child_count() - 1)


# Small bar above the figure, built in code like the other visuals.
# Issue #33: a name label sits above the bar.
# Issue #598: the HP renders in front of everything except the character's
# line (Stats.LINE_Z) — overlapping bodies, terrain and projectiles (rings
# at z 50) can no longer cover the bar.
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
	background.z_index = Stats.HP_Z
	# Issue #690 rework 4: a figure-attached overlay never intercepts
	# the mouse (the Shield bubble's convention) — a STOP bar would eat
	# clicks in the strip above a figure that the Talk pick's tolerant
	# click ring covers.
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.offset_left = -BAR_WIDTH / 2.0
	background.offset_top = -44.0
	background.offset_right = BAR_WIDTH / 2.0
	background.offset_bottom = -44.0 + BAR_HEIGHT
	background.color = Color(0.1, 0.1, 0.12, 0.85)
	add_child(background)

	_bar_fill = ColorRect.new()
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Issue #726: full-rect anchors make the fill's offsets measure from
	# the background's own edges — the 1 px inset (offsets 1, 1, -1, -1)
	# only works with them. Without anchor_right/anchor_bottom = 1 the
	# fill's height collapsed to zero (offset_bottom -1 landed ABOVE its
	# top edge), the fill turned invisible and the bar read as an empty
	# dark line with no HP in it.
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_right = 1.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_left = 1.0
	_bar_fill.offset_top = 1.0
	_bar_fill.offset_right = -1.0
	_bar_fill.offset_bottom = -1.0
	_bar_fill.color = _bar_fill_color(1.0)
	background.add_child(_bar_fill)
	_update_bar()


func _update_bar() -> void:
	if _bar_fill == null:
		return
	# Issue #252: keep the debug HP number near the figure in sync.
	DebugInfo.update_hp(self, health, MAX_HEALTH)
	var inner_width := BAR_WIDTH - 2.0
	var ratio := float(health) / float(MAX_HEALTH)
	# Issue #726: the remaining HP fills the middle of the bar. Full
	# health paints the whole inner width; damage shrinks the fill
	# symmetrically from both edges toward the centre (never anchored
	# to one side). The symmetric offsets keep the fill centred in the
	# background whatever the ratio.
	var edge: float = (BAR_WIDTH - inner_width * ratio) / 2.0
	_bar_fill.offset_left = edge
	_bar_fill.offset_right = -edge
	_bar_fill.color = _bar_fill_color(ratio)


## Issue #726: the HP fill is red — full health paints the full bar
## red, and damage shrinks it from the edges to the centre. (Supersedes
## the issue #6 green-at-full-health look: a green bar read as "no HP".)
## Computer figures keep their team color (Npc override, issue #60).
func _bar_fill_color(_ratio: float) -> Color:
	return Color(0.85, 0.15, 0.15, 1)


## Issue #521: rename the figure after the level was staged — the name
## label above the health bar was already built from the old name.
func set_display_name(value: String) -> void:
	display_name = value
	var label := get_node_or_null("NameLabel") as Label
	if label != null:
		label.text = value


## Issue #170: toggle the energy shield (and its visual bubble).
## The bubble's box is per-side heritage (Player vs Npc geometry) —
## `_shield_offsets()` keeps both looks without duplicating the toggle.
func set_shielded(value: bool) -> void:
	shielded = value
	if shielded and _shield_rect == null:
		_shield_rect = ColorRect.new()
		_shield_rect.name = "Shield"
		_shield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := _shield_offsets()
		_shield_rect.offset_left = box.x
		_shield_rect.offset_top = box.y
		_shield_rect.offset_right = box.z
		_shield_rect.offset_bottom = box.w
		_shield_rect.color = Color(0.25, 0.4, 0.95, 0.35)
		add_child(_shield_rect)
	if _shield_rect != null:
		_shield_rect.visible = shielded


## Issue #611: the Shield bubble's box (left, top, right, bottom) — the
## player-side geometry by default; Npc keeps its own heritage box.
func _shield_offsets() -> Vector4:
	return Vector4(-BAR_WIDTH / 2.0 - 4.0, -BAR_HEIGHT - 40.0,
			BAR_WIDTH / 2.0 + 4.0, BAR_HEIGHT + 16.0)


## Issue #364: first aid kits heal figures exactly like always — same
## clamp at MAX_HEALTH; dead figures stay dead (issue #151).
func heal(amount: int) -> void:
	if _dead:
		return
	health = clampi(health + amount, 0, MAX_HEALTH)
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


## Issue #6: apply damage and update the health bar.
## Issue #151: health 0 means DEAD — flagged immediately so win checks
## stop counting this figure before its death animation frees the node.
## Issue #611: ONE damage flow for every figure — the player/NPC copies
## were line-for-line identical apart from ordering that never showed.
func take_damage(amount: int, attacker: Node2D = null) -> void:
	if _dead:
		return
	# Issue #170: the energy shield blocks all damage until next turn.
	# Issue #255 rework: the shield blocks ONE attack — blocking consumes
	# it (no player/NPC difference).
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
	# Issue #559: the hit shows on the FACE too — a short SURPRISED
	# flinch (purely visual; the animator restores the resting face).
	if _animator != null:
		_animator.flash_expression("SURPRISED", 0.8)
	# Issue #252: debug damage number + action-log line.
	DebugInfo.show_damage(self, amount)
	DebugInfo.log("%s takes %d damage (%d/%d)" % [display_name, amount, health, MAX_HEALTH])
	# Issue #335: comics line near the figure — the victim cries out (or
	# calls out an ALLY's betrayal) and a big hit makes the attacker
	# gloat.
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


## Issue #186: figures flash on damage exactly alike — blast visuals
## must not differ between teams. Finds whichever child currently
## depicts the body (the authored ColorRect or the modular shape visual).
## Issue #222: the scene's collision shape ends with "Shape" but is a
## CollisionShape2D, not a ShapeVisual — it must never take the
## shape-visual branch.
func _hit_flash() -> void:
	var visual: Node = null
	for child in get_children():
		var rect := child as ColorRect
		if rect != null and rect.name != "Shield" \
				and rect.name != "HealthBarBackground" and rect.visible:
			visual = rect
			break
		var shape := child as Node
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


## Issue #181: a figure that reaches 0 HP DISAPPEARS — shrink out, then
## free the node, so the corpse never stays on the field and win checks /
## turn flow see it as gone. Camera rescue and control handover are the
## subclasses' hooks (`_rescue_camera`, `_on_dying`).
func _die() -> void:
	set_physics_process(false)
	# Issue #252: action-log line — the figure left the field.
	DebugInfo.log("%s died" % display_name)
	# Issue #335: if this leaves exactly one teammate alive, the survivor
	# is "left alone in the team" and speaks up.
	CharacterLines.on_member_death(self)
	_rescue_camera()
	_on_dying()
	death_tween = create_tween()
	death_tween.tween_property(self, "scale", Vector2.ZERO, 0.25)
	death_tween.tween_callback(queue_free)


## Issue #222/#280: the shared camera must survive EVERY dying member —
## its host may die while someone else is controlled, or when the whole
## team is wiped at the end of the game. Reparent it to the level and
## keep it ENABLED: with nobody left controlled it becomes the free
## spectator camera (issue #126), so the view never freezes after the
## win and the field stays watchable.
func _rescue_camera() -> void:
	for child in get_children():
		if child is Camera2D and child.is_in_group("player_camera"):
			child.reparent(get_parent())
			child.enabled = true
			break


## Issue #611: per-side death hook — the player side hands control over
## (Player.gd); the computer side needs nothing extra.
func _on_dying() -> void:
	pass


## ------------------------------------------------------------------
## Issue #611: the CONTROLLER API — the public surface every "brain"
## (player input, scripted AI, RL policy) drives the figure through.
## Pure commands, no state inspection needed beyond the fields above.
## ------------------------------------------------------------------

## Walk along the gravity frame's tangent (the character's LOCAL +x,
## issue #518 rework) at the figure's speed, keeping the fall/jump
## component along gravity. `horizontal_axis` is clamped to [-1, 1];
## 0.0 plants the figure (only the gravity component of the velocity
## survives — the exact old "stand" behavior).
func move(horizontal_axis: float) -> void:
	var axis := clampf(horizontal_axis, -1.0, 1.0)
	# Issue #700: record the commanded walk axis — the facing source
	# (see walk_command).
	_walk_command = axis
	velocity = _aim_tangent * axis * _move_speed() \
			+ _aim_grav * velocity.dot(_aim_grav)


## The walking speed — the plain figure speed by default; the player
## side slows to the weapon's charge factor through this hook
## (issue #359: charging the railgun halves the wielder's speed).
func _move_speed() -> float:
	return float(SPEED)


## Slew the view (aim) angle by `delta_angle` radians — positive raises
## the muzzle away from the floor, negative lowers it — clamped to
## ±VIEW_MAX. The weapon faces aim_dir(), so the whole arsenal follows.
## Issue #682: the jackhammer and the entrenching shovel are the
## exceptions — they must be able to point STRAIGHT DOWN so the
## wielder can dig a shaft UNDER itself (entrench, Worms-style).
## While the jackhammer is the selected weapon — or a drill is already
## running and being steered by the aim keys — the clamp widens to the
## full vertical; issue #682 rework: the entrenching shovel is a
## DISTINCT tool with the same need, so it gets the widened clamp too
## (its dig bore opens 12 px ahead along the aim, see Weapon's
## _shovel_dig). Every other weapon keeps the ±VIEW_MAX limit.
func aim(delta_angle: float) -> void:
	view_angle = clampf(view_angle + delta_angle, -_view_max(), _view_max())


## Issue #682: the live view-angle limit — PI/2 (straight down/up along
## the gravity frame) with the jackhammer selected or drilling, the
## entrenching shovel selected (#682 rework — a distinct tool that
## digs the same under-the-feet shaft), the arsenal-wide
## Stats.VIEW_MAX otherwise.
func _view_max() -> float:
	var weapon := get_node_or_null("Weapon")
	if weapon != null and weapon.has_method("is_drilling"):
		var slot: int = weapon.get("selected_weapon")
		if slot == WEAPON_SLOT_JACKHAMMER or slot == WEAPON_SLOT_SHOVEL \
				or weapon.is_drilling():
			return PI / 2.0
	return VIEW_MAX


## Jump away from the floor along the CURRENT gravity frame
## (JUMP_VELOCITY is negative, so grav * JUMP_VELOCITY points AWAY from
## the floor — issue #202). Returns true when the jump fired; floor
## contact is required.
func jump() -> bool:
	if not is_on_floor():
		return false
	velocity = _aim_grav * JUMP_VELOCITY
	# Issue #558: squash-before-takeoff impulse — purely visual.
	if _animator != null:
		_animator.notify_jump()
	return true


## Trigger the carried Weapon at `power` (0..1 charge). Returns false
## when the figure carries no Weapon node. This is the RAW trigger the
## player's charge release and npc_fire() wrap — quota/budget gating
## stays with the caller (the brain).
func fire(power := 1.0) -> bool:
	var weapon := get_node_or_null("Weapon")
	if weapon == null or not weapon.has_method("_fire"):
		return false
	weapon._fire(power)
	return true
