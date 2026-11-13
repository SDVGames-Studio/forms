extends Node
## Regression check for issue #456 (rework, owner report 2026-11-11):
## "can't move cam when I choose where to teleport with the teleport
## tool. RMB cam moving is needed for this". Arming the teleport used to
## swallow EVERY mouse press before the drag code ran, so the RIGHT
## button could not start a camera pan while a destination was being
## picked. Now only the LEFT press (the destination pick — ToolInventory
## consumes MOUSE_BUTTON_LEFT) and touch presses are swallowed; a right
## press + drag pans the view and spends nothing. The left-click pick
## itself is unchanged (covered by tests #212/#233/#328).
##
## Run headless: godot --headless res://tests/test_issue456.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	var level: Node = load("res://scenes/levels/Level.tscn").instantiate()
	add_child(level)
	for i in 60:
		await get_tree().physics_frame
	var cam: Camera2D = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		cam = c
	var playing: bool = cam != null and not cam._is_spectator()
	var member: Node2D = cam._controlled_member() if cam != null else null
	var start: Vector2 = cam.global_position if cam != null else Vector2.ZERO

	# --- Arm the teleport, as selecting the tool does (issue #170). ---
	ToolInventory.armed_tool = ToolInventory.TOOL_TELEPORT
	var armed: bool = ToolInventory.armed_tool == ToolInventory.TOOL_TELEPORT
	print("ISSUE456 playing=", playing, " armed=", armed)
	ok = ok and playing and armed

	# --- RMB drag pans WHILE the teleport stays armed (the fix). ---
	var vp := get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
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
	# Drag right+up -> camera moves left+down, like the LMB drag (#212).
	var direction: bool = cam.global_position.x < start.x \
		and cam.global_position.y > start.y
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = motion.position
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame
	# The pan persists after release — hands-free spectating (#212).
	var persisted: bool = cam.global_position != start

	# --- The right press is not a destination pick: the tool stays
	#     armed (a pick would disarm/consume it in ToolInventory). ---
	var still_armed: bool = ToolInventory.armed_tool == ToolInventory.TOOL_TELEPORT
	print("ISSUE456 dragged=", dragged, " direction=", direction,
		" persisted=", persisted, " still_armed=", still_armed,
		" pos=", cam.global_position)
	ok = ok and dragged and direction and persisted and still_armed
	ToolInventory.armed_tool = -1

	print("ISSUE456 ok=", ok)
	get_tree().quit(0 if ok else 1)
