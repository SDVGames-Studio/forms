extends Camera2D
## Player camera with zoom controls (issue #43).
##
## Press + / - (or numpad + / -) to zoom in and out. A HUD label in the
## top-left corner shows the current zoom level.

const ZOOM_STEP := 1.25
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0

var _label: Label


func _ready() -> void:
	var hud := CanvasLayer.new()
	hud.name = "ZoomHud"
	_label = Label.new()
	_label.name = "ZoomLabel"
	_label.position = Vector2(12.0, 12.0)
	_label.text = ""
	hud.add_child(_label)
	add_child(hud)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_apply_zoom(ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_apply_zoom(1.0 / ZOOM_STEP)


func _apply_zoom(factor: float) -> void:
	var target := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(target, target)
	_update_label()


func _update_label() -> void:
	if _label:
		_label.text = "Zoom: %d%%" % roundi(zoom.x * 100.0)
