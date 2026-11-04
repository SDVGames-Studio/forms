extends Node
## Regression check for issue #304: the in-game pause menu opens the
## SAME settings screen as the main menu — instanced over the paused
## game (the running level must survive), with every entry present
## (Teams, Hotkeys, Debug Mode, Gravity Field, Back). The submenus
## (Teams, Hotkeys) also open over the game and return to the settings
## screen; Settings Back returns to the pause panel with the game still
## paused. Standalone mode is unchanged: Back leaves for the main menu.
##
## Run headless: godot --headless res://tests/test_issue304.tscn
## Exit code 0 = pass.

func _ready() -> void:
	# The driver must survive the scene change it provokes, so it lives
	# directly under /root and runs while the tree is paused. The quit
	# callback captures the TREE, not this node — this scene is freed by
	# the final scene change before the driver reports back.
	var tree := get_tree()
	var driver := Issue304Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		tree.quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue304Driver extends Node:
	signal done(ok: bool)

	func _init() -> void:
		# The whole point of the overlay is that it works while paused.
		process_mode = Node.PROCESS_MODE_ALWAYS

	func run() -> void:
		var ok := true
		var pause: Node = get_node_or_null("/root/InGameMenu")
		if pause == null:
			print("ISSUE304 autoload_missing=true")
			done.emit(false)
			return

		# --- Pause-panel state, exactly as Esc leaves it. ---
		var panel: Control = pause.get("_panel")
		panel.visible = true
		get_tree().paused = true

		# --- Settings opens the shared screen over the game. ---
		pause._on_settings_pressed()
		await get_tree().process_frame
		var settings: Control = pause.get("_settings_menu")
		var opened: bool = settings != null and settings.is_inside_tree() \
			and settings.get("in_game") == true \
			and not panel.visible and get_tree().paused
		# The very same entries as the main-menu settings screen.
		var entries: bool = settings != null \
			and settings.get_node_or_null("%TeamButton") != null \
			and settings.get_node_or_null("%HotkeysButton") != null \
			and settings.get_node_or_null("%DebugCheck") != null \
			and settings.get_node_or_null("%GravityFieldCheck") != null \
			and settings.get_node_or_null("%BackButton") != null
		print("ISSUE304 settings_open=", opened, " entries=", entries)
		ok = ok and opened and entries

		# --- The Teams submenu opens over the game, not as a scene change. ---
		var scene_before: Node = get_tree().current_scene
		settings._on_team_pressed()
		await get_tree().process_frame
		var submenu: Control = settings.get("_submenu")
		var team_open: bool = submenu != null and submenu.is_inside_tree() \
			and submenu.get("in_game") == true \
			and get_tree().current_scene == scene_before
		print("ISSUE304 teams_overlay=", team_open)
		ok = ok and team_open

		# --- Its Back returns to the settings screen, game still paused. ---
		submenu._on_back_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
		var team_closed: bool = settings.get("_submenu") == null \
			and not is_instance_valid(submenu) \
			and pause.get("_settings_menu") != null \
			and get_tree().paused
		print("ISSUE304 teams_back=", team_closed)
		ok = ok and team_closed

		# --- The Hotkeys submenu behaves the same. ---
		settings = pause.get("_settings_menu")
		settings._on_hotkeys_pressed()
		await get_tree().process_frame
		var hotkeys: Control = settings.get("_submenu")
		var hotkeys_open: bool = hotkeys != null \
			and hotkeys.is_inside_tree()
		print("ISSUE304 hotkeys_overlay=", hotkeys_open)
		ok = ok and hotkeys_open
		hotkeys._on_back_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
		var hotkeys_closed: bool = settings.get("_submenu") == null \
			and not is_instance_valid(hotkeys)
		print("ISSUE304 hotkeys_back=", hotkeys_closed)
		ok = ok and hotkeys_closed

		# --- Settings Back returns to the pause panel, still paused. ---
		settings._on_back_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
		var back: bool = pause.get("_settings_menu") == null \
			and not is_instance_valid(settings) \
			and panel.visible and get_tree().paused
		print("ISSUE304 settings_back=", back)
		ok = ok and back

		# --- Standalone mode is unchanged: Back leaves for the main menu. ---
		get_tree().paused = false
		var standalone: Node = load("res://SettingsMenu.tscn").instantiate()
		add_child(standalone)
		await get_tree().process_frame
		standalone._on_back_pressed()
		for i in 3:
			await get_tree().process_frame
		var went: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == "res://Main.tscn"
		print("ISSUE304 standalone_back=", went)
		ok = ok and went

		print("ISSUE304 ok=", ok)
		done.emit(ok)
