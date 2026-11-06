extends Node
## Main-menu UI checks per docs/ui/main_menu.md §11 (M1 scope):
## branding, exactly three primary options, footer version, shared
## theme, static background, no gameplay HUD leak ("level" group stays
## empty), and working NEW GAME / SETTINGS navigation. QUIT is checked
## last — the test process exits 0 when it fires (issue #303 pattern).
##
## Run headless: godot --headless res://tests/test_main_menu_ui.tscn
## Exit code 0 = pass; the printed MAINMENU ok= verdict is
## authoritative.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	var driver := MainMenuDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class MainMenuDriver extends Node:
	signal done(ok: bool)

	const EXPECTED_BUTTONS := ["NEW GAME", "SETTINGS", "QUIT"]


	func run() -> void:
		var ok := true
		var menu: Node = _fresh_main()
		await get_tree().process_frame

		# --- Structure (spec §4): branding + exactly three options. ---
		var buttons: Array = _all_buttons(menu)
		var labels: Array[String] = []
		for b in buttons:
			labels.append((b as Button).text)
		var three: bool = labels.size() == 3 \
			and labels == EXPECTED_BUTTONS
		print("MAINMENU buttons=", labels, " three=", three)
		ok = ok and three

		var title: Label = _find_label(menu, "FORMS")
		var subtitle: Label = _find_label(
			menu, "TACTICAL TURN-BASED COMBAT")
		print("MAINMENU branding=", title != null and subtitle != null)
		ok = ok and title != null and subtitle != null

		# --- Shared theme with visible focus state (spec §3, §4.4). ---
		var themed: bool = (menu as Control).theme != null
		var focus_style: StyleBox = (menu as Control).theme.get_stylebox(
			"focus", "Button") if themed else null
		print("MAINMENU theme=", themed, " focus_style=",
			focus_style != null)
		ok = ok and themed and focus_style != null

		# --- Footer version (spec §4.2; owner decision Q4). ---
		var version_label: Label = menu.get_node_or_null(
			"%VersionLabel") as Label
		var version_ok: bool = version_label != null \
			and version_label.text == "v0.1.0" \
			and ProjectSettings.get_setting(
				"application/config/version", "") == "0.1.0"
		print("MAINMENU version_ok=", version_ok)
		ok = ok and version_ok

		# --- Static background (spec §3.3): present, no animation. ---
		var bg: Node = menu.get_node_or_null("Background")
		var anims: Array = _all_of(menu, "AnimationPlayer")
		var static_ok: bool = bg != null \
			and bg.get_script() != null \
			and str(bg.get_script().resource_path).contains(
				"MenuBackground") \
			and anims.is_empty()
		print("MAINMENU background=", bg != null, " anim_players=",
			anims.size(), " static_ok=", static_ok)
		ok = ok and static_ok

		# --- No gameplay HUD / state leak (spec §7, §8.1). ---
		var hud_leak: bool = not get_tree().get_nodes_in_group(
			"level").is_empty()
		print("MAINMENU level_group_empty=", not hud_leak)
		ok = ok and not hud_leak
		menu.queue_free()
		await get_tree().process_frame

		# --- Navigation (spec §5): NEW GAME -> existing LevelsMenu. ---
		ok = ok and await _nav_check("%NewGameButton",
			"res://LevelsMenu.tscn", "new_game")
		# --- SETTINGS -> existing SettingsMenu (spec §6.4). ---
		ok = ok and await _nav_check("%SettingsButton",
			"res://SettingsMenu.tscn", "settings")

		print("MAINMENU ok=", ok)

		# --- QUIT: checked LAST — success exits the process (0). ---
		var quit_menu: Node = _fresh_main()
		add_child(quit_menu)
		await get_tree().process_frame
		quit_menu._on_quit_pressed()
		for i in 30:
			await get_tree().process_frame
		print("MAINMENU quit_fired=false")
		print("MAINMENU ok=false")
		done.emit(false)


	func _fresh_main() -> Node:
		return load("res://Main.tscn").instantiate()


	func _nav_check(button_path: String, expected: String,
			tag: String) -> bool:
		var menu: Node = _fresh_main()
		add_child(menu)
		await get_tree().process_frame
		var button: Button = menu.get_node(button_path) as Button
		button.pressed.emit()
		for i in 3:
			await get_tree().process_frame
		var went: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == expected
		print("MAINMENU ", tag, " -> ", expected.get_file(), " ok=", went)
		menu.queue_free()
		return went


	func _all_buttons(root: Node) -> Array:
		return _all_of(root, "Button")


	func _all_of(root: Node, classname: String) -> Array:
		var found: Array = []
		for child in root.find_children("*", classname, true, false):
			found.append(child)
		return found


	func _find_label(root: Node, text: String) -> Label:
		for node in _all_of(root, "Label"):
			var label := node as Label
			if label.text == text:
				return label
		return null
