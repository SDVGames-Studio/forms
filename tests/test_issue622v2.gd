extends Node
## Issue #622 rework: PR #625's expand rework collapsed the LevelConfig
## menu's teams list — TeamsScroll expanded with NO expanding ancestor
## (Nav was SHRINK_CENTER, TeamsPanel min-height only), so its height
## fell to 0: the rows existed but were invisible ("there are no teams")
## and an added team was invisible too ("Add team doesn't work").
##
## This regression test drives the menu at several window sizes with a
## worst-case set (MAX_TEAMS teams) and asserts the teams list is
## actually VISIBLE: the scroll viewport is tall enough for a row, the
## first row shows inside it, and the Add team button is reachable on
## screen (enabled below the cap, disabled at it, and it really adds).
##
## Run headless: godot --headless res://tests/test_issue622v2.tscn
## Exit code 0 = pass; the printed 622V2 verdict is authoritative.

const SIZES := [
	Vector2i(1152, 648),  # desktop base (project default window)
	Vector2i(980, 809),   # the owner's report window
	Vector2i(960, 540),   # small landscape window
	Vector2i(640, 360),   # compact landscape window
]
const TOL := 0.5

func _ready() -> void:
	var driver := Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Driver extends Node:
	signal done(ok: bool)

	var _had_team_cfg := false
	var _team_cfg_backup: PackedByteArray = PackedByteArray()

	func run() -> void:
		var ok := true
		_backup_team_cfg()
		# Worst case: the set is at the cap (Add team disabled) — the
		# list is still fully visible and scrolling.
		GameConfig.teams = GameConfig.default_teams()
		while GameConfig.teams.size() < GameConfig.MAX_TEAMS:
			var team: Dictionary = GameConfig.teams[0].duplicate(true)
			team["label"] = "Team %d" % (GameConfig.teams.size() + 1)
			GameConfig.teams.append(team)
		GameConfig.save_teams()
		for size in SIZES:
			DisplayServer.window_set_size(size)
			await get_tree().process_frame
			await get_tree().process_frame
			var size_ok := await _check(size)
			ok = size_ok and ok
		_restore_team_cfg()
		done.emit(ok)

	## Instantiates the menu at the CURRENT window size and audits the
	## teams panel. Every wait lets the container layout settle.
	func _check(size: Vector2i) -> bool:
		var menu = load("res://scenes/menus/LevelConfigMenu.tscn").instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var failures: Array[String] = []
		var view: Rect2 = get_viewport().get_visible_rect()
		var scroll: ScrollContainer = menu.get_node(
			"Layout/Columns/Nav/TeamsPanel/TeamsBox/TeamsScroll")
		var list: VBoxContainer = scroll.get_node("TeamsList")
		var add: Button = menu.get_node(
			"Layout/Columns/Nav/TeamsPanel/TeamsBox/AddTeamButton")
		if list.get_child_count() != GameConfig.MAX_TEAMS:
			failures.append("expected %d rows, got %d" % [
				GameConfig.MAX_TEAMS, list.get_child_count()])
		# The scroll viewport must be tall enough to show at least one
		# row (a 0-height scroll was the #622 rework regression).
		if scroll.size.y < 40.0:
			failures.append("teams scroll height %.1f < 40" % scroll.size.y)
		# The first row must actually SHOW inside the scroll viewport:
		# it overlaps it vertically and sits inside the screen
		# horizontally.
		var row_rect: Rect2 = list.get_child(0).get_global_rect()
		var scroll_rect: Rect2 = scroll.get_global_rect()
		if row_rect.intersection(scroll_rect).size.y <= TOL:
			failures.append("row0 %s not visible in scroll %s" % [
				row_rect, scroll_rect])
		if not view.grow(TOL).encloses(
				Rect2(row_rect.position.x, view.position.y,
					row_rect.size.x, 0.0)):
			failures.append("row0 x-range %s outside view %s" % [
				row_rect, view])
		var add_center: Vector2 = add.get_global_rect().get_center()
		if not view.grow(TOL).has_point(add_center):
			failures.append("add button center %s off-screen %s" % [
				add_center, view])
		if not add.disabled:
			failures.append("add enabled at MAX_TEAMS")
		# Adding must WORK below the cap: remove one team, click Add,
		# the count grows back.
		menu._on_remove_team_pressed(0)
		await get_tree().process_frame
		if add.disabled:
			failures.append("add disabled below the cap")
		add.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
		if list.get_child_count() != GameConfig.MAX_TEAMS:
			failures.append("add below cap did not rebuild the list")
		menu.queue_free()
		var size_label := "%dx%d" % [size.x, size.y]
		if failures.is_empty():
			print("622V2 %s ok" % size_label)
		else:
			for failure in failures:
				push_error("622V2 %s FAIL: %s" % [size_label, failure])
		return failures.is_empty()

	func _backup_team_cfg() -> void:
		var file := FileAccess.open(GameConfig._SAVE_PATH, FileAccess.READ)
		if file != null:
			_team_cfg_backup = file.get_buffer(file.get_length())
			_had_team_cfg = true

	func _restore_team_cfg() -> void:
		if _had_team_cfg:
			var file := FileAccess.open(GameConfig._SAVE_PATH, FileAccess.WRITE)
			file.store_buffer(_team_cfg_backup)
		else:
			DirAccess.remove_absolute(GameConfig._SAVE_PATH)
