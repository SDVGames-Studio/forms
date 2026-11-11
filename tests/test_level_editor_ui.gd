extends Node
## Level-editor UI checks (issue #464): scene structure (four tool
## toggles in one group, canvas with the LevelEditorCanvas script,
## shared theme), tool-button wiring, a full save -> clear -> load
## JSON round-trip through user://levels/, and BACK navigation to the
## main menu.
##
## Run headless: godot --headless res://tests/test_level_editor_ui.tscn
## Exit code 0 = pass; the printed LEVELEDITOR ok= verdict is
## authoritative.

func _ready() -> void:
	# The driver must survive the scene changes it provokes, so it lives
	# directly under /root — change_scene_to_file only frees current_scene.
	# The quit handler lives ON the driver for the same reason: the BACK
	# check replaces (and frees) this test scene before done fires, and a
	# lambda owned by a freed node cannot quit the tree.
	var driver := LevelEditorDriver.new()
	driver.done.connect(driver._on_done)
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class LevelEditorDriver extends Node:
	signal done(ok: bool)

	## Emits are received by an alive node (this driver), so quit always
	## lands — see _ready.
	func _on_done(ok: bool) -> void:
		get_tree().quit(0 if ok else 1)

	const TEST_NAME := "issue464_roundtrip"

	func run() -> void:
		var ok := true
		var editor: Node = load("res://LevelEditor.tscn").instantiate()
		add_child(editor)
		await get_tree().process_frame

		# --- Structure: unique-name nodes, canvas script, theme. ---
		for unique in ["IndestructibleTool", "DestructibleTool",
				"SpawnTool", "EraseTool", "EditorCanvas", "FileNameEdit",
				"SaveButton", "LoadButton", "FileSelect", "ClearButton",
				"BackButton", "StatusText"]:
			var found: Node = editor.get_node_or_null("%" + unique)
			print("LEVELEDITOR node ", unique, " ok=", found != null)
			ok = ok and found != null
		var canvas: Control = editor.get_node("%EditorCanvas") as Control
		var canvas_script_ok: bool = canvas != null \
			and canvas.get_script() != null \
			and str(canvas.get_script().resource_path).contains(
				"LevelEditorCanvas")
		print("LEVELEDITOR canvas_script=", canvas_script_ok)
		ok = ok and canvas_script_ok
		var tool_toggles := true
		for unique in ["IndestructibleTool", "DestructibleTool",
				"SpawnTool", "EraseTool"]:
			var b := editor.get_node("%" + unique) as BaseButton
			tool_toggles = tool_toggles and b != null \
				and b.toggle_mode and b.button_group != null
		print("LEVELEDITOR tool_toggles=", tool_toggles)
		ok = ok and tool_toggles
		var themed: bool = (editor as Control).theme != null
		print("LEVELEDITOR theme=", themed)
		ok = ok and themed

		# --- Tool wiring: buttons switch the canvas tool. ---
		(editor.get_node("%SpawnTool") as BaseButton).pressed.emit()
		var tool_set: bool = canvas.get_tool() == "spawn"
		(editor.get_node("%IndestructibleTool") as BaseButton).pressed.emit()
		tool_set = tool_set and canvas.get_tool() == "indestructible"
		print("LEVELEDITOR tool_wiring=", tool_set)
		ok = ok and tool_set

		# --- Authoring data -> save. ---
		var pieces: Array = [
			{"kind": "indestructible",
				"rect": Rect2(Vector2(96, 480), Vector2(960, 128))},
			{"kind": "destructible",
				"rect": Rect2(Vector2(320, 288), Vector2(256, 96))},
		]
		var spawns: Array = [
			Vector2(224, 192), Vector2(768, 160), Vector2(576, 384)]
		canvas.set_pieces(pieces)
		canvas.set_spawns(spawns)
		var name_edit: LineEdit = editor.get_node("%FileNameEdit")
		name_edit.text = TEST_NAME
		(editor.get_node("%SaveButton") as Button).pressed.emit()
		await get_tree().process_frame

		var path := "user://levels/%s.json" % TEST_NAME
		var saved: bool = FileAccess.file_exists(path)
		print("LEVELEDITOR saved_file=", saved)
		ok = ok and saved
		var json_ok := false
		var parsed = JSON.parse_string(
			FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			var level: Dictionary = parsed
			json_ok = str(level.get("format", "")) == "forms-level/1" \
				and (level.get("pieces") as Array).size() == 2 \
				and (level.get("spawns") as Array).size() == 3
		print("LEVELEDITOR json=", json_ok)
		ok = ok and json_ok

		# --- Clear -> load round-trip. ---
		(editor.get_node("%ClearButton") as Button).pressed.emit()
		await get_tree().process_frame
		var cleared: bool = canvas.get_pieces().is_empty() \
			and canvas.get_spawns().is_empty()
		print("LEVELEDITOR cleared=", cleared)
		ok = ok and cleared
		var select: OptionButton = editor.get_node("%FileSelect")
		var selected_index := -1
		for i in select.item_count:
			if select.get_item_text(i) == TEST_NAME:
				selected_index = i
		select.select(selected_index)
		(editor.get_node("%LoadButton") as Button).pressed.emit()
		await get_tree().process_frame
		var loaded_pieces: Array = canvas.get_pieces()
		var loaded_spawns: Array = canvas.get_spawns()
		var roundtrip: bool = loaded_pieces.size() == 2 \
			and loaded_spawns.size() == 3 \
			and (loaded_pieces[0]["rect"] as Rect2) \
				== (pieces[0]["rect"] as Rect2) \
			and (loaded_pieces[1]["rect"] as Rect2) \
				== (pieces[1]["rect"] as Rect2) \
			and loaded_pieces[1]["kind"] == pieces[1]["kind"] \
			and (loaded_spawns[0] as Vector2) == spawns[0]
		print("LEVELEDITOR roundtrip=", roundtrip)
		ok = ok and roundtrip
		editor.queue_free()
		DirAccess.remove_absolute(path)

		# --- BACK -> main menu. ---
		var editor2: Node = load("res://LevelEditor.tscn").instantiate()
		add_child(editor2)
		await get_tree().process_frame
		(editor2.get_node("%BackButton") as Button).pressed.emit()
		for i in 3:
			await get_tree().process_frame
		var went: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path \
			== "res://Main.tscn"
		print("LEVELEDITOR back_nav=", went)
		ok = ok and went

		print("LEVELEDITOR ok=", ok)
		done.emit(ok)
