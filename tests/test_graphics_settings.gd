extends Node
## Graphics-settings checks per docs/ui/main_menu.md §6.3 (milestone M3)
## + owner decision Q2: GameConfig display statics persist through
## settings.cfg; apply_display_settings() is wired at boot and on every
## change; the Settings GRAPHICS category exists and opens GraphicsMenu
## (standalone scene change + in-game overlay submenu); every control
## reflects and updates the persisted state. Headless runs sit on the
## dummy renderer — wiring and persistence are asserted, not pixels.
##
## Run headless: godot --headless res://tests/test_graphics_settings.tscn
## Exit code 0 = pass; the printed GRAPHICS ok= verdict is authoritative.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	var driver := GraphicsDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class GraphicsDriver extends Node:
	signal done(ok: bool)

	## Original state, restored at the end so the run leaves no trace in
	## the shared user://settings.cfg.
	var _orig_mode := 0
	var _orig_size := Vector2i.ZERO
	var _orig_vsync := true

	func run() -> void:
		var ok := true
		_orig_mode = GameConfig.display_mode
		_orig_size = GameConfig.window_size
		_orig_vsync = GameConfig.vsync
		GameConfig.load_settings()

		# --- Defaults keep today's behavior (spec §6.3: sensible
		## defaults; the statics are the documented contract). ---
		var defaults_ok: bool = GameConfig.display_mode == 0 \
			and GameConfig.vsync == true \
			and GameConfig.window_size == Vector2i(1152, 648)
		print("GRAPHICS defaults_ok=", defaults_ok)
		ok = ok and defaults_ok

		# --- Persistence round-trip through settings.cfg. ---
		GameConfig.display_mode = 1
		GameConfig.window_size = Vector2i(1920, 1080)
		GameConfig.vsync = false
		GameConfig.save_settings()
		GameConfig.display_mode = 0
		GameConfig.window_size = Vector2i(1152, 648)
		GameConfig.vsync = true
		GameConfig.load_settings()
		var persisted: bool = GameConfig.display_mode == 1 \
			and GameConfig.window_size == Vector2i(1920, 1080) \
			and GameConfig.vsync == false
		print("GRAPHICS persisted=", persisted)
		ok = ok and persisted

		# --- apply_display_settings() runs clean on the dummy renderer. ---
		GameConfig.apply_display_settings()
		print("GRAPHICS apply_no_error=true")

		# --- Q2: touch detection — false on this desktop/headless run
		## (CI is linux; the true branch is a device-only path). ---
		var touch: bool = GameConfig.is_touch_device()
		print("GRAPHICS is_touch_device=", touch)
		ok = ok and not touch

		# --- Settings category: GRAPHICS button exists, visible on
		## desktop, opens the screen (standalone scene change). ---
		var settings: Node = load("res://SettingsMenu.tscn").instantiate()
		add_child(settings)
		await get_tree().process_frame
		var graphics_button: Button = \
			settings.get_node_or_null("%GraphicsButton")
		var category_ok: bool = graphics_button != null \
			and graphics_button.text == "GRAPHICS" \
			and graphics_button.visible
		print("GRAPHICS category=", category_ok)
		ok = ok and category_ok
		settings._on_graphics_pressed()
		for i in 3:
			await get_tree().process_frame
		var opened: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path \
			== "res://GraphicsMenu.tscn"
		print("GRAPHICS opens_screen=", opened)
		ok = ok and opened

		# --- The screen: controls reflect the persisted state and every
		## change updates + persists it. ---
		var menu: Node = load("res://GraphicsMenu.tscn").instantiate()
		add_child(menu)
		await get_tree().process_frame
		var mode_option: OptionButton = menu.get_node("%DisplayModeOption")
		var resolution_option: OptionButton = \
			menu.get_node("%ResolutionOption")
		var vsync_check: CheckButton = menu.get_node("%VSyncCheck")
		var structure_ok: bool = mode_option.item_count == 2 \
			and mode_option.get_item_text(0) == "WINDOWED" \
			and mode_option.get_item_text(1) == "FULLSCREEN" \
			and resolution_option.item_count >= 5 \
			and vsync_check.button_pressed == GameConfig.vsync \
			and mode_option.selected == GameConfig.display_mode
		print("GRAPHICS screen_structure=", structure_ok)
		ok = ok and structure_ok

		menu._on_mode_selected(0)
		var mode_applied: bool = GameConfig.display_mode == 0 \
			and not resolution_option.disabled
		menu._on_resolution_selected(_preset_index(menu, Vector2i(1600, 900)))
		var resolution_applied: bool = \
			GameConfig.window_size == Vector2i(1600, 900)
		menu._on_vsync_toggled(true)
		var vsync_applied: bool = GameConfig.vsync == true
		menu._on_mode_selected(1)
		var fullscreen_gates: bool = GameConfig.display_mode == 1 \
			and resolution_option.disabled
		print("GRAPHICS changes=", mode_applied, " ", resolution_applied,
			" ", vsync_applied, " ", fullscreen_gates)
		ok = ok and mode_applied and resolution_applied and vsync_applied \
			and fullscreen_gates

		# --- Overlay mode (issue #304): GRAPHICS opens as a submenu on
		## top of the settings screen, Back returns, shadow stays single. ---
		var overlay: Node = load("res://SettingsMenu.tscn").instantiate()
		overlay.set("in_game", true)
		add_child(overlay)
		await get_tree().process_frame
		overlay._on_graphics_pressed()
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
		print("GRAPHICS overlay=", overlay_ok, " shadow=", shadow_ok,
			" back=", back_ok)
		ok = ok and overlay_ok and shadow_ok and back_ok
		overlay.queue_free()
		menu.queue_free()

		# --- Restore the original persisted state. ---
		GameConfig.display_mode = _orig_mode
		GameConfig.window_size = _orig_size
		GameConfig.vsync = _orig_vsync
		GameConfig.save_settings()

		print("GRAPHICS ok=", ok)
		done.emit(ok)


	func _preset_index(menu: Node, size: Vector2i) -> int:
		var entries: Array = menu.get("_resolution_entries")
		return entries.find(size)
