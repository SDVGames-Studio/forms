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

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const GRAVITY := 1200.0

## Issue #48 rework: y of the level's central line. When > 0, gravity always
## pulls toward the line — normal above it, reversed below it — so a figure
## walking off an edge falls, but after crossing the middle of the level the
## fall reverses and the figure lands back on the other side of the line.
@export var center_line_y := 0.0

## Issue #40: non-controlled team members just stay where they are.

signal health_changed(health: int, max_health: int)

const MAX_HEALTH := 100
const BAR_WIDTH := 64.0
const BAR_HEIGHT := 8.0

## Issue #33: name shown above the health bar.
@export var display_name := "Player"

## Issue #60: every member of a team wears the same team color — all
## scene-authored body visuals are tinted with it in _ready.
@export var team_color := Color(1, 0.84, 0.2, 1)

var health: int = MAX_HEALTH
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
	# walking into another figure steps up on top of it (see _physics_process).
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	_apply_team_color()
	_build_health_bar()
	set_controlled(controlled)


## Issue #60: tint every ColorRect visual authored in the scene (captured
## before the health bar adds its own ColorRects) with the team color.
func _apply_team_color() -> void:
	for child in get_children():
		var rect := child as ColorRect
		if rect != null:
			rect.color = team_color


## Issue #33: if no team member ended up controlled (fresh scene), the
## first one takes control.
func _claim_control_if_none() -> void:
	for member in get_tree().get_nodes_in_group("player_team"):
		if member.get("controlled") == true:
			return
	set_controlled(true)


## Issue #33: switch input control to/from this member.
func set_controlled(value: bool) -> void:
	controlled = value
	if _camera == null:
		_camera = get_node_or_null("Camera") as Camera2D
		if _camera == null:
			_camera = Camera2D.new()
			_camera.position_smoothing_enabled = true
			_camera.position_smoothing_speed = 8.0
			add_child(_camera)
	_camera.enabled = value


## Issue #6: apply damage and update the health bar.
func take_damage(amount: int) -> void:
	health = clampi(health - amount, 0, MAX_HEALTH)
	health_changed.emit(health, MAX_HEALTH)
	_update_bar()


func heal(amount: int) -> void:
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

	if controlled:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY * dir

		var direction := Input.get_axis("move_left", "move_right")
		if direction != 0.0:
			velocity.x = direction * SPEED
		else:
			velocity.x = 0.0
	else:
		# Issue #40/#58: uncontrolled team member just stays put (no glide).
		velocity.x = 0.0

	move_and_slide()
	_climb_on_characters(dir)


## Issue #39 rework: when walking into another character, climb on top of it
## instead of being blocked — figures can step onto each other's heads.
func _climb_on_characters(dir: float) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider() as CharacterBody2D
		if other == null or other == self:
			continue
		if not (other.is_in_group("player_team") or other.is_in_group("enemy_team")):
			continue
		# Only a frontal hit (normal pointing back at us) while grounded
		# and actually moving toward the other figure.
		if absf(col.get_normal().x) < 0.7 or not is_on_floor():
			continue
		if absf(velocity.x) > 1.0 and signf(col.get_normal().x) != -signf(velocity.x):
			continue
		# Both figures are 64 px circles — stack the centers 64 px apart,
		# offset along the current gravity direction (supports level 3).
		global_position = other.global_position - Vector2(0.0, 64.0) * dir
		velocity.y = 0.0
		return
