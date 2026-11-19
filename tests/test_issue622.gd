extends Node
## Issue #622: check that all menu items in all menus fit on the screen.
## Instantiates EVERY menu scene (Main + scenes/menus family) at several
## window sizes (the canvas_items/expand stretch keeps the layout canvas
## at 1152x648 or larger, so the window classes also prove resize
## invariance) AND with worst-case dynamic content: 8 editor-saved
## custom levels in LevelConfigMenu's level drop-down (issue #643),
## 8 teams x 3 members in TeamMenu / LevelConfigMenu. Asserts every visible Control either fits inside
## the viewport rect or lives inside a ScrollContainer (reachable by
## scrolling) whose content fits its width (h-scroll is disabled by
## convention). Headless-safe: rects come from the container layout
## pass, not rendered pixels.
##
## Run headless: godot --headless res://tests/test_issue622.tscn
## Exit code 0 = pass; the printed FIT ok= verdict is authoritative.

func _ready() -> void:
	var driver := FitDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class FitDriver extends Node:
	signal done(ok: bool)

	const SIZES := [
		Vector2i(1152, 648),  # desktop base (project default window)
		Vector2i(960, 540),   # small landscape window
		Vector2i(640, 360),   # compact landscape window
	]
	const MENUS := [
		"res://scenes/Main.tscn",
		"res://scenes/menus/SettingsMenu.tscn",
		"res://scenes/menus/TeamMenu.tscn",
		"res://scenes/menus/HotkeysMenu.tscn",
		"res://scenes/menus/DebugMenu.tscn",
		"res://scenes/menus/GraphicsMenu.tscn",
		"res://scenes/menus/LevelConfigMenu.tscn",
		"res://scenes/menus/AudioMenu.tscn",
		"res://scenes/menus/LanMenu.tscn",
		"res://scenes/menus/LevelEditor.tscn",
	]
	const TOL := 0.5
	const LEVELS_DIR := "user://levels"
	const TEAM_CFG := "user://team.cfg"
	var _team_cfg_backup: PackedByteArray = PackedByteArray()
	var _had_team_cfg := false

	func run() -> void:
		var ok := true
		_seed_custom_levels(8)
		_seed_teams(8, 3)
		for menu_path in MENUS:
			var menu_name: String = menu_path.get_file()
			for size in SIZES:
				_set_window_size(size)
				await get_tree().process_frame
				var scene: Node = load(menu_path).instantiate()
				add_child(scene)
				# Two frames: enter tree + container sort.
				await get_tree().process_frame
				await get_tree().process_frame
				var offenders := _offenders(scene, false)
				if offenders.is_empty():
					print("FIT ", menu_name, " @", size.x, "x", size.y,
						" ok")
				else:
					ok = false
					print("FIT ", menu_name, " @", size.x, "x", size.y,
						" OVERFLOW ", offenders)
				scene.free()
				await get_tree().process_frame
		_clear_custom_levels()
		_restore_teams()
		print("FIT ok=", ok)
		done.emit(ok)

	func _set_window_size(size: Vector2i) -> void:
		DisplayServer.window_set_size(size)
		get_window().size = size

	## Worst case for the level drop-down (issue #643): N editor-saved
	## levels in user://levels joining the drop-down's list.
	func _seed_custom_levels(count: int) -> void:
		DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
		_clear_custom_levels()
		for i in count:
			var file := FileAccess.open(
				"%s/fit_test_%d.json" % [LEVELS_DIR, i], FileAccess.WRITE)
			if file != null:
				file.store_string("{}")
				file.close()

	func _clear_custom_levels() -> void:
		if DirAccess.dir_exists_absolute(LEVELS_DIR):
			for fname in DirAccess.get_files_at(LEVELS_DIR):
				if fname.begins_with("fit_test_"):
					DirAccess.remove_absolute(
						"%s/%s" % [LEVELS_DIR, fname])

	## Worst case for TeamMenu / LevelConfigMenu: the maximum set of
	## teams (GameConfig.MAX_TEAMS) with the maximum members each —
	## persisted like the real editor does, because the menus load the
	## set from disk in _ready().
	func _seed_teams(team_count: int, members: int) -> void:
		# Back up the developer's real team set first — the menus load
		# and SAVE this file, so the test must restore what was there.
		_had_team_cfg = FileAccess.file_exists(TEAM_CFG)
		if _had_team_cfg:
			_team_cfg_backup = FileAccess.get_file_as_bytes(TEAM_CFG)
		var teams: Array = []
		for t in team_count:
			var names: Array[String] = []
			for m in members:
				names.append("Member %d" % m)
			teams.append({
				"label": "Team %d" % (t + 1),
				"color": Color(0.9, 0.9, 0.2),
				"shape": "square",
				"names": names,
				"skill": 5,
				"friendly_fire": 0,
				"language": GameConfig.DEFAULT_LANGUAGE,
			})
		GameConfig.teams = teams
		GameConfig.save_teams()

	func _restore_teams() -> void:
		if _had_team_cfg:
			var file := FileAccess.open(TEAM_CFG, FileAccess.WRITE)
			if file != null:
				file.store_buffer(_team_cfg_backup)
				file.close()
		elif FileAccess.file_exists(TEAM_CFG):
			DirAccess.remove_absolute(TEAM_CFG)
		GameConfig.load_teams()

	## Visible Controls whose global rect leaves the viewport rect by
	## more than the tolerance. Content INSIDE a ScrollContainer is
	## reachable by scrolling, so it is exempt from the screen check —
	## but the scroll frame itself must fit, and its content's minimum
	## WIDTH must fit the frame (horizontal scrolling is disabled).
	func _offenders(node: Node, in_scroll: bool) -> Array[String]:
		var out: Array[String] = []
		_collect(node, in_scroll, out)
		return out

	func _collect(node: Node, in_scroll: bool, out: Array[String]) -> void:
		var vp := Rect2(Vector2.ZERO, Vector2(1152, 648))
		var root_control := node as Control
		if root_control != null and root_control.is_inside_tree():
			vp = root_control.get_viewport_rect()
		for child in node.get_children():
			var control := child as Control
			if control == null:
				continue
			if not control.visible:
				continue  # hidden items cannot overflow
			if not in_scroll:
				_outside(control, vp, out)
			var scroll := control as ScrollContainer
			if scroll != null:
				_scroll_width_ok(scroll, out)
				_collect(scroll, true, out)
			else:
				_collect(control, in_scroll, out)

	func _outside(control: Control, vp: Rect2, out: Array[String]) -> void:
		var rect := control.get_global_rect()
		var ox := maxf(rect.end.x - vp.end.x, vp.position.x - rect.position.x)
		var oy := maxf(rect.end.y - vp.end.y, vp.position.y - rect.position.y)
		if ox > TOL or oy > TOL:
			out.append("%s (%+.0f, %+.0f)" % [
				str(control.get_path()), maxf(ox, 0.0), maxf(oy, 0.0)])

	func _scroll_width_ok(scroll: ScrollContainer,
			out: Array[String]) -> void:
		for child in scroll.get_children():
			var content := child as Control
			if content == null:
				continue
			var over := content.get_combined_minimum_size().x \
				- scroll.size.x
			if over > TOL:
				out.append("%s content %+.0f wider than frame" % [
					str(scroll.get_path()), over])
