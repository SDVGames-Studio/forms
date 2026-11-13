extends Node
## Regression check for issue #303: the Escape key acts as the cancel
## button in every menu — Back on all navigation menus (levels, settings,
## team, level-config, hotkeys) and quit on the root main menu. The
## in-game pause menu already handled Escape (open/close).
##
## Run headless: godot --headless res://tests/test_issue303.tscn
## Exit code 0 = pass.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	var driver := Issue303Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue303Driver extends Node:
	signal done(ok: bool)

	## [menu scene, expected scene after Escape] — checked in order.
	const MENUS := [
		["res://scenes/menus/LevelsMenu.tscn", "res://scenes/Main.tscn"],
		["res://scenes/menus/SettingsMenu.tscn", "res://scenes/Main.tscn"],
		["res://scenes/menus/TeamMenu.tscn", "res://scenes/menus/SettingsMenu.tscn"],
		["res://scenes/menus/LevelConfigMenu.tscn", "res://scenes/menus/LevelsMenu.tscn"],
		["res://scenes/menus/HotkeysMenu.tscn", "res://scenes/menus/SettingsMenu.tscn"],
		# Main-menu spec M2 (Q1): the debug switches live under their own
		# category screen — Escape returns to the settings screen.
		["res://scenes/menus/DebugMenu.tscn", "res://scenes/menus/SettingsMenu.tscn"],
		# Main-menu spec M3 (§6.3): the graphics screen follows the same
		# Escape-as-Back rule.
		["res://scenes/menus/GraphicsMenu.tscn", "res://scenes/menus/SettingsMenu.tscn"],
	]


	func _esc() -> InputEventKey:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		return key


	func _feed(menu: Node, event: InputEvent) -> void:
		if menu.has_method("_input"):
			menu._input(event)
		elif menu.has_method("_unhandled_input"):
			menu._unhandled_input(event)


	func run() -> void:
		var ok := true

		# --- Navigation menus: Escape = Back (real scene change). ---
		for entry in MENUS:
			var menu: Node = load(entry[0]).instantiate()
			add_child(menu)
			await get_tree().process_frame
			_feed(menu, _esc())
			for i in 3:
				await get_tree().process_frame
			var went: bool = get_tree().current_scene != null \
				and get_tree().current_scene.scene_file_path == entry[1]
			print("ISSUE303 ", entry[0].get_file(), " -> ",
				entry[1].get_file(), " back=", went)
			ok = ok and went

		# --- In-game pause menu: Escape closes the open panel. ---
		var pause: Node = get_node_or_null("/root/InGameMenu")
		var panel: Control = pause.get("_panel") if pause != null else null
		if panel != null:
			panel.visible = true
			pause._unhandled_input(_esc())
			await get_tree().process_frame
			var closed: bool = not panel.visible
			print("ISSUE303 InGameMenu close=", closed)
			ok = ok and closed
		else:
			print("ISSUE303 InGameMenu panel_missing=true")
			ok = false

		print("ISSUE303 ok=", ok)

		# --- Root main menu: Escape = Quit — checked LAST. If the quit
		# fires, the process exits 0 right here; if it does not, the run
		# fails explicitly after a short grace period. ---
		var main_menu: Node = load("res://scenes/Main.tscn").instantiate()
		add_child(main_menu)
		await get_tree().process_frame
		main_menu._unhandled_input(_esc())
		for i in 30:
			await get_tree().process_frame
		print("ISSUE303 main_menu_quit=false")
		print("ISSUE303 ok=false")
		done.emit(false)
