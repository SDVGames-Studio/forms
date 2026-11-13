extends Node
## Audio-settings checks per issue #472 (docs/ui/main_menu.md §6.6):
## GameConfig volume statics persist through settings.cfg;
## apply_audio_settings() is wired at boot and on every change and
## drives the real AudioServer bus volumes (the buses exist in every
## run — headless sits on the dummy driver, but bus volumes are still
## assertable, unlike pixels); the Settings AUDIO category exists on
## every device and opens AudioMenu (standalone scene change + in-game
## overlay submenu); every slider reflects and updates the persisted
## state. Headless runs assert wiring and persistence, not sound.
##
## Run headless: godot --headless res://tests/test_audio_settings.tscn
## Exit code 0 = pass; the printed AUDIO ok= verdict is authoritative.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	var driver := AudioDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class AudioDriver extends Node:
	signal done(ok: bool)

	## Original state, restored at the end so the run leaves no trace in
	## the shared user://settings.cfg.
	var _orig_master := 1.0
	var _orig_music := 0.5
	var _orig_sfx := 1.0

	func run() -> void:
		var ok := true
		_orig_master = GameConfig.master_volume
		_orig_music = GameConfig.music_volume
		_orig_sfx = GameConfig.sfx_volume
		GameConfig.load_settings()

		# --- Defaults keep today's authored mix (spec §6.6: sensible
		## defaults; the statics are the documented contract). ---
		var defaults_ok: bool = is_equal_approx(
			GameConfig.master_volume, 1.0) \
			and is_equal_approx(GameConfig.music_volume, 0.5) \
			and is_equal_approx(GameConfig.sfx_volume, 1.0)
		print("AUDIO defaults_ok=", defaults_ok)
		ok = ok and defaults_ok

		# --- Persistence round-trip through settings.cfg. ---
		GameConfig.master_volume = 0.2
		GameConfig.music_volume = 0.4
		GameConfig.sfx_volume = 0.6
		GameConfig.save_settings()
		GameConfig.master_volume = 1.0
		GameConfig.music_volume = 1.0
		GameConfig.sfx_volume = 1.0
		GameConfig.load_settings()
		var persisted: bool = is_equal_approx(
			GameConfig.master_volume, 0.2) \
			and is_equal_approx(GameConfig.music_volume, 0.4) \
			and is_equal_approx(GameConfig.sfx_volume, 0.6)
		print("AUDIO persisted=", persisted)
		ok = ok and persisted

		# --- apply_audio_settings() drives the real bus volumes; 0 is
		## the -80 dB hard-mute floor (linear_to_db(0) is -INF). ---
		var master_idx := AudioServer.get_bus_index("Master")
		var music_idx := AudioServer.get_bus_index("Music")
		var sfx_idx := AudioServer.get_bus_index("SFX")
		var buses_ok: bool = master_idx >= 0 and music_idx >= 0 \
			and sfx_idx >= 0
		GameConfig.master_volume = 0.3
		GameConfig.music_volume = 0.0
		GameConfig.apply_audio_settings()
		var applied: bool = buses_ok \
			and is_equal_approx(AudioServer.get_bus_volume_db(master_idx),
				linear_to_db(0.3)) \
			and is_equal_approx(AudioServer.get_bus_volume_db(music_idx),
				-80.0) \
			and is_equal_approx(AudioServer.get_bus_volume_db(sfx_idx),
				linear_to_db(0.6))
		print("AUDIO buses=", buses_ok, " applied=", applied)
		ok = ok and applied

		# --- Settings category: AUDIO button exists, visible (also on
		## touch devices — audio matters everywhere), opens the screen
		## (standalone scene change). ---
		var settings: Node = load("res://scenes/menus/SettingsMenu.tscn").instantiate()
		add_child(settings)
		await get_tree().process_frame
		var audio_button: Button = settings.get_node_or_null("%AudioButton")
		var category_ok: bool = audio_button != null \
			and audio_button.text == "AUDIO" \
			and audio_button.visible
		print("AUDIO category=", category_ok)
		ok = ok and category_ok
		settings._on_audio_pressed()
		for i in 3:
			await get_tree().process_frame
		var opened: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path \
			== "res://scenes/menus/AudioMenu.tscn"
		print("AUDIO opens_screen=", opened)
		ok = ok and opened

		# --- The screen: sliders reflect the persisted state and every
		## change updates + persists + applies it. ---
		var menu: Node = load("res://scenes/menus/AudioMenu.tscn").instantiate()
		add_child(menu)
		await get_tree().process_frame
		var master_slider: HSlider = menu.get_node("%MasterSlider")
		var music_slider: HSlider = menu.get_node("%MusicSlider")
		var sfx_slider: HSlider = menu.get_node("%SfxSlider")
		var structure_ok: bool = master_slider.min_value == 0.0 \
			and master_slider.max_value == 1.0 \
			and is_equal_approx(master_slider.value,
				GameConfig.master_volume) \
			and is_equal_approx(music_slider.value,
				GameConfig.music_volume) \
			and is_equal_approx(sfx_slider.value, GameConfig.sfx_volume) \
			and menu.get_node("%MasterValue").text == "30%" \
			and menu.get_node("%MusicValue").text == "0%" \
			and menu.get_node("%SfxValue").text == "60%"
		print("AUDIO screen_structure=", structure_ok)
		ok = ok and structure_ok

		menu._on_master_changed(0.8)
		var change_applied: bool = is_equal_approx(
			GameConfig.master_volume, 0.8) \
			and is_equal_approx(AudioServer.get_bus_volume_db(master_idx),
				linear_to_db(0.8)) \
			and menu.get_node("%MasterValue").text == "80%"
		GameConfig.master_volume = 0.3
		GameConfig.load_settings()
		var change_persisted: bool = is_equal_approx(
			GameConfig.master_volume, 0.8)
		print("AUDIO change=", change_applied, " persisted=",
			change_persisted)
		ok = ok and change_applied and change_persisted
		menu.queue_free()
		settings.queue_free()
		await get_tree().process_frame

		# --- Overlay mode (issue #304): AUDIO opens as a submenu on
		## top of the settings screen, Back returns, shadow stays single. ---
		var overlay: Node = load("res://scenes/menus/SettingsMenu.tscn").instantiate()
		overlay.set("in_game", true)
		add_child(overlay)
		await get_tree().process_frame
		overlay._on_audio_pressed()
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
		print("AUDIO overlay=", overlay_ok, " shadow=", shadow_ok,
			" back=", back_ok)
		ok = ok and overlay_ok and shadow_ok and back_ok
		overlay.queue_free()

		# --- Restore the original persisted state. ---
		GameConfig.master_volume = _orig_master
		GameConfig.music_volume = _orig_music
		GameConfig.sfx_volume = _orig_sfx
		GameConfig.save_settings()
		GameConfig.apply_audio_settings()

		print("AUDIO ok=", ok)
		done.emit(ok)
