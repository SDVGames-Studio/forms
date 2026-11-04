extends CanvasLayer
## Camera-type switch button (issue #289).
##
## A small button in the LEFT BOTTOM corner of the screen that flips the
## shared player camera between its two types (see ZoomCamera.gd):
##   CAM: STATIC    — the default world-aligned view;
##   CAM: CHARACTER — the view aligned with the character's local
##                    coordinate system (rotates with the figure's frame).
## The camera itself builds this layer as a child (like the OSD), so the
## button exists exactly where a player camera exists. The label rereads
## the shared mode every frame, so any instance (scene camera or fallback)
## always shows the live type.
##
## On touchscreen devices the virtual movement stick owns the bottom-left
## corner (TouchControls), so the button sits directly ABOVE the stick —
## still on the left edge, clear of the stick's touch zone.

const ZoomCameraScript := preload("res://ZoomCamera.gd")

const TEXT_STATIC := "CAM: STATIC"
const TEXT_CHARACTER := "CAM: CHARACTER"

var _button: Button


func _ready() -> void:
	layer = 12
	_button = Button.new()
	_button.name = "CameraSwitch"
	_button.text = TEXT_STATIC
	_button.custom_minimum_size = Vector2(180, 64)
	_button.add_theme_font_size_override("font_size", 22)
	_button.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_button.offset_left = 24.0
	_button.offset_right = 204.0
	_button.offset_top = -88.0
	_button.offset_bottom = -24.0
	if DisplayServer.is_touchscreen_available():
		# Above the virtual stick: the stick base spans x 40..300 from the
		# left, up to 340 px from the bottom (TouchControls) — keep clear.
		_button.offset_top = -404.0
		_button.offset_bottom = -340.0
	_button.pressed.connect(_on_pressed)
	add_child(_button)


func _process(_delta: float) -> void:
	_button.text = TEXT_CHARACTER \
			if ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_CHARACTER \
			else TEXT_STATIC


## Issue #289: flip the shared camera type (every camera in the view reads
## the same static var, so one press switches them all).
func _on_pressed() -> void:
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_CHARACTER \
			if ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC \
			else ZoomCameraScript.MODE_STATIC
	DebugInfo.log("camera mode: %s" % [
			"character frame" \
			if ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_CHARACTER \
			else "static"])
