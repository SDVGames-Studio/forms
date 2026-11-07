extends Node
## Settings-category checks per docs/ui/main_menu.md §6 + owner decision
## Q1 (2026-11-06), milestone M2: the Settings screen shows categories
## (TEAMS CUSTOMIZATION / CONTROLS / DEBUG; GRAPHICS arrives with M3),
## the debug switches live on the DebugMenu category screen (no longer
## on the Settings root), toggles persist through GameConfig, every
## category opens its screen and Back returns — standalone and in the
## in-game overlay mode (issue #304 pattern).
##
## Run headless: godot --headless res://tests/test_settings_categories.tscn
## Exit code 0 = pass; the printed SETTINGS ok= verdict is authoritative.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	var driver := SettingsCategoriesDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class SettingsCategoriesDriver extends Node:
	signal done(ok: bool)

	func _init() -> void:
		# The overlay-mode checks run while the tree is paused.
		process_mode = Node.PROCESS_MODE_ALWAYS

	func run() -> void:
		var ok := true
		var settings: Node = load("res://SettingsMenu.tscn").instantiate()
		add_child(settings)
		await get_tree().process_frame

		# --- Settings root: category buttons, no inline debug toggles. ---
		var team: Button = settings.get_node_or_null("%TeamButton")
		var controls: Button = settings.get_node_or_null("%HotkeysButton")
		var debug: Button = settings.get_node_or_null("%DebugButton")
		var back: Button = settings.get_node_or_null("%BackButton")
		var categories: bool = team != null and controls != null \
			and debug != null and back != null \
			and team.text == "TEAMS CUSTOMIZATION" \
			and controls.text == "CONTROLS" \
			and debug.text == "DEBUG" \
			and settings.get_node_or_null("%DebugCheck") == null \
			and settings.get_node_or_null("%GravityFieldCheck") == null
		print("SETTINGS categories=", categories)
		ok = ok and categories

		# --- Categories open their screens (standalone scene change). ---
		ok = ok and await _nav_check(settings, "_on_team_pressed",
			"res://TeamMenu.tscn", "teams")
		ok = ok and await _nav_check(settings, "_on_hotkeys_pressed",
			"res://HotkeysMenu.tscn", "controls")
		ok = ok and await _nav_check(settings, "_on_debug_pressed",
			"res://DebugMenu.tscn", "debug")

		# --- DebugMenu: switches carry the persisted state, flips save. ---
		var debug_menu: Node = load("res://DebugMenu.tscn").instantiate()
		add_child(debug_menu)
		await get_tree().process_frame
		var debug_check: CheckButton = debug_menu.get_node("%DebugCheck")
		var gravity_check: CheckButton = \
			debug_menu.get_node("%GravityFieldCheck")
		var state_ok: bool = debug_check.button_pressed \
			== GameConfig.debug_mode \
			and gravity_check.button_pressed \
			== GameConfig.debug_gravity_field
		var before_debug: bool = GameConfig.debug_mode
		var before_gravity: bool = GameConfig.debug_gravity_field
		debug_check.set_pressed_no_signal(not before_debug)
		debug_check.toggled.emit(not before_debug)
		gravity_check.set_pressed_no_signal(not before_gravity)
		gravity_check.toggled.emit(not before_gravity)
		GameConfig.load_settings()
		var persisted: bool = GameConfig.debug_mode == (not before_debug) \
			and GameConfig.debug_gravity_field == (not before_gravity)
		# Restore the original state for the other checks.
		debug_check.set_pressed_no_signal(before_debug)
		debug_check.toggled.emit(before_debug)
		gravity_check.set_pressed_no_signal(before_gravity)
		gravity_check.toggled.emit(before_gravity)
		print("SETTINGS debug_state=", state_ok, " persisted=", persisted)
		ok = ok and state_ok and persisted

		# --- No gameplay state leak: menus never touch the level group. ---
		var leak: bool = not get_tree().get_nodes_in_group(
			"level").is_empty()
		print("SETTINGS level_group_empty=", not leak)
		ok = ok and not leak
		debug_menu.queue_free()
		settings.queue_free()
		await get_tree().process_frame

		# --- Overlay mode (issue #304): Debug opens as a submenu on top,
		# Back returns to the settings screen without a scene change. ---
		var overlay: Node = load("res://SettingsMenu.tscn").instantiate()
		overlay.set("in_game", true)
		add_child(overlay)
		await get_tree().process_frame
		overlay._on_debug_pressed()
		await get_tree().process_frame
		var submenu: Node = overlay.get("_submenu")
		var overlay_ok: bool = submenu != null \
			and submenu.is_inside_tree() \
			and submenu.get("in_game") == true
		var shadow_ok: bool = overlay_ok \
			and not overlay.get_node("Shadow").visible \
			and submenu.get_node("Shadow").visible
		submenu._on_back_pressed()
		await get_tree().process_frame
		await get_tree().process_frame
		var back_ok: bool = overlay.get("_submenu") == null \
			and not is_instance_valid(submenu)
		print("SETTINGS debug_overlay=", overlay_ok, " shadow=", shadow_ok,
			" back=", back_ok)
		ok = ok and overlay_ok and shadow_ok and back_ok
		overlay.queue_free()

		print("SETTINGS ok=", ok)
		done.emit(ok)


	func _nav_check(menu: Node, method: String, expected: String,
			tag: String) -> bool:
		menu.call(method)
		for i in 3:
			await get_tree().process_frame
		var went: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == expected
		print("SETTINGS ", tag, " -> ", expected.get_file(), " ok=", went)
		return went
