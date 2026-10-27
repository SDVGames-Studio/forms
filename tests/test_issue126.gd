extends Node
## Regression check for issue #126: in spectator mode the camera can be
## panned — mouse drag on PC and finger drag on touch devices. In normal
## play (a controlled member exists) panning stays disabled and the camera
## keeps following the controlled figure.
##
## Run headless: godot --headless res://tests/test_issue126.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	# --- Spectator case: LevelDuel has no controlled member. ---
	var duel: Node = load("res://LevelDuel.tscn").instantiate()
	add_child(duel)
	for i in 30:
		await get_tree().physics_frame
	var cam: Camera2D = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		cam = c
	var spectator: bool = cam != null and cam._is_spectator()
	var start: Vector2 = cam.global_position if cam != null else Vector2.ZERO
	# Simulate a touch drag across the screen (same path the mouse drag
	# uses: press, drag, release).
	var vp := get_viewport()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = vp.get_visible_rect().size * 0.5
	Input.parse_input_event(press)
	await get_tree().process_frame
	var drag: InputEventScreenDrag
	for i in 5:
		drag = InputEventScreenDrag.new()
		drag.index = 0
		drag.position = press.position + Vector2(20.0 * (i + 1), -10.0 * (i + 1))
		drag.relative = Vector2(20.0, -10.0)
		Input.parse_input_event(drag)
		await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = press.position + Vector2(100.0, -50.0)
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame
	var moved: bool = cam != null and cam.global_position != start
	# Headless stretch transforms make exact deltas unreliable; verify the
	# pan direction (drag right+up -> camera moves left+down).
	var direction: bool = cam != null \
			and cam.global_position.x < start.x \
			and cam.global_position.y > start.y
	ok = ok and spectator and moved and direction
	print("ISSUE126 spectator=", spectator, " moved=", moved,
		" direction=", direction, " pos=", cam.global_position)
	duel.queue_free()
	await get_tree().process_frame

	# --- Normal play case: a controlled member exists -> no panning. ---
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 60:
		await get_tree().physics_frame
	cam = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		cam = c
	var playing: bool = cam != null and not cam._is_spectator()
	var cam_start: Vector2 = cam.global_position if cam != null else Vector2.ZERO
	press = InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(press)
	await get_tree().process_frame
	drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = press.position + Vector2(80.0, 0.0)
	drag.relative = Vector2(80.0, 0.0)
	Input.parse_input_event(drag)
	await get_tree().process_frame
	release = InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = drag.position
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().physics_frame
	var not_moved: bool = cam != null and cam.global_position == cam_start
	ok = ok and playing and not_moved
	print("ISSUE126 playing=", playing, " camera_follows=", not_moved)

	print("ISSUE126 ok=", ok)
	get_tree().quit(0 if ok else 1)
