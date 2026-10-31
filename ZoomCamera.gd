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
##
## Issue #126: in spectator mode (no controlled member — e.g. the AI vs AI
## duel) the camera does not follow anyone, so it can be panned freely:
## hold the left mouse button and drag on PC, or drag a finger across the
## screen on touch devices. Input events consumed by UI (virtual stick,
## buttons) never reach _unhandled_input, so panning never fights them.
##
## Issue #212: spectating is available ALWAYS, not only in spectator mode.
## During normal play dragging pans the view away from the controlled
## figure and the pan persists after the drag is released (follow resumes
## with the offset). Switching the controlled member (N / P / Switch tool /
## new turn) re-centers the camera on it. An armed teleport (issue #170)
## keeps its click: the destination press never starts a camera drag.

const ZOOM_STEP := 1.25
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0


var _dragging := false
var _drag_last := Vector2.ZERO
## Issue #212: pan offset relative to the controlled member. Follow applies
## it so the panned view persists hands-free; a new member resets it.
var _pan_offset := Vector2.ZERO
var _followed_member: Node2D = null


func _ready() -> void:
	top_level = true
	global_position = _controlled_member().global_position if _controlled_member() != null else global_position
	add_to_group("player_camera")
	# Zoom is per-view: keep it identical for every camera in the group so
	# any camera instance created as a fallback shares the same zoom state.
	add_child(load("res://OSD.gd").new())

func _process(_delta: float) -> void:
	var member := _controlled_member()
	if member == null:
		return
	if member != _followed_member:
		# Issue #212: control switched to another member — re-center.
		_followed_member = member
		_pan_offset = Vector2.ZERO
	if not _dragging:
		global_position = member.global_position + _pan_offset


func _is_spectator() -> bool:
	return _controlled_member() == null


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
		return
	# Issue #170: while a teleport is armed the next left click picks the
	# destination — it must reach ToolInventory, not start a camera drag.
	if ToolInventory.armed_tool == ToolInventory.TOOL_TELEPORT:
		if (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_last = event.position
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		# Screen-drag panning (issue #126); touches on the virtual stick or
		# buttons are consumed as GUI input and never arrive here.
		_dragging = event.pressed
		if _dragging:
			_drag_last = event.position
	elif event is InputEventScreenDrag and _dragging:
		_pan_by(event.relative)
	elif event is InputEventMouseMotion and _dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_pan_by(event.relative)


func _pan_by(screen_delta: Vector2) -> void:
	# Screen pixels -> world units at the current zoom.
	var world_delta := screen_delta / zoom.x
	global_position -= world_delta
	_pan_offset -= world_delta


func _apply_zoom(factor: float) -> void:
	var target := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	for camera in get_tree().get_nodes_in_group("player_camera"):
		camera.zoom = Vector2(target, target)
	zoom = Vector2(target, target)


