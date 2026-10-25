extends CanvasLayer
## Issue #69: on-screen touch controls for the mobile version.
## Left side: move left / move right. Right side: jump / fire.
## The buttons drive the same input actions as the keyboard
## (move_left, move_right, jump, shoot), so Player.gd / Weapon.gd need
## no changes. Visible only on touchscreen devices and only during
## gameplay (hidden on the main menu and levels menu).

var _buttons := {}


func _ready() -> void:
	layer = 90
	if not DisplayServer.is_touchscreen_available():
		set_process(false)
		return
	_add_button("◀", false, 0, "move_left")
	_add_button("▶", false, 0, "move_right")
	_add_button("JUMP", true, 1, "jump")
	_add_button("FIRE", true, 0, "shoot")


func _add_button(label: String, right_side: bool, row: int, action: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(112.0, 112.0)
	button.add_theme_font_size_override("font_size", 40)
	button.modulate = Color(1.0, 1.0, 1.0, 0.55)
	# Anchor to the bottom-left or bottom-right corner of the screen.
	button.set_anchors_preset(
		Control.PRESET_BOTTOM_RIGHT if right_side else Control.PRESET_BOTTOM_LEFT)
	button.grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN if right_side else Control.GROW_DIRECTION_END)
	if right_side:
		button.offset_left = -136.0 - 24.0
		button.offset_right = -24.0
	else:
		button.offset_left = 24.0
		button.offset_right = 136.0
	# Stack rows upward from the bottom edge; row 0 is nearest the edge.
	button.offset_top = -124.0 - 124.0 * row
	button.offset_bottom = -12.0 - 124.0 * row
	button.pressed.connect(_on_pressed.bind(action))
	button.button_down.connect(_on_button_down.bind(action))
	button.button_up.connect(_on_button_up.bind(action))
	add_child(button)
	_buttons[action] = button


func _on_button_down(action: String) -> void:
	Input.action_press(action)


func _on_button_up(action: String) -> void:
	Input.action_release(action)


func _on_pressed(action: String) -> void:
	# Release again in case press/release events were missed.
	Input.action_release(action)


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var in_game := scene != null and String(scene.name).begins_with("Level")
	visible = in_game
	if not in_game:
		for action in _buttons:
			Input.action_release(action)
