extends Node
## Regression check for issue #212: spectating with the mouse is available
## ALWAYS — during normal play too, not only in spectator mode (#126).
## Left-mouse drag pans the camera away from the controlled figure, the
## pan PERSISTS after the button is released, and switching the controlled
## member re-centers the camera on the new one. While a teleport is armed
## (issue #170) the destination click must not be swallowed by the camera.
##
## Run headless: godot --headless res://tests/test_issue212.tscn
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
	var member: Node2D = cam._controlled_member() if cam != null else null
	# With no pan yet the camera sits exactly on the controlled member.
	var follows: bool = member != null \
		and cam.global_position == member.global_position
	var start: Vector2 = cam.global_position if cam != null else Vector2.ZERO

	# --- Hold the left mouse button and drag: the view pans (#212). ---
	var vp := get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = vp.get_visible_rect().size * 0.5
	Input.parse_input_event(press)
	await get_tree().process_frame
	var motion: InputEventMouseMotion
	for i in 5:
		motion = InputEventMouseMotion.new()
		motion.position = press.position + Vector2(20.0 * (i + 1), -10.0 * (i + 1))
		motion.relative = Vector2(20.0, -10.0)
		Input.parse_input_event(motion)
		await get_tree().process_frame
	var dragged: bool = cam.global_position != start
	# Drag right+up -> camera moves left+down.
	var direction: bool = cam.global_position.x < start.x \
		and cam.global_position.y > start.y
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame
	# The pan persists after release — hands-free spectating.
	var persisted: bool = cam.global_position != start
	print("ISSUE212 playing=", playing, " follows=", follows,
		" dragged=", dragged, " direction=", direction,
		" persisted=", persisted, " pos=", cam.global_position)
	ok = ok and playing and follows and dragged and direction and persisted

	# --- Switching the controlled member re-centers the camera on it. ---
	var other: Node2D = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if m != member and m is Node2D and m.get("controlled") == false:
			other = m
			break
	if other != null:
		member.set_controlled(false)
		other.set_controlled(true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var recentered: bool = cam.global_position == other.global_position
		print("ISSUE212 recentered=", recentered)
		ok = ok and recentered
	else:
		print("ISSUE212 no second member — recenter check skipped")

	# --- Armed teleport: its click must not start a camera drag. ---
	ToolInventory.armed_tool = ToolInventory.TOOL_TELEPORT
	var tp_press := InputEventMouseButton.new()
	tp_press.button_index = MOUSE_BUTTON_LEFT
	tp_press.pressed = true
	tp_press.position = vp.get_visible_rect().size * 0.5
	Input.parse_input_event(tp_press)
	await get_tree().process_frame
	var click_free: bool = not cam._dragging
	print("ISSUE212 click_free=", click_free)
	ok = ok and click_free
	ToolInventory.armed_tool = -1

	print("ISSUE212 ok=", ok)
	get_tree().quit(0 if ok else 1)
