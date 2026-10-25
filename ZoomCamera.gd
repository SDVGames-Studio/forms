extends Camera2D
## Player camera with zoom controls (issue #43).
##
## Issue #63: zoom applies to the PLAYER'S VIEW, not to one character —
## this is the single shared camera for the whole player team. It follows
## the currently controlled member (it is top-level, so it does not move
## with whatever node it is parented to), and zoom persists when control
## switches between team members.
##
## Press + / - (or numpad + / -) to zoom in and out. A HUD label in the
## top-left corner shows the current zoom level.

const ZOOM_STEP := 1.25
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0

var _label: Label


func _ready() -> void:
	top_level = true
	global_position = _controlled_member().global_position if _controlled_member() != null else global_position
	add_to_group("player_camera")
	# Zoom is per-view: keep it identical for every camera in the group so
	# any camera instance created as a fallback shares the same zoom state.
	var hud := CanvasLayer.new()
	hud.name = "ZoomHud"
	_label = Label.new()
	_label.name = "ZoomLabel"
	_label.position = Vector2(12.0, 12.0)
	_label.text = ""
	hud.add_child(_label)
	add_child(hud)
	_update_label()


func _process(_delta: float) -> void:
	var member := _controlled_member()
	if member != null:
		global_position = member.global_position


func _controlled_member() -> Node2D:
	for member in get_tree().get_nodes_in_group("player_team"):
		if member.get("controlled") == true:
			return member
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_apply_zoom(ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_apply_zoom(1.0 / ZOOM_STEP)


func _apply_zoom(factor: float) -> void:
	var target := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	for camera in get_tree().get_nodes_in_group("player_camera"):
		camera.zoom = Vector2(target, target)
	zoom = Vector2(target, target)
	_update_label()


func _update_label() -> void:
	if _label:
		_label.text = "Zoom: %d%%" % roundi(zoom.x * 100.0)
