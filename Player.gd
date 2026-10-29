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
		if rect != null:
			rect.color = team_color


## Issue #169: non-square body shapes replace the square ColorRect visual
## with a ShapeVisual drawing the picked polygon.
func _apply_team_shape() -> void:
	if team_shape == "square":
		return
	for child in get_children():
		var rect := child as ColorRect
		if rect != null:
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
	health = clampi(health - amount, 0, MAX_HEALTH)
	if health == 0:
		_dead = true
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


func heal(amount: int) -> void:
	# Issue #151: dead characters cannot be healed back.
	if _dead:
		return
	health = clampi(health + amount, 0, MAX_HEALTH)
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


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
	var dir := 1.0
	if center_line_y > 0.0:
		dir = 1.0 if global_position.y < center_line_y else -1.0
		up_direction = Vector2.UP if dir > 0.0 else Vector2.DOWN

	if not is_on_floor():
		velocity.y += GRAVITY * dir * delta

	if controlled and TurnController.active_team == TurnController.TEAM_PLAYER:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY * dir

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

