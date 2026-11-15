extends CanvasLayer
## Camera-type switch button (issue #289, reworked for #552).
##
## A small button in the LEFT BOTTOM corner of the screen that cycles the
## shared player camera through its three types (see ZoomCamera.gd):
##   CAM: CHARACTER GLOBAL — the default world-aligned view (the old
##                            "STATIC", renamed by #552);
##   CAM: CHARACTER LOCAL  — the view aligned with the character's local
##                            coordinate system (rotates with the figure's
##                            frame; the old "CHARACTER", renamed by #552);
##   CAM: GLOBAL           — #552: fully independent of any figure; the
##                            game never moves it, only the player does.
## The camera itself builds this layer as a child (like the OSD), so the
## button exists exactly where a player camera exists. The label rereads
## the shared mode every frame, so any instance (scene camera or fallback)
## always shows the live type.
##
## On touchscreen devices the virtual movement stick owns the bottom-left
## corner (TouchControls), so the button sits directly ABOVE the stick —
## still on the left edge, clear of the stick's touch zone.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

## Issue #552: the renamed pair plus the new third type.
const TEXT_FOLLOW := "CAM: CHARACTER GLOBAL"
const TEXT_LOCAL := "CAM: CHARACTER LOCAL"
const TEXT_GLOBAL := "CAM: GLOBAL"

var _button: Button


func _ready() -> void:
	layer = 12
	# Issue #353: GUI input is NOT blocked by SceneTree pause, so this
	# layer (12) floats above the in-game menu's dim (layer 10) and its
	# button stayed clickable while the game was paused. The layer keeps
	# processing during the pause so it can hide itself (see _process).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_button = Button.new()
	_button.name = "CameraSwitch"
	_button.text = TEXT_FOLLOW
	_button.custom_minimum_size = Vector2(280, 64)
	_button.add_theme_font_size_override("font_size", 22)
	_button.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_button.offset_left = 24.0
	_button.offset_right = 304.0
	_button.offset_top = -88.0
	_button.offset_bottom = -24.0
	if DisplayServer.is_touchscreen_available():
		# Above the virtual stick: the stick base spans x 40..300 from the
		# left, up to 340 px from the bottom (TouchControls) — keep clear.
		_button.offset_top = -404.0
		_button.offset_bottom = -340.0
	_button.pressed.connect(_on_pressed)
	# Issue #294: Space must NOT flip the camera. A clicked Button keeps
	# keyboard focus, and Godot activates a focused button on Space — the
	# JUMP key — so after one click on this button every jump also flipped
	# the camera type. The switch is the mouse/touch click plus the C key
	# ("camera_switch", see _unhandled_input below) only.
	_button.focus_mode = Control.FOCUS_NONE
	add_child(_button)


func _process(_delta: float) -> void:
	# Issue #353: while the in-game menu has the game paused, the whole
	# layer hides — the camera button must not hover above the pause dim
	# and stay clickable. The next unpaused frame brings it back.
	visible = not get_tree().paused
	_button.text = _mode_text(ZoomCameraScript.camera_mode)


## Issue #552: the button label for a shared camera type — the type names
## are the issue's own ("character local" / "character global" / "global").
func _mode_text(mode: int) -> String:
	match mode:
		ZoomCameraScript.MODE_CHARACTER:
			return TEXT_LOCAL
		ZoomCameraScript.MODE_GLOBAL:
			return TEXT_GLOBAL
		_:
			return TEXT_FOLLOW


func _mode_name(mode: int) -> String:
	match mode:
		ZoomCameraScript.MODE_CHARACTER:
			return "character local"
		ZoomCameraScript.MODE_GLOBAL:
			return "global"
		_:
			return "character global"


## Issue #289/#552: cycle the shared camera type through all three (every
## camera in the view reads the same static var, so one press switches
## them all).
func _on_pressed() -> void:
	ZoomCameraScript.camera_mode = (ZoomCameraScript.camera_mode + 1) \
			% ZoomCameraScript.MODE_COUNT
	DebugInfo.log("camera mode: %s" \
			% _mode_name(ZoomCameraScript.camera_mode))


## Issue #294: the C key flips the camera type exactly like the button.
## The action is rebindable in the settings hotkeys screen, so it is read
## from the InputMap, never from a hardcoded keycode.
func _unhandled_input(event: InputEvent) -> void:
	# Issue #353: no camera flips from behind the pause menu.
	if get_tree().paused:
		return
	if event.is_action_pressed("camera_switch"):
		_on_pressed()
		get_viewport().set_input_as_handled()
