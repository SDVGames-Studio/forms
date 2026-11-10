extends Node
## Regression check for issue #222: the game must not block after the win.
## When one team wins, nobody may move (player input and AI alike), but
## the game keeps running — the tree is NOT paused and the player keeps a
## live view to SPECTATE: the shared camera survives the dying team (it
## used to be disabled or freed with its host member), stays enabled in
## spectator mode (#126) and drag-panning still moves the view.
##
## Run headless: godot --headless res://tests/test_issue222.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame

	# Let the first-team roll finish (a forced game-over during the roll
	# would race its callbacks) and let a real turn begin.
	for i in 200:
		await get_tree().physics_frame
		if TurnController.active_team != "":
			break
	# Force a player turn (whatever team the roll picked) and wipe the
	# whole player team — the enemy team wins.
	var members := get_tree().get_nodes_in_group("player_team")
	TurnController.active_team = TurnController.TEAM_PLAYER
	TurnController.active_member = members[0] if not members.is_empty() else null
	for m in members:
		m.take_damage(9999)
	var over := false
	for i in 120:
		await get_tree().physics_frame
		if TurnController.game_over:
			over = true
			break
	# Let the 0.25 s death tweens free the corpses.
	for i in 30:
		await get_tree().physics_frame

	# --- Nobody may act any more, but the game is NOT paused. ---
	var no_moves: bool = TurnController.game_over and over \
		and TurnController.active_team == "" \
		and TurnController.active_member == null
	var not_paused: bool = not get_tree().paused
	var banner: bool = TurnController._label != null \
		and TurnController._label.text == "PINK TEAM WINS!"
	var spectate_hint: bool = TurnController._hint_label != null \
		and TurnController._hint_label.text == TurnController.HINT_SPECTATE
	# Something to watch: the winning enemy team is still on the field.
	var enemy_alive: bool = not get_tree().get_nodes_in_group("enemy_team").is_empty()
	print("ISSUE222 no_moves=", no_moves, " not_paused=", not_paused,
		" banner=", banner, " spectate_hint=", spectate_hint,
		" enemy_alive=", enemy_alive)
	ok = ok and no_moves and not_paused and banner and spectate_hint and enemy_alive

	# --- The camera survived the wiped team and stays enabled (spectator). ---
	var cam: Camera2D = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(c) and c.get_tree() != null:
			cam = c
	var cam_alive: bool = cam != null
	var cam_enabled: bool = cam_alive and cam.enabled
	var spectator: bool = cam_alive and cam._is_spectator()
	print("ISSUE222 cam_alive=", cam_alive, " cam_enabled=", cam_enabled,
		" spectator=", spectator)
	ok = ok and cam_alive and cam_enabled and spectator

	# --- Spectating still works: drag-panning moves the live view. ---
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
	print("ISSUE222 panned=", panned, " pos=", cam.global_position)
	ok = ok and panned

	print("ISSUE222 ok=", ok)
	get_tree().quit(0 if ok else 1)
