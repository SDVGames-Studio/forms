extends CharacterBody2D
## Playable figure for the simple level (issue #1).
##
## Left/right movement plus jump, driven by the move_left/move_right/jump
## actions (WASD and arrow keys, Space); gravity is applied while airborne.
##
## Issue #33: the player controls their WHOLE team — every team member uses
## this script. Exactly one member is `controlled` (driven by input); the
## rest just stay in place (issue #40). TeamController (autoload) switches
## the controlled member with N (next) / P (previous). All members share the
## same shape and color and show a name above the health bar.

## Issue #108: all characteristics come from the shared CharacterStats —
## enemy figures are the SAME class of character as player figures.
const Stats := preload("res://scripts/CharacterStats.gd")
const SPEED := Stats.SPEED
const JUMP_VELOCITY := Stats.JUMP_VELOCITY
const GRAVITY := Stats.GRAVITY

## Issue #48 rework: y of the level's central line. When > 0, gravity always
## pulls toward the line — normal above it, reversed below it — so a figure
## walking off an edge falls, but after crossing the middle of the level the
## fall reverses and the figure lands back on the other side of the line.
@export var center_line_y := 0.0

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
var shielded := false
var _shield_rect: ColorRect

## Issue #67: character's view (aim) angle in radians, 0 = horizontal.
## Positive raises the view, negative lowers it. Controlled with the
## view_up/view_down actions (W/S and Arrow Up/Down).
const VIEW_SPEED := Stats.VIEW_SPEED
const VIEW_MAX := Stats.VIEW_MAX
var view_angle := 0.0

## Issue #67: direction the character looks/aims in — facing direction
## raised/lowered by view_angle, oriented against the current gravity side.
func aim_dir(facing: float, dir: float) -> Vector2:
	return Vector2(cos(view_angle) * facing, -sin(view_angle) * dir)
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


func take_damage(amount: int) -> void:
	if _dead:
		return
	# Issue #170: the energy shield blocks all damage until next turn.
	if shielded:
		return
	health = clampi(health - amount, 0, MAX_HEALTH)
	_hit_flash()
	if health == 0:
		_dead = true
		_die()
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


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
		if shape != null and shape.name.ends_with("Shape") and shape.visible:
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
func _die() -> void:
	set_physics_process(false)
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
		# Issue #187: if this body hosts the shared team camera, move it out
		# of the dying node so the player's view survives the corpse.
		if _camera != null and _camera.get_parent() == self:
			_camera.reparent(get_parent())
			_camera.enabled = successor != null
		if successor != null:
			successor.set_controlled(true)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.25)
	tween.tween_callback(queue_free)


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
	var inner_width := BAR_WIDTH - 2.0
	var ratio := float(health) / float(MAX_HEALTH)
	_bar_fill.offset_right = 1.0 + inner_width * ratio
	# Turn more red as health drops.
	_bar_fill.color = Color(0.75 - 0.5 * ratio, 0.25 + 0.5 * ratio, 0.3, 1)


func _physics_process(delta: float) -> void:
	# Issue #48 rework: pick the gravity side from the position relative to
	# the central line and orient the floor accordingly (upside-down below).
	# Issue #190: gravity comes from the nearest indestructible terrain
	# surface when the level authors gravity sources; otherwise the legacy
	# central-line rule (global down) applies. Destructible ground never
	# bends gravity.
	var grav := Vector2.DOWN
	if LevelTerrain.has_sources(self):
		grav = LevelTerrain.gravity_vector(self)
	elif center_line_y > 0.0:
		grav = Vector2.DOWN \
				if global_position.y < center_line_y else Vector2.UP
	up_direction = -grav

	if not is_on_floor():
		velocity += grav * GRAVITY * delta

	if controlled and TurnController.is_player_team(TurnController.active_team):
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
		if direction != 0.0:
			velocity.x = direction * SPEED
		else:
			velocity.x = 0.0
		# Issue #67: raise/lower the view with W/S / Arrow Up/Down.
		view_angle = clampf(view_angle + view_axis * VIEW_SPEED * delta, -VIEW_MAX, VIEW_MAX)
	else:
		# Issue #40/#58: uncontrolled team member just stays put (no glide).
		velocity.x = 0.0

	move_and_slide()

