extends Node
## Menu adaptation checks — docs/ui/main_menu.md §9, milestone M4
## hardening (2026-11-14): the MenuAdapt tables behave monotonically and
## clamp sanely; every #348 template screen adapts at small widths
## (tighter margins + column gap, smaller title, subtitle/accent rule
## yield their space, nav buttons slim) and restores the desktop look
## at the base width; no template screen pollutes the gameplay "level"
## group. Headless asserts layout STATE, not rendered pixels.
##
## Run headless: godot --headless res://tests/test_menu_adaptation.tscn
## Exit code 0 = pass; the printed ADAPT ok= verdict is authoritative.

func _ready() -> void:
	var driver := MenuAdaptDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class MenuAdaptDriver extends Node:
	signal done(ok: bool)

	const TEMPLATE_SCENES := [
		"res://scenes/Main.tscn",
		"res://scenes/menus/SettingsMenu.tscn",
		"res://scenes/menus/TeamMenu.tscn",
		"res://scenes/menus/HotkeysMenu.tscn",
		"res://scenes/menus/DebugMenu.tscn",
		"res://scenes/menus/GraphicsMenu.tscn",
		"res://scenes/menus/LevelsMenu.tscn",
		"res://scenes/menus/LevelConfigMenu.tscn",
		"res://scenes/menus/AudioMenu.tscn",
	]

	func run() -> void:
		var ok := true

		# --- Adaptation tables (pure logic, deterministic). ---
		var tables_ok := MenuAdapt.margins(1920.0) == 72 \
			and MenuAdapt.margins(1152.0) == 72 \
			and MenuAdapt.margins(640.0) == 40 \
			and MenuAdapt.margins(360.0) == 23 \
			and MenuAdapt.margins(120.0) == 16 \
			and MenuAdapt.title_size(1152.0) == 96 \
			and MenuAdapt.title_size(900.0) == 72 \
			and MenuAdapt.title_size(640.0) == 56 \
			and MenuAdapt.separation(1152.0) == 64 \
			and MenuAdapt.separation(900.0) == 32 \
			and MenuAdapt.separation(640.0) == 24 \
			and MenuAdapt.nav_width(1152.0) == 340 \
			and MenuAdapt.nav_width(900.0) == 300 \
			and MenuAdapt.nav_width(640.0) == 264 \
			and MenuAdapt.compact(640.0) \
			and not MenuAdapt.compact(800.0)
		print("ADAPT tables_ok=", tables_ok)
		ok = ok and tables_ok

		# --- Desktop behavior unchanged at the base width. ---
		var main: Control = load(TEMPLATE_SCENES[0]).instantiate()
		add_child(main)
		await get_tree().process_frame
		var desktop_ok: bool = _margins_of(main) == 72 \
			and _title_size_of(main) == 96 \
			and _subtitle_visible(main) \
			and main.get_node(
				"Layout/Columns/Nav").get_child(
				0).custom_minimum_size.x == 340
		print("ADAPT desktop=", desktop_ok)
		ok = ok and desktop_ok

		# --- Small-landscape adaptation on Main (640 px class). ---
		MenuAdapt.apply(main, 640.0)
		var small_ok: bool = _margins_of(main) == 40 \
			and _title_size_of(main) == 56 \
			and not _subtitle_visible(main) \
			and main.get_node(
				"Layout/Columns/Nav").get_child(
				0).custom_minimum_size.x == 264
		# And it restores when the width grows again (explicit width,
		# sticky semantics).
		MenuAdapt.apply(main, 1152.0)
		var restored: bool = _margins_of(main) == 72 \
			and _title_size_of(main) == 96 \
			and _subtitle_visible(main)
		print("ADAPT small=", small_ok, " restored=", restored)
		ok = ok and small_ok and restored
		main.queue_free()
		await get_tree().process_frame

		# --- Every template screen adapts and stays group-clean. ---
		for path in TEMPLATE_SCENES:
			var menu: Control = load(path).instantiate()
			add_child(menu)
			await get_tree().process_frame
			MenuAdapt.apply(menu, 640.0)
			# The forced width is sticky in MenuAdapt — deferred `resized`
			# signals (screens settle at different times) re-apply 640, so a
			# single settle frame before asserting is deterministic.
			await get_tree().process_frame
			var adapted: bool = _margins_of(menu) == 40 \
				and _title_size_of(menu) == 56 \
				and not _subtitle_visible(menu)
			var clean: bool = \
				get_tree().get_nodes_in_group("level").is_empty()
			print("ADAPT ", path.get_file(), " adapted=", adapted,
				" group_clean=", clean)
			ok = ok and adapted and clean
			menu.queue_free()
			await get_tree().process_frame

		print("ADAPT ok=", ok)
		done.emit(ok)


	func _margins_of(menu: Control) -> int:
		var layout := menu.get_node("Layout") as MarginContainer
		return layout.get_theme_constant("margin_left")


	func _title_size_of(menu: Control) -> int:
		return (menu.get_node(
			"Layout/Columns/Brand/Title") as Label).get_theme_font_size(
			"font_size")


	func _subtitle_visible(menu: Control) -> bool:
		var subtitle := menu.get_node_or_null(
			"Layout/Columns/Brand/Subtitle") as Control
		return subtitle != null and subtitle.visible
