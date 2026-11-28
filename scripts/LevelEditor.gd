extends Control
## Level editor for Forms (issue #464).
##
## Opened from the main menu's LEVEL EDITOR button. A grid canvas for
## authoring skirmish maps with the same shapes the levels use —
## indestructible gravity slabs (purple), destructible dirt (brown)
## and player spawn points — plus export/import of the result as a
## JSON level file under user://levels/.
##
## Issue #640: the EDIT POINTS tool now also ADDS points — a click on
## a figure's outline inserts a vertex there (see LevelEditorCanvas);
##
## Issue #464 rework (file round-trip):
##  - SAVE keeps writing user://levels/<name>.json — the files the
##    levels menu turns into playable levels (CustomLevel.tscn) — but
##    now remembers the open file: saving again writes the changes
##    back to THAT file, and typing a new name creates a new level;
##  - LOAD FILE… opens any forms level file from the user's own
##    filesystem (not only user://levels) into the canvas;
##  - DOWNLOAD exports a copy of the current level file to a path the
##    user picks, so built maps can be shared.
##
## Issue #632: the SHAPE palette — a second button row under the
## canvas (RECTANGLE / TRIANGLE / CIRCLE / LOOP / CURVE) that
## combines with the ground tools: rectangle and triangle drag their
## bounding box, circle drags centre-to-edge, loop clicks vertices
## (clicking the marked first vertex closes it) and curve clicks
## start, end and bend. Rect/tri/circle serialise as the {x,y,w,h}
## box; loop/curve store their clicked points.
##
## Issue #673: the BRUSH shape joins the palette — a click-drag
## stroke paints ground cell by cell (one 32 px grid cell per step)
## in the ground kind the tool column selects; a cell paints only
## where no piece covers it yet (see LevelEditorCanvas).
##
## Issue #638: same-kind ground pieces that overlap or share a
## boundary UNITE into one shape automatically (see
## LevelEditorCanvas) — including a brush stroke's cells when the
## stroke ends.
##
## Layout follows the shared menu pattern (MenuTheme, MenuBackground)
## with the canvas filling the whole editor.
## Issue #676: the editor tools live in a PALETTE pinned to the
## editor's TOP-LEFT corner — the ground-tool column, the #632 shape
## column and a GROUND & VIEW column (ground picture on/off, reset
## view) side by side — with no brand column beside it, so the
## palette sits in the true corner and the canvas keeps the full
## size. The FILE operations (level name, save/load, load from disk,
## download) live in a panel pinned to the canvas's BOTTOM-RIGHT
## corner; CLEAR, BACK and the status line stay in the slim bar
## under the canvas. Issue #699 adds the SNAP TO GRID toggle to the
## GROUND & VIEW column — off, authoring clicks land exactly where
## clicked instead of snapping to the 32 px grid. The data model is
## deliberately plain ({kind, shape, ...} pieces and {x, y} spawns in
## a fixed 1152x648 level space) so CustomLevel.gd can build a real
## playable scene from the files.
##
## Issue #675: the canvas is a movable, zoomable CAMERA over the level
## map — the wheel zooms toward the cursor, a middle/right drag pans
## (see LevelEditorCanvas) — and RESET VIEW in the bar under the
## canvas restores the fitted whole-map view.
##
## Issue #740: pictures per GROUND KIND plus the level BACKGROUND —
## the GROUND PICTURES column of the palette gives INDESTRUCTIBLE and
## DESTRUCTIBLE ground their own picture (each with a live preview
## thumbnail in the interface, an exact TILE SIZE — W/H in level
## pixels per repetition, so a picture smaller than its ground
## repeats periodically — and a ROTATION) and the BACKGROUND group
## picks the level's backdrop. Level files embed them as
## "pictures": {kind: {name, png, w, h, rot}} (the legacy #633
## single "picture" key still loads, filling both ground kinds).

const LEVELS_DIR := "user://levels"
const FORMAT := "forms-level/1"
const NAME_CHARS := \
	"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_- "
## Issue #633: the longest side an embedded ground picture may keep —
## larger images are downscaled so level files stay share-sized.
const MAX_PICTURE_SIDE := 1152

@onready var _indestructible_tool: Button = %IndestructibleTool
@onready var _destructible_tool: Button = %DestructibleTool
@onready var _spawn_tool: Button = %SpawnTool
@onready var _erase_tool: Button = %EraseTool
@onready var _edit_tool: Button = %EditTool
@onready var _rect_tool: Button = %RectTool
@onready var _triangle_tool: Button = %TriangleTool
@onready var _circle_tool: Button = %CircleTool
@onready var _loop_tool: Button = %LoopTool
@onready var _curve_tool: Button = %CurveTool
@onready var _brush_tool: Button = %BrushTool
@onready var _canvas: Control = %EditorCanvas
@onready var _file_name_edit: LineEdit = %FileNameEdit
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _file_select: OptionButton = %FileSelect
@onready var _load_file_button: Button = %LoadFileButton
@onready var _download_button: Button = %DownloadButton
@onready var _open_dialog: FileDialog = %OpenDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _reset_view_button: Button = %ResetViewButton
@onready var _snap_button: Button = %SnapButton
@onready var _picture_dialog: FileDialog = %PictureDialog
@onready var _clear_button: Button = %ClearButton
@onready var _back_button: Button = %BackButton
@onready var _status_text: Label = %StatusText
# Issue #740: the per-kind picture controls of the GROUND PICTURES
# column — choose / drop buttons, a preview thumbnail and (for the
# ground kinds) the tile size W/H and rotation spinboxes.
@onready var _in_pic_button: Button = %IndestructiblePicButton
@onready var _in_no_pic_button: Button = %IndestructibleNoPicButton
@onready var _in_preview: TextureRect = %IndestructiblePreview
@onready var _in_w: SpinBox = %IndestructibleW
@onready var _in_h: SpinBox = %IndestructibleH
@onready var _in_rot: SpinBox = %IndestructibleRot
@onready var _de_pic_button: Button = %DestructiblePicButton
@onready var _de_no_pic_button: Button = %DestructibleNoPicButton
@onready var _de_preview: TextureRect = %DestructiblePreview
@onready var _de_w: SpinBox = %DestructibleW
@onready var _de_h: SpinBox = %DestructibleH
@onready var _de_rot: SpinBox = %DestructibleRot
@onready var _bg_pic_button: Button = %BackgroundPicButton
@onready var _bg_no_pic_button: Button = %BackgroundNoPicButton
@onready var _bg_preview: TextureRect = %BackgroundPreview

var _files: PackedStringArray = []

## Issue #464 rework: the file currently open in the editor — the
## target SAVE writes back to ("" while the canvas belongs to a level
## that was never saved or loaded from disk).
var _current_path := ""

## The loaded file's level NAME — SAVE writes in place while the name
## field still shows it; typing a different name creates a new level.
var _loaded_name := ""

## Issue #740: the picture slot the chooser was opened for
## ("indestructible" / "destructible" / "background").
var _picture_kind := ""


func _ready() -> void:
	_indestructible_tool.pressed.connect(
		func() -> void: _canvas.set_tool("indestructible"))
	_destructible_tool.pressed.connect(
		func() -> void: _canvas.set_tool("destructible"))
	_spawn_tool.pressed.connect(
		func() -> void: _canvas.set_tool("spawn"))
	_erase_tool.pressed.connect(
		func() -> void: _canvas.set_tool("erase"))
	# Issue #639: EDIT — drag a figure's points to reshape it.
	_edit_tool.pressed.connect(
		func() -> void: _canvas.set_tool("edit"))
	# Issue #632: the shape palette — combines with the ground tools.
	_rect_tool.pressed.connect(
		func() -> void: _canvas.set_shape("rect"))
	_triangle_tool.pressed.connect(
		func() -> void: _canvas.set_shape("tri"))
	_circle_tool.pressed.connect(
		func() -> void: _canvas.set_shape("circle"))
	_loop_tool.pressed.connect(
		func() -> void: _canvas.set_shape("loop"))
	_curve_tool.pressed.connect(
		func() -> void: _canvas.set_shape("curve"))
	# Issue #673: the BRUSH shape — drag-paints ground grid cells.
	_brush_tool.pressed.connect(
		func() -> void: _canvas.set_shape("brush"))
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_load_file_button.pressed.connect(_on_load_file_pressed)
	_download_button.pressed.connect(_on_download_pressed)
	_open_dialog.file_selected.connect(_on_open_dialog_selected)
	_save_dialog.file_selected.connect(_on_save_dialog_selected)
	# Issue #740: the per-kind picture controls — choose / drop for
	# the two ground kinds and the background, live tile size /
	# rotation for the ground kinds.
	_in_pic_button.pressed.connect(
		func() -> void: _on_kind_picture_pressed("indestructible"))
	_in_no_pic_button.pressed.connect(
		func() -> void: _on_kind_no_picture_pressed("indestructible"))
	_de_pic_button.pressed.connect(
		func() -> void: _on_kind_picture_pressed("destructible"))
	_de_no_pic_button.pressed.connect(
		func() -> void: _on_kind_no_picture_pressed("destructible"))
	_bg_pic_button.pressed.connect(
		func() -> void: _on_kind_picture_pressed("background"))
	_bg_no_pic_button.pressed.connect(
		func() -> void: _on_kind_no_picture_pressed("background"))
	_in_w.value_changed.connect(
		_on_ground_param_changed.bind("indestructible"))
	_in_h.value_changed.connect(
		_on_ground_param_changed.bind("indestructible"))
	_in_rot.value_changed.connect(
		_on_ground_param_changed.bind("indestructible"))
	_de_w.value_changed.connect(
		_on_ground_param_changed.bind("destructible"))
	_de_h.value_changed.connect(
		_on_ground_param_changed.bind("destructible"))
	_de_rot.value_changed.connect(
		_on_ground_param_changed.bind("destructible"))
	_reset_view_button.pressed.connect(_on_reset_view_pressed)
	# Issue #699: SNAP TO GRID — a toggle, on by default.
	_snap_button.toggled.connect(_on_snap_toggled)
	_picture_dialog.file_selected.connect(_on_picture_selected)
	_clear_button.pressed.connect(_on_clear_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_indestructible_tool.set_pressed_no_signal(true)
	_rect_tool.set_pressed_no_signal(true)
	_canvas.set_tool("indestructible")
	_canvas.set_shape("rect")
	_back_button.grab_focus()
	_ensure_levels_dir()
	_refresh_file_list()
	_set_status("drag ground shapes; BRUSH paints cells by dragging; "
		+ "EDIT POINTS moves them (click an outline to add a point); "
		+ "wheel zooms, middle/right-drag pans")


func _ensure_levels_dir() -> void:
	if not DirAccess.dir_exists_absolute(LEVELS_DIR):
		DirAccess.make_dir_recursive_absolute(LEVELS_DIR)


func _refresh_file_list(select_stem: String = "") -> void:
	_files = PackedStringArray()
	_file_select.clear()
	for fname in DirAccess.get_files_at(LEVELS_DIR):
		if fname.ends_with(".json"):
			_files.append(fname)
	_files.sort()
	var select_index := -1
	for i in _files.size():
		var stem: String = _files[i].get_basename()
		_file_select.add_item(stem, i)
		if stem == select_stem:
			select_index = i
	if select_index >= 0:
		_file_select.select(select_index)
	elif _file_select.item_count > 0:
		_file_select.select(0)


func _sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		out += ch if ch in NAME_CHARS else "_"
	return out.strip_edges()


## The current canvas state as a forms-level/1 dictionary.
func _serialize_level(name: String) -> Dictionary:
	var pieces: Array = []
	for piece in _canvas.get_pieces():
		var shape := str(piece.get("shape", "rect"))
		if shape == "loop" or shape == "curve":
			var points: Array = []
			for point in piece["points"]:
				points.append({
				"x": (point as Vector2).x,
				"y": (point as Vector2).y,
			})
			pieces.append({
				"kind": piece["kind"],
				"shape": shape,
				"points": points,
			})
		else:
			var rect: Rect2 = piece["rect"]
			pieces.append({
				"kind": piece["kind"],
				"shape": shape,
				"x": rect.position.x,
				"y": rect.position.y,
				"w": rect.size.x,
				"h": rect.size.y,
			})
	var spawns: Array = []
	for spawn in _canvas.get_spawns():
		var pos: Vector2 = spawn
		spawns.append({"x": pos.x, "y": pos.y})
	var level := {
		"format": FORMAT,
		"name": name,
		"pieces": pieces,
		"spawns": spawns,
	}
	# Issue #740: every picture travels INSIDE the level file, so
	# downloads/loads keep them without side-car files — one entry
	# per ground kind (with its exact tile size and rotation) plus
	# the background.
	var pictures := {}
	for kind in ["indestructible", "destructible", "background"]:
		var pic: Dictionary = _canvas.get_picture(kind)
		if pic.is_empty():
			continue
		var entry := {
			"name": str(pic["name"]),
			"png": Marshalls.raw_to_base64(pic["png"]),
		}
		if kind != "background":
			var size: Vector2 = pic["size"]
			entry["w"] = size.x
			entry["h"] = size.y
			entry["rot"] = float(pic["rotation"])
		pictures[kind] = entry
	if not pictures.is_empty():
		level["pictures"] = pictures
	return level


## Write the current level to `path` as JSON. Returns true on success.
func _save_to_path(path: String, name: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(_serialize_level(name), "  "))
	file.close()
	return true


## Issue #464 rework: SAVE writes the changes back to the open file;
## with a NEW name typed (or no file open yet) it creates/updates
## user://levels/<name>.json instead.
func _on_save_pressed() -> void:
	var safe := _sanitize_name(_file_name_edit.text)
	if safe.is_empty():
		_set_status("enter a level name before saving")
		return
	_file_name_edit.text = safe
	var stem := safe.replace(" ", "_")
	# Issue #464 rework: the open file keeps receiving the changes while
	# its name is unchanged; a NEW name creates a new level file.
	var in_place := not _current_path.is_empty() and safe == _loaded_name
	var path := _current_path if in_place \
		else "%s/%s.json" % [LEVELS_DIR, stem]
	if not _save_to_path(path, safe):
		return
	_current_path = path
	_loaded_name = safe
	var level := _serialize_level(safe)
	_refresh_file_list(stem)
	_set_status("saved %s (%d pieces, %d spawns)" % [
		path, level["pieces"].size(), level["spawns"].size()])


## Load a level file from anywhere on the user's filesystem into the
## canvas and make it the open file SAVE writes back to.
func _on_load_file_pressed() -> void:
	_open_dialog.popup_centered(Vector2i(900, 600))


func _on_open_dialog_selected(path: String) -> void:
	_load_from_path(path)


## DOWNLOAD — export a copy of the current level file to a path the
## user picks (their own filesystem; the open file is untouched).
func _on_download_pressed() -> void:
	var safe := _sanitize_name(_file_name_edit.text)
	_save_dialog.current_file = (safe if not safe.is_empty() else "level") \
		.replace(" ", "_") + ".json"
	_save_dialog.popup_centered(Vector2i(900, 600))


func _on_save_dialog_selected(path: String) -> void:
	var safe := _sanitize_name(_file_name_edit.text)
	var name := safe if not safe.is_empty() \
		else path.get_file().get_basename().replace("_", " ")
	if _save_to_path(path, name):
		_set_status("downloaded %s" % path)


## Issue #740: open the picture chooser for one slot — an
## "indestructible" or "destructible" ground picture, or the level
## "background".
func _on_kind_picture_pressed(kind: String) -> void:
	_picture_kind = kind
	_picture_dialog.popup_centered(Vector2i(900, 600))


## Issue #740: drop one slot's picture — flat colors / the plain
## background return on the canvas and in the playable level.
func _on_kind_no_picture_pressed(kind: String) -> void:
	_canvas.clear_picture(kind)
	_refresh_picture_ui()
	_set_status("%s picture cleared" % kind)


## Issue #633/#740: choose a PICTURE for the slot the chooser was
## opened for — any image the user picks is decoded, downscaled to
## MAX_PICTURE_SIDE and embedded (as PNG) with the level. A ground
## picture starts at its native size as its exact tile (smaller
## than the ground → it repeats); the size and rotation are then
## free to change in the interface.
func _on_picture_selected(path: String) -> void:
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	var bytes := FileAccess.get_file_as_bytes(path)
	match path.get_extension().to_lower():
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
		"bmp":
			err = image.load_bmp_from_buffer(bytes)
		_:
			err = image.load_png_from_buffer(bytes)
	if err != OK or image.is_empty():
		_set_status("cannot read picture %s" % path.get_file())
		return
	var longest := maxi(image.get_width(), image.get_height())
	if longest > MAX_PICTURE_SIDE:
		var factor := MAX_PICTURE_SIDE / float(longest)
		image.resize(maxi(1, int(image.get_width() * factor)),
				maxi(1, int(image.get_height() * factor)),
			Image.INTERPOLATE_LANCZOS)
	var pic_name := path.get_file()
	var png := image.save_png_to_buffer()
	if _picture_kind == "background":
		_canvas.set_picture("background",
			ImageTexture.create_from_image(image), pic_name, png)
		_refresh_picture_ui()
		_set_status("background picture %s (%dx%d)" % [pic_name,
			image.get_width(), image.get_height()])
		return
	var size := Vector2(image.get_width(), image.get_height())
	_canvas.set_picture(_picture_kind,
		ImageTexture.create_from_image(image), pic_name, png, size, 0.0)
	_refresh_picture_ui()
	_set_status("%s ground picture %s (%dx%d, tiles at %dx%d)" % [
		_picture_kind, pic_name, image.get_width(), image.get_height(),
		int(size.x), int(size.y)])


## Issue #740: a tile-size / rotation spinbox changed — push the
## ground kind's new exact size and rotation to the canvas live.
func _on_ground_param_changed(_value: float, kind: String) -> void:
	if kind == "indestructible":
		_canvas.set_picture_transform(kind, Vector2(
			_in_w.value, _in_h.value), _in_rot.value)
	else:
		_canvas.set_picture_transform(kind, Vector2(
			_de_w.value, _de_h.value), _de_rot.value)


## Issue #740: sync the picture previews and the tile size /
## rotation spinboxes with the canvas state (after a choose, a clear
## or a load).
func _refresh_picture_ui() -> void:
	_sync_picture_group("indestructible", _in_preview,
		_in_w, _in_h, _in_rot)
	_sync_picture_group("destructible", _de_preview,
		_de_w, _de_h, _de_rot)
	var background: Dictionary = _canvas.get_picture("background")
	_bg_preview.texture = background["texture"] as Texture2D \
			if not background.is_empty() else null


func _sync_picture_group(kind: String, preview: TextureRect,
		w: SpinBox, h: SpinBox, rot: SpinBox) -> void:
	var pic: Dictionary = _canvas.get_picture(kind)
	if pic.is_empty():
		preview.texture = null
	else:
		preview.texture = pic["texture"] as Texture2D
	var size: Vector2 = pic.get("size", Vector2.ZERO)
	w.set_value_no_signal(size.x)
	h.set_value_no_signal(size.y)
	rot.set_value_no_signal(float(pic.get("rotation", 0.0)))


## Load any forms level file (user://levels entry or a path from the
## user's filesystem). Returns true when the canvas changed.
func _load_from_path(path: String) -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY \
			or str((parsed as Dictionary).get("format", "")) != FORMAT:
		_set_status("%s is not a forms level file" % path.get_file())
		return false
	var level: Dictionary = parsed
	var pieces: Array = []
	var raw_pieces: Array = level.get("pieces", [])
	for raw in raw_pieces:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var kind := str((raw as Dictionary).get("kind", ""))
		if kind != "indestructible" and kind != "destructible":
			continue
		# Issue #632: rect / tri / circle author an {x,y,w,h} box (a
		# missing shape key is a legacy #464 rectangle); loop and curve
		# author their clicked points.
		var shape := str((raw as Dictionary).get("shape", "rect"))
		if shape != "rect" and shape != "tri" and shape != "circle" \
				and shape != "loop" and shape != "curve":
			shape = "rect"
		if shape == "loop" or shape == "curve":
			var points := PackedVector2Array()
			for rp in (raw as Dictionary).get("points", []):
				if typeof(rp) == TYPE_DICTIONARY:
					points.append(Vector2(
						float((rp as Dictionary).get("x", 0.0)),
						float((rp as Dictionary).get("y", 0.0))))
			# Loops need a polygon (>= 3 points); curves exactly their
			# start, end and bend control point.
			if (shape == "loop" and points.size() >= 3) \
					or (shape == "curve" and points.size() == 3):
				pieces.append({
					"kind": kind, "shape": shape, "points": points})
			continue
		var w := float((raw as Dictionary).get("w", 0.0))
		var h := float((raw as Dictionary).get("h", 0.0))
		if w <= 0.0 or h <= 0.0:
			continue
		pieces.append({
			"kind": kind,
			"shape": shape,
			"rect": Rect2(
				Vector2(
					float((raw as Dictionary).get("x", 0.0)),
					float((raw as Dictionary).get("y", 0.0))),
				Vector2(w, h)),
		})
	var spawns: Array = []
	var raw_spawns: Array = level.get("spawns", [])
	for raw in raw_spawns:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		spawns.append(Vector2(
			float((raw as Dictionary).get("x", 0.0)),
			float((raw as Dictionary).get("y", 0.0))))
	_canvas.set_pieces(pieces)
	_canvas.set_spawns(spawns)
	_load_pictures(level)
	_current_path = path
	var loaded_name := str(level.get("name", ""))
	_loaded_name = loaded_name if not loaded_name.is_empty() \
		else path.get_file().get_basename()
	_file_name_edit.text = _loaded_name
	_refresh_file_list(path.get_file().get_basename()
		if path.begins_with(LEVELS_DIR) else "")
	var picture_count := 0
	for kind in ["indestructible", "destructible", "background"]:
		if _canvas.has_picture(kind):
			picture_count += 1
	_set_status("loaded %s (%d pieces, %d spawns%s)" % [
		path.get_file(), pieces.size(), spawns.size(),
		", %d pictures" % picture_count if picture_count > 0 else ""])
	return true


## Issue #740: restore the level file's pictures onto the canvas —
## one per ground kind (with its exact tile size and rotation) plus
## the background; a legacy #633 single "picture" fills BOTH ground
## kinds (stretched, as before). A missing/broken entry quietly
## falls back to flat colors.
func _load_pictures(level: Dictionary) -> void:
	for kind in ["indestructible", "destructible", "background"]:
		_canvas.clear_picture(kind)
	var raw_pics = level.get("pictures", null)
	if typeof(raw_pics) == TYPE_DICTIONARY:
		for kind in ["indestructible", "destructible", "background"]:
			var raw = (raw_pics as Dictionary).get(kind, {})
			if typeof(raw) == TYPE_DICTIONARY:
				_apply_picture_entry(kind, raw)
	else:
		var legacy = level.get("picture", {})
		if typeof(legacy) == TYPE_DICTIONARY:
			var png := Marshalls.base64_to_raw(
					str((legacy as Dictionary).get("png", "")))
			var image := Image.new()
			if not png.is_empty() \
						and image.load_png_from_buffer(png) == OK:
				var tex := ImageTexture.create_from_image(image)
				for kind in ["indestructible", "destructible"]:
					_canvas.set_picture(kind, tex,
							str((legacy as Dictionary).get("name", "picture")),
						png, Vector2.ZERO, 0.0)
	_refresh_picture_ui()


## Issue #740: decode and apply one level-file picture entry onto
## its canvas slot.
func _apply_picture_entry(kind: String, raw: Dictionary) -> void:
	var png := Marshalls.base64_to_raw(str(raw.get("png", "")))
	var image := Image.new()
	if png.is_empty() or image.load_png_from_buffer(png) != OK:
		return
	_canvas.set_picture(kind, ImageTexture.create_from_image(image),
		str(raw.get("name", "picture")), png,
		Vector2(float(raw.get("w", 0.0)), float(raw.get("h", 0.0))),
		float(raw.get("rot", 0.0)))


func _on_load_pressed() -> void:
	if _files.is_empty():
		_set_status("no saved level files yet")
		return
	var id := _file_select.get_selected_id()
	if id < 0 or id >= _files.size():
		_set_status("select a level file first")
		return
	_load_from_path("%s/%s" % [LEVELS_DIR, _files[id]])


## Issue #675: RESET VIEW — back to the fitted whole-map camera.
func _on_reset_view_pressed() -> void:
	_canvas.reset_view()
	_set_status("view reset to the whole map")


## Issue #699: SNAP TO GRID — on (the default) every authoring click
## snaps to the 32 px grid; off, placements land exactly where
## clicked (the BRUSH still paints whole grid cells — its cells are
## its shape).
func _on_snap_toggled(on: bool) -> void:
	_canvas.set_snap_enabled(on)
	_set_status("snap to grid %s" % ("on" if on else "off"))


func _on_clear_pressed() -> void:
	_canvas.clear_all()
	_set_status("canvas cleared")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _set_status(text: String) -> void:
	_status_text.text = text


## Issue #303: Escape is the cancel button in every menu — in the
## editor cancel means back to the main menu (unsaved changes are
## discarded, same as CLEAR).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
