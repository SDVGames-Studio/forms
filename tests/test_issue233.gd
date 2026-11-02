extends Node
## Regression check for issue #233: the camera zooms with the mouse wheel.
## Scroll up zooms in, scroll down zooms out (same step/limits as the +/-
## keys), the zoom is shared by every camera in the player_camera group,
## and the wheel keeps working while a teleport is armed (issue #170) —
## a wheel scroll is not a click and must not be swallowed.
##
## Run headless: godot --headless res://tests/test_issue233.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 60:
		await get_tree().physics_frame
	var cam: Camera2D = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		cam = c
	var playing: bool = cam != null and not cam._is_spectator()
	var start: float = cam.zoom.x if cam != null else -1.0

	# --- Scroll up: zoom in (zoom.x grows past 1.0). ---
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(wheel_up)
	Input.flush_buffered_events()
	await get_tree().process_frame
	var zoomed_in: bool = cam.zoom.x > start
	print("ISSUE233 playing=", playing, " start=", start,
		" zoomed_in=", zoomed_in, " zoom=", cam.zoom.x)
	ok = ok and playing and zoomed_in

	# --- Scroll down twice: zoom out below the start level. ---
	for i in 2:
		var wheel_down := InputEventMouseButton.new()
		wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel_down.pressed = true
		wheel_down.position = wheel_up.position
		Input.parse_input_event(wheel_down)
		Input.flush_buffered_events()
		await get_tree().process_frame
	var zoomed_out: bool = cam.zoom.x < start
	print("ISSUE233 zoomed_out=", zoomed_out, " zoom=", cam.zoom.x)
	ok = ok and zoomed_out

	# --- Every camera in the group shares the same zoom. ---
	var shared := true
	for c in get_tree().get_nodes_in_group("player_camera"):
		shared = shared and c.zoom == cam.zoom
	print("ISSUE233 shared=", shared)
	ok = ok and shared

	# --- Armed teleport (issue #170): the wheel still zooms. ---
	ToolInventory.armed_tool = ToolInventory.TOOL_TELEPORT
	var before := cam.zoom.x
	Input.parse_input_event(wheel_up)
	Input.flush_buffered_events()
	await get_tree().process_frame
	var armed_zoom: bool = cam.zoom.x > before
	print("ISSUE233 armed_zoom=", armed_zoom)
	ok = ok and armed_zoom
	ToolInventory.armed_tool = -1

	print("ISSUE233 ok=", ok)
	get_tree().quit(0 if ok else 1)
