extends Camera2D
## Player camera with zoom controls (issue #43).
##
## Issue #63: zoom applies to the PLAYER'S VIEW, not to one character —
## this is the single shared camera for the whole player team. It follows
## the currently controlled member (it is top-level, so it does not move
## with whatever node it is parented to), and zoom persists when control
## switches between team members.
##
## Press + / - (or numpad + / -) to zoom in and out. The zoom level shows
## in the top-left OSD (issue #76, shared with FPS and the level name).

const ZOOM_STEP := 1.25
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0


func _ready() -> void:
	top_level = true
	global_position = _controlled_member().global_position if _controlled_member() != null else global_position
	add_to_group("player_camera")
	# Zoom is per-view: keep it identical for every camera in the group so
	# any camera instance created as a fallback shares the same zoom state.
	add_child(load("res://OSD.gd").new())

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


