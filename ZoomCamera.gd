extends Camera2D
## Player camera with zoom controls (issue #43).
##
## Issue #63: zoom applies to the PLAYER'S VIEW, not to one character —
## this is the single shared camera for the whole player team. It follows
## the currently controlled member (it is top-level, so it does not move
## with whatever node it is parented to), and zoom persists when control
## switches between team members.
##
## Press + / - (or numpad + / -) or scroll the mouse wheel (issue #233)
## to zoom in and out. The zoom level shows
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
##
## Issue #289: two camera types. The default STATIC camera keeps the view
## world-aligned (exactly the old behaviour). The CHARACTER camera is
## aligned with the character's local coordinate system: the view rotates
## with the figure's gravity frame (the same frame FigurePose.align_to_gravity
## rotates the body to), so a figure standing at an angle — the rim of a
## disc arena, below a level's central line — appears UPRIGHT, feet to
## screen-down. The type is per-VIEW, shared by every camera in the group
## (like zoom), and is switched with the bottom-left button (CameraSwitch).

const ZOOM_STEP := 1.25
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0

## Issue #289: camera types.
const MODE_STATIC := 0
const MODE_CHARACTER := 1

## Issue #289: how fast the view rotates to a new frame angle (per second,
## exponential ease). Walking around a disc rim changes the angle slowly, so
## this only smooths the mode switch and the gravity flip at a central line —
## and lerp_angle takes the shortest arc, so the wrap at ±PI never spins.
const ROTATION_SMOOTH := 6.0

## Issue #289: the active camera type — a static var, so every camera in
## the view (scene-authored plus fallbacks) shares one mode, like zoom.
static var camera_mode := MODE_STATIC


var _dragging := false
var _drag_last := Vector2.ZERO
## Issue #212: pan offset relative to the controlled member. Follow applies
## it so the panned view persists hands-free; a new member resets it.
var _pan_offset := Vector2.ZERO
var _followed_member: Node2D = null


func _ready() -> void:
	top_level = true
	# Issue #289: this Camera2D DRIVES its own rotation (the eased frame
	# angle below), so the view must not ignore it — `ignore_rotation` keeps
	# its pre-4.4 default (true) for compatibility and would drop the angle
	# from the view transform. Godot's own rotation_smoothing stays OFF: the
	# lerp_angle ease below handles the shortest arc around the ±PI wrap.
	ignore_rotation = false
	global_position = _controlled_member().global_position if _controlled_member() != null else global_position
	add_to_group("player_camera")
	# Zoom is per-view: keep it identical for every camera in the group so
	# any camera instance created as a fallback shares the same zoom state.
	add_child(load("res://OSD.gd").new())
	# Issue #289: the camera-type switch button (bottom-left corner).
	add_child(load("res://CameraSwitch.gd").new())

func _process(delta: float) -> void:
	var member := _controlled_member()
	# Issue #289: ease the view rotation to the current type's target — 0 in
	# the static mode, the character's gravity frame in the character mode
	# (no member to follow → back to world-aligned).
	rotation = lerp_angle(rotation, _rotation_target(member),
			1.0 - exp(-ROTATION_SMOOTH * delta))
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


## Issue #289: the view angle the CHARACTER camera type eases to. It is the
## SAME target FigurePose.align_to_gravity rotates the body children by, so
## the body's +Y (its feet) points at screen-down in the rendered view: the
## character's local frame becomes the screen frame wherever it stands.
func _rotation_target(member: Node2D) -> float:
	if camera_mode != MODE_CHARACTER or member == null:
		return 0.0
	var grav := Vector2.DOWN
	if member.has_method("current_gravity"):
		grav = member.current_gravity()
	elif "up_direction" in member:
		grav = -(member.up_direction as Vector2)
	return grav.angle() - PI / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_apply_zoom(ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_apply_zoom(1.0 / ZOOM_STEP)
		return
	# Issue #233: zoom with the mouse wheel — scroll up zooms in, scroll down
	# zooms out, with the same step/limits as the +/- keys. Handled BEFORE the
	# armed-teleport check below: a wheel scroll is not a click, so zoom keeps
	# working while a teleport destination is being picked.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(1.0 / ZOOM_STEP)
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
	# Screen pixels -> world units at the current zoom. In a rotated view
	# (issue #289 character camera) the delta is rotated into the world frame
	# first, so the view still tracks the finger/mouse one to one; with no
	# rotation this is exactly the old formula.
	var world_delta := screen_delta.rotated(rotation) / zoom.x
	global_position -= world_delta
	_pan_offset -= world_delta


func _apply_zoom(factor: float) -> void:
	var target := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	for camera in get_tree().get_nodes_in_group("player_camera"):
		camera.zoom = Vector2(target, target)
	zoom = Vector2(target, target)


