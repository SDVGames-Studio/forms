extends Node
## Regression check for issue #280: "View is blocked after the match in
## the Duel level". LevelDuel authors the shared camera as a CHILD of an
## NPC figure (BlueAI) — and Npc._die() used to queue_free() the node
## together with its children, so when the camera's host LOST the match
## the camera was freed with it: after the win banner the view froze —
## no camera, no zoom, no drag-pan, no spectating (Player._die already
## rescued the camera for the player team, issue #222; Npc._die now
## mirrors that rescue).
##
## Checks:
##  1. The camera in the duel really is hosted by an NPC figure.
##  2. Kill the host with take_damage(9999) → the match ends
##     (game_over, WINS banner, spectate hint).
##  3. After the death animation frees the host, the camera is STILL
##     alive, enabled, parented to the LEVEL (not the freed corpse) and
##     is a spectator camera.
##  4. Spectating still works: drag-panning moves the live view.
##
## Run headless: godot --headless res://tests/test_issue280.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	var level: Node = load("res://scenes/levels/LevelDuel.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame

	# --- 1. The shared camera is hosted by an NPC figure (LevelDuel). ---
	var cam: Camera2D = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(c) and c.get_tree() != null:
			cam = c
	var host: Node = cam.get_parent() if cam != null else null
	var hosted_by_figure: bool = host != null \
		and (host.is_in_group("player_team") or host.is_in_group("enemy_team"))
	print("ISSUE280 cam=", cam != null, " host=", host.name if host != null else "—",
		" hosted_by_figure=", hosted_by_figure)
	ok = ok and hosted_by_figure

	# Let the first-team roll finish and a real turn begin.
	for i in 200:
		await get_tree().physics_frame
		if TurnController.active_team != "":
			break

	# --- 2. Kill the camera's host — the match ends. ---
	TurnController.active_team = TurnController.TEAM_PLAYER
	TurnController.active_member = host
	host.take_damage(9999)
	var over := false
	for i in 120:
		await get_tree().physics_frame
		if TurnController.game_over:
			over = true
			break
	# Let the 0.25 s death tween free the corpse.
	for i in 30:
		await get_tree().physics_frame

	var banner: bool = TurnController._label != null \
		and TurnController._label.text.ends_with("WINS!")
	var spectate_hint: bool = TurnController._hint_label != null \
		and TurnController._hint_label.text == TurnController.HINT_SPECTATE
	print("ISSUE280 game_over=", over, " banner=", banner,
		" spectate_hint=", spectate_hint)
	ok = ok and over and banner and spectate_hint

	# --- 3. The camera survived its freed host and stays enabled. ---
	var cam_alive: bool = cam != null and is_instance_valid(cam) \
		and cam.get_tree() != null
	var cam_enabled: bool = cam_alive and cam.enabled
	var reparented: bool = cam_alive and cam.get_parent() == level \
		and not is_instance_valid(host)
	var spectator: bool = cam_alive and cam._is_spectator()
	print("ISSUE280 cam_alive=", cam_alive, " cam_enabled=", cam_enabled,
		" reparented=", reparented, " host_freed=", not is_instance_valid(host),
		" spectator=", spectator)
	ok = ok and cam_alive and cam_enabled and reparented and spectator

	# --- 4. Spectating still works: drag-panning moves the live view. ---
	var start: Vector2 = cam.global_position
	var vp := get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = vp.get_visible_rect().size * 0.5
	Input.parse_input_event(press)
	await get_tree().process_frame
	for i in 5:
		var motion := InputEventMouseMotion.new()
		motion.position = press.position + Vector2(20.0 * (i + 1), -10.0 * (i + 1))
		motion.relative = Vector2(20.0, -10.0)
		Input.parse_input_event(motion)
		await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	var panned: bool = cam.global_position != start
	print("ISSUE280 panned=", panned, " pos=", cam.global_position)
	ok = ok and panned

	print("ISSUE280 ok=", ok)
	get_tree().quit(0 if ok else 1)
