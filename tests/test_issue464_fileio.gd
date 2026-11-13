extends Node
## Issue #464 rework regression checks — the editor's file round-trip
## and custom levels in the game flow:
##  - SAVE writes user://levels/<name>.json, remembers the open file
##    and writes CHANGES back to it; a new name creates a new level;
##  - a level file from outside user://levels loads into the canvas
##    (LOAD FILE…) and becomes the file SAVE updates in place;
##  - DOWNLOAD (_save_to_path) exports a copy to any path;
##  - the levels menu shows every saved level under CUSTOM LEVELS and
##    a click routes to the level config menu with the custom level
##    picked (CustomLevel.tscn);
##  - CustomLevel.tscn builds a PLAYABLE scene from the JSON: ground
##    groups, a player team with camera and weapons, the computer
##    team trimmed by GameConfig (enemy_count), spawn points honored.
##
## Run headless: godot --headless res://tests/test_issue464_fileio.tscn
## Exit code 0 = pass; the printed ISSUE464F verdict is authoritative.
##
## The driver lives directly under /root (not as the current scene):
## the levels-menu check provokes a real scene change, which frees the
## current scene — the driver must survive it.

func _ready() -> void:
	var driver := Driver.new()
	# The quit handler lives ON the driver: the levels-menu check
	# provokes a real scene change that frees this test scene, and a
	# lambda owned by a freed node cannot quit the tree.
	driver.done.connect(driver._on_done)
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Driver extends Node:
	signal done(ok: bool)

	## Emits are received by an alive node (this driver), so quit
	## always lands — see the outer scene's _ready.
	func _on_done(ok: bool) -> void:
		get_tree().quit(0 if ok else 1)

	const LEVELS_DIR := "user://levels"
	const TEST_STEM := "issue464_fileio"
	const TEST_STEM2 := "issue464_fileio_new"

	var _fails: Array = []

	func _check(what: String, ok: bool) -> void:
		if not ok:
			_fails.append(what)
		print("ISSUE464F %s — %s" % ["ok" if ok else "FAIL", what])

	func _rm(path: String) -> void:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	func _write_pieces(editor: Node, count: int) -> void:
		var canvas: Node = editor.get_node("%EditorCanvas")
		var pieces: Array = []
		for i in count:
			pieces.append({
				"kind": "indestructible" if i % 2 == 0 else "destructible",
				"rect": Rect2(Vector2(64.0 + 96.0 * i, 320.0),
					Vector2(128.0, 64.0)),
			})
		canvas.set_pieces(pieces)
		canvas.set_spawns([Vector2(200.0, 200.0), Vector2(400.0, 200.0),
			Vector2(600.0, 200.0), Vector2(800.0, 200.0)])

	func _piece_count(path: String) -> int:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			return -1
		return (parsed as Dictionary).get("pieces", []).size()

	func run() -> void:
		_rm("%s/%s.json" % [LEVELS_DIR, TEST_STEM])
		_rm("%s/%s.json" % [LEVELS_DIR, TEST_STEM2])
		_rm("user://issue464_export.json")
		_rm("user://issue464_external.json")
		await _test_editor_file_io()
		await _test_levels_menu()
		await _test_custom_level()
		_rm("%s/%s.json" % [LEVELS_DIR, TEST_STEM])
		_rm("%s/%s.json" % [LEVELS_DIR, TEST_STEM2])
		_rm("user://issue464_export.json")
		_rm("user://issue464_external.json")
		print("ISSUE464F verdict ok=%d fails=%d" % [
			int(_fails.is_empty()), _fails.size()])
		done.emit(_fails.is_empty())

	## Editor: save → re-save in place → save under a new name → load
	## an external file → export a copy (download).
	func _test_editor_file_io() -> void:
		var editor: Node = load("res://scenes/menus/LevelEditor.tscn").instantiate()
		add_child(editor)
		await get_tree().process_frame
		var path := "%s/%s.json" % [LEVELS_DIR, TEST_STEM]
		# First save: creates the file under the written name.
		editor._file_name_edit.text = TEST_STEM.replace("_", " ")
		_write_pieces(editor, 2)
		editor._on_save_pressed()
		_check("first save creates user://levels file",
			FileAccess.file_exists(path) and _piece_count(path) == 2)
		# Second save with the SAME name: writes the changes back to
		# the open file (in place).
		_write_pieces(editor, 3)
		editor._on_save_pressed()
		_check("save writes changes back to the open file",
			_piece_count(path) == 3)
		_check("open file is remembered", editor._current_path == path)
		# A NEW name creates a new level instead.
		editor._file_name_edit.text = TEST_STEM2.replace("_", " ")
		_write_pieces(editor, 1)
		editor._on_save_pressed()
		var path2 := "%s/%s.json" % [LEVELS_DIR, TEST_STEM2]
		_check("new name creates a new level",
			FileAccess.file_exists(path2) and _piece_count(path2) == 1)
		_check("old level untouched by the new save",
			_piece_count(path) == 3)
		# LOAD FILE…: a level from outside user://levels loads, and
		# SAVE then updates THAT file in place.
		var external := "user://issue464_external.json"
		var file := FileAccess.open(external, FileAccess.WRITE)
		file.store_string(JSON.stringify({
			"format": "forms-level/1", "name": "external",
			"pieces": [{"kind": "destructible", "x": 100.0, "y": 100.0,
				"w": 256.0, "h": 96.0}],
			"spawns": [{"x": 150.0, "y": 80.0}],
		}))
		file.close()
		_check("external file loads", editor._load_from_path(external))
		var canvas: Node = editor.get_node("%EditorCanvas")
		_check("load fills the canvas",
			canvas.get_pieces().size() == 1
			and canvas.get_spawns().size() == 1)
		_write_pieces(editor, 4)
		editor._on_save_pressed()
		_check("save updates the loaded external file in place",
			editor._current_path == external
			and _piece_count(external) == 4)
		# DOWNLOAD: export a copy; the open file is untouched.
		_check("download exports a copy",
			editor._save_to_path(
				"user://issue464_export.json", "export copy"))
		_check("export copy holds the level",
			_piece_count("user://issue464_export.json") == 4
			and editor._current_path == external)
		editor.queue_free()
		await get_tree().process_frame

	## Levels menu: saved levels appear under CUSTOM LEVELS and route
	## to the level config menu with the custom level picked.
	func _test_levels_menu() -> void:
		GameConfig.custom_level_name = ""
		GameConfig.level_path = ""
		var menu: Node = load("res://scenes/menus/LevelsMenu.tscn").instantiate()
		add_child(menu)
		await get_tree().process_frame
		var box: Node = menu.get_node("%CustomLevels")
		var buttons: Array = []
		for child in box.get_children():
			if child is Button:
				buttons.append(child)
		_check("custom levels section is visible with saved files",
			box.visible and not buttons.is_empty())
		var found := false
		for button in buttons:
			if (button as Button).text.contains("issue464 fileio"):
				found = true
		_check("saved editor level is listed", found)
		# The real handler: changes the scene to the level config menu.
		menu._on_custom_level_pressed(TEST_STEM)
		await get_tree().process_frame
		_check("custom level click routes to level config",
			GameConfig.custom_level_name == TEST_STEM
			and GameConfig.level_path == "res://scenes/levels/CustomLevel.tscn"
			and get_tree().current_scene != null
			and get_tree().current_scene.name == "LevelConfigMenu")
		if get_tree().current_scene != null:
			get_tree().current_scene.queue_free()
		GameConfig.custom_level_name = ""
		GameConfig.level_path = ""

	## CustomLevel: the JSON becomes a playable level — ground groups,
	## teams with weapons/camera, GameConfig trimming, spawn points.
	func _test_custom_level() -> void:
		GameConfig.team_size = 3
		GameConfig.enemy_count = 2
		GameConfig.custom_level_name = TEST_STEM
		var level: Node = load("res://scenes/levels/CustomLevel.tscn").instantiate()
		add_child(level)
		# Position snapshot BEFORE any physics frame — gravity starts
		# pulling the figure down the moment the tree starts stepping.
		var hero := level.get_node_or_null(NodePath("Player"))
		var spawn_at: Vector2 = hero.position \
				if hero != null else Vector2(-9999.0, -9999.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var tree := get_tree()
		_check("ground groups built",
			not tree.get_nodes_in_group("indestructible_ground").is_empty()
			and not tree.get_nodes_in_group("destructible_ground").is_empty())
		var player_team := tree.get_nodes_in_group("player_team")
		var enemy_team := tree.get_nodes_in_group("enemy_team")
		_check("player team of three", player_team.size() == 3)
		for member in player_team:
			var figure := member as Node
			_check("%s carries a weapon" % figure.name,
				figure.get_node_or_null(NodePath("Weapon")) != null)
		# The hero was captured right after the build above (before any
		# physics frame could pull it off its spawn point).
		_check("hero holds the shared zoom camera",
			hero != null
			and hero.get_node_or_null(NodePath("Camera")) != null
			and not tree.get_nodes_in_group("player_camera").is_empty())
		_check("computer team trimmed to enemy_count",
			enemy_team.size() == 2
			and level.get_node_or_null(NodePath("Npc3")) == null)
		_check("spawn points honored",
			spawn_at.distance_to(Vector2(200.0, 200.0)) < 0.5)
		level.queue_free()
		await get_tree().process_frame
		GameConfig.custom_level_name = ""
