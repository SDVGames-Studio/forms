extends Node
## Level-editor UI checks (issues #464 and #632): scene structure
## (four tool toggles in one group, the five SHAPE toggles of the
## #632 palette in their own group, canvas with the
## LevelEditorCanvas script, shared theme), tool and shape button
## wiring, a full save -> clear -> load JSON round-trip through
## user://levels/ (rectangles AND every #632 shape), the issue #633
## ground PICTURE (embeds in the JSON, round-trips, fills the built
## ground and survives destructible carving), a CustomLevel
## build of all the shapes into playable ground, and BACK navigation
## to the main menu.
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

	## A level file authored with every #632 shape — the input for the
	## CustomLevel build check (issue #633: with an embedded picture).
	func _write_shapes_level(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({
			"format": "forms-level/1", "name": TEST_SHAPES,
			"pieces": [
				{"kind": "indestructible", "shape": "rect",
					"x": 0.0, "y": 504.0, "w": 1152.0, "h": 144.0},
				{"kind": "indestructible", "shape": "circle",
					"x": 448.0, "y": 96.0, "w": 256.0, "h": 256.0},
				{"kind": "indestructible", "shape": "tri",
					"x": 96.0, "y": 288.0, "w": 256.0, "h": 192.0},
				{"kind": "indestructible", "shape": "loop",
					"points": [{"x": 640.0, "y": 288.0},
						{"x": 864.0, "y": 288.0},
						{"x": 864.0, "y": 480.0},
						{"x": 640.0, "y": 480.0}]},
				{"kind": "destructible", "shape": "curve",
					"points": [{"x": 160.0, "y": 448.0},
						{"x": 480.0, "y": 448.0},
						{"x": 320.0, "y": 320.0}]},
				{"kind": "destructible", "shape": "circle",
					"x": 900.0, "y": 100.0, "w": 192.0, "h": 192.0},
				{"kind": "destructible", "shape": "loop",
					"points": [{"x": 64.0, "y": 64.0},
						{"x": 320.0, "y": 64.0},
						{"x": 320.0, "y": 224.0},
						{"x": 192.0, "y": 128.0},
						{"x": 64.0, "y": 224.0}]},
			],
			"spawns": [{"x": 200.0, "y": 200.0}, {"x": 400.0, "y": 200.0},
				{"x": 600.0, "y": 200.0}, {"x": 800.0, "y": 200.0}],
			"picture": {"name": "tiny.png", "png": _tiny_picture_b64()},
		}, "  "))
		file.close()

	## Issue #633: an 8x8 PNG (base64) standing in for a chosen picture.
	func _tiny_picture_b64() -> String:
		var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.8, 0.4, 0.2, 1.0))
		return Marshalls.raw_to_base64(image.save_png_to_buffer())

	## Emits are received by an alive node (this driver), so quit always
	## lands — see _ready.
	func _on_done(ok: bool) -> void:
		get_tree().quit(0 if ok else 1)

	const TEST_NAME := "issue464_roundtrip"
	const TEST_SHAPES := "issue632_shapes"
	const TEST_PIC := "issue633_picture"
	const SHAPE_TOOLS := {
		"rect": "%RectTool", "tri": "%TriangleTool",
		"circle": "%CircleTool", "loop": "%LoopTool",
		"curve": "%CurveTool",
	}

	func run() -> void:
		var ok := true
		var editor: Node = load("res://scenes/menus/LevelEditor.tscn").instantiate()
		add_child(editor)
		await get_tree().process_frame

		# --- Structure: unique-name nodes, canvas script, theme. ---
		for unique in ["IndestructibleTool", "DestructibleTool",
				"SpawnTool", "EraseTool", "RectTool", "TriangleTool",
				"CircleTool", "LoopTool", "CurveTool", "EditorCanvas",
				"FileNameEdit", "SaveButton", "LoadButton", "FileSelect",
				"ClearButton", "BackButton", "StatusText",
				"PictureButton", "NoPictureButton", "PictureDialog"]:
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

		# --- Issue #632: shape toggles share their own group + wiring. ---
		var shape_toggles := true
		var shape_group: ButtonGroup = null
		for key in SHAPE_TOOLS.keys():
			var b := editor.get_node(SHAPE_TOOLS[key]) as BaseButton
			shape_toggles = shape_toggles and b != null and b.toggle_mode \
				and b.button_group != null
			if b != null and b.button_group != null:
				if shape_group == null:
					shape_group = b.button_group
				shape_toggles = shape_toggles \
						and b.button_group == shape_group
		print("LEVELEDITOR shape_toggles=", shape_toggles)
		ok = ok and shape_toggles
		var shape_wiring := true
		for key in SHAPE_TOOLS.keys():
			(editor.get_node(SHAPE_TOOLS[key]) as BaseButton).pressed.emit()
			shape_wiring = shape_wiring and canvas.get_shape() == key
		print("LEVELEDITOR shape_wiring=", shape_wiring)
		ok = ok and shape_wiring

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
				and (level.get("spawns") as Array).size() == 3 \
				and not level.has("picture")
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

		# --- Issue #632: every shape saves to JSON and loads back. ---
		var editor_s: Node = load("res://scenes/menus/LevelEditor.tscn").instantiate()
		add_child(editor_s)
		await get_tree().process_frame
		var canvas_s: Control = editor_s.get_node("%EditorCanvas") as Control
		var shape_pieces: Array = [
			{"kind": "indestructible", "shape": "rect",
				"rect": Rect2(Vector2(96.0, 480.0), Vector2(960.0, 128.0))},
			{"kind": "indestructible", "shape": "tri",
				"rect": Rect2(Vector2(128.0, 256.0), Vector2(256.0, 192.0))},
			{"kind": "indestructible", "shape": "circle",
				"rect": Rect2(Vector2(704.0, 160.0), Vector2(256.0, 256.0))},
			{"kind": "destructible", "shape": "loop",
				"points": PackedVector2Array([Vector2(640.0, 320.0),
					Vector2(832.0, 320.0), Vector2(832.0, 512.0),
					Vector2(640.0, 512.0)])},
			{"kind": "destructible", "shape": "curve",
				"points": PackedVector2Array([Vector2(160.0, 448.0),
					Vector2(480.0, 448.0), Vector2(320.0, 320.0)])},
		]
		canvas_s.set_pieces(shape_pieces)
		(editor_s.get_node("%FileNameEdit") as LineEdit).text = TEST_SHAPES
		(editor_s.get_node("%SaveButton") as Button).pressed.emit()
		await get_tree().process_frame
		var shapes_path := "user://levels/%s.json" % TEST_SHAPES
		var shapes_json := false
		var parsed_s = JSON.parse_string(
			FileAccess.get_file_as_string(shapes_path))
		if typeof(parsed_s) == TYPE_DICTIONARY:
			var lvl: Dictionary = parsed_s
			var ps: Array = lvl.get("pieces", [])
			shapes_json = ps.size() == 5
			if shapes_json:
				shapes_json = str(ps[1].get("shape", "")) == "tri" \
					and str(ps[2].get("shape", "")) == "circle" \
					and str(ps[3].get("shape", "")) == "loop" \
					and (ps[3].get("points") as Array).size() == 4 \
					and str(ps[4].get("shape", "")) == "curve" \
					and (ps[4].get("points") as Array).size() == 3
		print("LEVELEDITOR shapes_json=", shapes_json)
		ok = ok and shapes_json
		(editor_s.get_node("%ClearButton") as Button).pressed.emit()
		await get_tree().process_frame
		var select_s: OptionButton = editor_s.get_node("%FileSelect")
		var sel_s := -1
		for i in select_s.item_count:
			if select_s.get_item_text(i) == TEST_SHAPES:
				sel_s = i
		select_s.select(sel_s)
		(editor_s.get_node("%LoadButton") as Button).pressed.emit()
		await get_tree().process_frame
		var reloaded: Array = canvas_s.get_pieces()
		var shapes_roundtrip: bool = reloaded.size() == 5
		if shapes_roundtrip:
			shapes_roundtrip = \
					str(reloaded[0].get("shape", "")) == "rect" \
					and (reloaded[1]["rect"] as Rect2) \
					== (shape_pieces[1]["rect"] as Rect2) \
					and (reloaded[2]["rect"] as Rect2) \
					== (shape_pieces[2]["rect"] as Rect2) \
					and (reloaded[3]["points"] as PackedVector2Array) \
					== (shape_pieces[3]["points"] as PackedVector2Array) \
					and (reloaded[4]["points"] as PackedVector2Array) \
					== (shape_pieces[4]["points"] as PackedVector2Array)
		print("LEVELEDITOR shapes_roundtrip=", shapes_roundtrip)
		ok = ok and shapes_roundtrip
		editor_s.queue_free()
		DirAccess.remove_absolute(shapes_path)

		# --- Issue #633: the ground picture embeds and round-trips. ---
		var editor_p: Node = load("res://scenes/menus/LevelEditor.tscn").instantiate()
		add_child(editor_p)
		await get_tree().process_frame
		var canvas_p: Control = editor_p.get_node("%EditorCanvas") as Control
		var pic_bytes := Marshalls.base64_to_raw(_tiny_picture_b64())
		var pic_image := Image.new()
		pic_image.load_png_from_buffer(pic_bytes)
		canvas_p.set_ground_picture(
			ImageTexture.create_from_image(pic_image), "tiny.png", pic_bytes)
		canvas_p.set_pieces([{"kind": "destructible", "shape": "rect",
			"rect": Rect2(Vector2(256, 448), Vector2(256, 128))}])
		(editor_p.get_node("%FileNameEdit") as LineEdit).text = TEST_PIC
		(editor_p.get_node("%SaveButton") as Button).pressed.emit()
		await get_tree().process_frame
		var pic_path := "user://levels/%s.json" % TEST_PIC
		var pic_json := false
		var parsed_p = JSON.parse_string(
			FileAccess.get_file_as_string(pic_path))
		if typeof(parsed_p) == TYPE_DICTIONARY:
			var lvlp: Dictionary = parsed_p
			var pcp = lvlp.get("picture", {})
			pic_json = typeof(pcp) == TYPE_DICTIONARY \
				and str((pcp as Dictionary).get("name", "")) == "tiny.png" \
				and str((pcp as Dictionary).get("png", "")).length() > 32
		print("LEVELEDITOR picture_json=", pic_json)
		ok = ok and pic_json
		(editor_p.get_node("%NoPictureButton") as Button).pressed.emit()
		await get_tree().process_frame
		var no_pic: bool = not canvas_p.has_ground_picture()
		var select_p: OptionButton = editor_p.get_node("%FileSelect")
		var sel_p := -1
		for i in select_p.item_count:
			if select_p.get_item_text(i) == TEST_PIC:
				sel_p = i
		select_p.select(sel_p)
		(editor_p.get_node("%LoadButton") as Button).pressed.emit()
		await get_tree().process_frame
		var restored: Dictionary = canvas_p.get_ground_picture()
		var picture_roundtrip: bool = no_pic \
			and canvas_p.has_ground_picture() \
			and restored.get("name", "") == "tiny.png" \
			and (restored.get("png", PackedByteArray()) \
				as PackedByteArray) == pic_bytes \
			and restored.get("texture", null) is Texture2D
		print("LEVELEDITOR picture_roundtrip=", picture_roundtrip)
		ok = ok and picture_roundtrip
		editor_p.queue_free()
		DirAccess.remove_absolute(pic_path)

		# --- Issue #632: the shapes build PLAYABLE ground (CustomLevel).
		_write_shapes_level("user://levels/%s.json" % TEST_SHAPES)
		GameConfig.team_size = 3
		GameConfig.enemy_count = 2
		GameConfig.teams = GameConfig.default_teams()
		GameConfig.teams[0]["controller"] = "player"
		GameConfig.custom_level_name = TEST_SHAPES
		var level: Node = load("res://scenes/levels/CustomLevel.tscn").instantiate()
		add_child(level)
		await get_tree().process_frame
		var built := true
		var disc: CollisionShape2D = level.get_node_or_null(
			NodePath("Ground1/Shape")) as CollisionShape2D
		var disc_circle := (disc.shape if disc != null else null) as CircleShape2D
		built = built and disc_circle != null \
			and is_equal_approx(disc_circle.radius, 128.0)
		var tri_shape: CollisionPolygon2D = level.get_node_or_null(
			NodePath("Ground2/Shape")) as CollisionPolygon2D
		built = built and tri_shape != null and tri_shape.polygon.size() == 3
		var loop_shape: CollisionPolygon2D = level.get_node_or_null(
			NodePath("Ground3/Shape")) as CollisionPolygon2D
		built = built and loop_shape != null \
			and loop_shape.polygon.size() == 4
		var poly_chunks := 0
		for g in get_tree().get_nodes_in_group("destructible_ground"):
			if g.get_node_or_null(NodePath("Shape")) is CollisionPolygon2D:
				poly_chunks += 1
		built = built and poly_chunks >= 3 \
			and get_tree().get_nodes_in_group(
				"indestructible_ground").size() >= 4
		print("LEVELEDITOR shapes_build=", built)
		ok = ok and built

		# --- Issue #633: every built ground carries the picture. ---
		var pic_built := true
		for g in get_tree().get_nodes_in_group("destructible_ground") \
				+ get_tree().get_nodes_in_group("indestructible_ground"):
			pic_built = pic_built and g.get("picture") is Texture2D
		print("LEVELEDITOR picture_build=", pic_built)
		ok = ok and pic_built

		# --- Issue #633: a blast carves a pictured chunk — the surviving
		# pieces keep the picture (world-continuous mapping). ---
		var chunk: Node = null
		for g in get_tree().get_nodes_in_group("destructible_ground"):
			if g.get("picture") is Texture2D:
				chunk = g
			break
		var carve_pic := false
		if chunk != null:
			chunk.apply_blast(chunk.global_position, 60.0)
			await get_tree().process_frame
			var carved_pic := 0
			for g in get_tree().get_nodes_in_group("destructible_ground"):
				if g.get("picture") is Texture2D:
					carved_pic += 1
			carve_pic = carved_pic >= 2
		print("LEVELEDITOR picture_carve=", carve_pic)
		ok = ok and carve_pic

		level.queue_free()
		await get_tree().process_frame
		GameConfig.custom_level_name = ""
		DirAccess.remove_absolute("user://levels/%s.json" % TEST_SHAPES)

		# --- BACK -> main menu. ---
		var editor2: Node = load("res://scenes/menus/LevelEditor.tscn").instantiate()
		add_child(editor2)
		await get_tree().process_frame
		(editor2.get_node("%BackButton") as Button).pressed.emit()
		for i in 3:
			await get_tree().process_frame
		var went: bool = get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path \
			== "res://scenes/Main.tscn"
		print("LEVELEDITOR back_nav=", went)
		ok = ok and went

		print("LEVELEDITOR ok=", ok)
		done.emit(ok)
