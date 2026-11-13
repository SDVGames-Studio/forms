extends CanvasLayer
## Issue #69/#78: on-screen touch controls for the mobile version.
## Issue #512: the same overlay is now enabled on the GitHub Pages web
## build when the browser reports a touchscreen — several mobile
## browsers expose it only through navigator.maxTouchPoints, which the
## engine's own probe ('ontouchstart' in window) misses. On a PC browser
## without touch nothing changes: the overlay stays hidden.
## Left side: virtual movement stick (horizontal axis drives move_left /
## move_right). Right side: jump / fire buttons. A menu button sits in the
## top-right corner near the inventory button (issue #78).
## The stick and buttons drive the same input actions as the keyboard
## (move_left, move_right, jump, shoot), so Player.gd / Weapon.gd need no
## changes. Visible only on touchscreen devices and only inside level
## scenes (nodes in the "level" group — issue #78 scene restructure).

const STICK_RADIUS := 130.0
const DEAD_ZONE := 0.25

var _buttons := {}
var _stick_base: Control
var _stick_knob: Control
var _stick_touch_index := -1
var _stick_center := Vector2.ZERO


func _ready() -> void:
	layer = 90
	if not _touchscreen_available():
		set_process(false)
		return
	_build_ui()


## Issue #512: enable gate. The engine check covers native mobile (the
## Android app) and most mobile browsers; the web fallback below catches
## the rest. A non-touch desktop — the PC browser on GitHub Pages — fails
## every probe, so the overlay stays hidden there exactly as before.
func _touchscreen_available() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if Input.is_emulating_touch_from_mouse():
		return true
	return _web_touch_fallback()


## navigator.maxTouchPoints probe, web export only. On the web the
## engine checks just 'ontouchstart' in window, which not every mobile
## browser exposes even with a real touchscreen; maxTouchPoints is the
## standard signal and stays 0 on ordinary desktop browsers.
func _web_touch_fallback() -> bool:
	if not OS.has_feature("web"):
		return false
	var touch_points = JavaScriptBridge.eval(
				"(navigator.maxTouchPoints || 0) > 0")
	return touch_points == true or str(touch_points) == "true"


## Builds the on-screen set: stick, JUMP, FIRE and the MENU button —
## the same controls the Android app uses (issue #512).
func _build_ui() -> void:
	_build_stick()
	_add_button("JUMP", 1, "jump")
	_add_button("FIRE", 0, "shoot")
	_add_menu_button()


func _is_in_level() -> bool:
	return get_tree().get_first_node_in_group("level") != null


func _process(_delta: float) -> void:
	var in_game := _is_in_level()
	visible = in_game
	if not in_game:
		for action in _buttons:
			Input.action_release(action)
		_end_stick()
		for action in ["move_left", "move_right"]:
			Input.action_release(action)


# --- Virtual stick -----------------------------------------------------

func _build_stick() -> void:
	_stick_base = Control.new()
	_stick_base.custom_minimum_size = Vector2(STICK_RADIUS * 2.0, STICK_RADIUS * 2.0)
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.offset_left = 40.0
	_stick_base.offset_top = -STICK_RADIUS * 2.0 - 40.0
	_stick_base.offset_right = 40.0 + STICK_RADIUS * 2.0
	_stick_base.offset_bottom = -40.0
	_stick_base.modulate = Color(1, 1, 1, 0.4)
	_stick_base.gui_input.connect(_on_stick_input)
	add_child(_stick_base)

	var base_circle := _make_circle(Color(0.3, 0.3, 0.35, 0.6))
	_stick_base.add_child(base_circle)

	_stick_knob = Control.new()
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.custom_minimum_size = Vector2(110, 110)
	_stick_knob.set_anchors_preset(Control.PRESET_CENTER)
	_stick_knob.offset_left = -55.0
	_stick_knob.offset_top = -55.0
	_stick_knob.offset_right = 55.0
	_stick_knob.offset_bottom = 55.0
	_stick_base.add_child(_stick_knob)
	_stick_knob.add_child(_make_circle(Color(0.85, 0.85, 0.9, 0.8)))


func _make_circle(color: Color) -> Control:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0, 0, 0, 0)
	# Visuals only: never intercept touches meant for the stick base.
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.draw.connect(func() -> void:
		var radius := minf(rect.size.x, rect.size.y) * 0.5
		rect.draw_circle(rect.size * 0.5, radius, color))
	return rect


func _on_stick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_stick_touch_index = touch.index
			_stick_center = _stick_base.size * 0.5
			_update_stick(touch.position)
		elif touch.index == _stick_touch_index:
			_end_stick()
	elif event is InputEventScreenDrag and event.index == _stick_touch_index:
		_update_stick((event as InputEventScreenDrag).position)


func _update_stick(pos: Vector2) -> void:
	var offset := pos - _stick_center
	if offset.length() > STICK_RADIUS:
		offset = offset.normalized() * STICK_RADIUS
	_stick_knob.position = _stick_center + offset - _stick_knob.custom_minimum_size * 0.5
	var axis := offset.x / STICK_RADIUS
	Input.action_release("move_left")
	Input.action_release("move_right")
	if axis > DEAD_ZONE:
		Input.action_press("move_right")
	elif axis < -DEAD_ZONE:
		Input.action_press("move_left")


func _end_stick() -> void:
	_stick_touch_index = -1
	if _stick_base != null and _stick_knob != null:
		_stick_knob.position = _stick_base.size * 0.5 - _stick_knob.custom_minimum_size * 0.5
	Input.action_release("move_left")
	Input.action_release("move_right")


# --- Buttons ------------------------------------------------------------

func _add_button(label: String, row: int, action: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(112.0, 112.0)
	button.add_theme_font_size_override("font_size", 40)
	button.modulate = Color(1.0, 1.0, 1.0, 0.55)
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.offset_left = -136.0 - 24.0
	button.offset_right = -24.0
	# Stack rows upward from the bottom edge; row 0 is nearest the edge.
	button.offset_top = -124.0 - 124.0 * row
	button.offset_bottom = -12.0 - 124.0 * row
	button.pressed.connect(_on_pressed.bind(action))
	button.button_down.connect(_on_button_down.bind(action))
	button.button_up.connect(_on_button_up.bind(action))
	add_child(button)
	_buttons[action] = button


## Issue #78: menu button in the top-right corner, next to the inventory
## toggle button; opens the in-game pause menu.
func _add_menu_button() -> void:
	var button := Button.new()
	button.text = "MENU"
	button.custom_minimum_size = Vector2(150.0, 64.0)
	button.add_theme_font_size_override("font_size", 30)
	button.modulate = Color(1.0, 1.0, 1.0, 0.6)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Left of the inventory toggle button (which sits at the very corner).
	button.offset_left = -360.0
	button.offset_right = -210.0
	button.offset_top = 20.0
	button.offset_bottom = 84.0
	button.pressed.connect(_on_menu_pressed)
	add_child(button)


func _on_menu_pressed() -> void:
	var menu := get_node_or_null("/root/InGameMenu")
	if menu != null and menu.has_method("open_menu"):
		menu.open_menu()


func _on_button_down(action: String) -> void:
	Input.action_press(action)


func _on_button_up(action: String) -> void:
	Input.action_release(action)


func _on_pressed(action: String) -> void:
	# Release again in case press/release events were missed.
	Input.action_release(action)
