extends Control
## Level editor for Forms (issue #464).
##
## Opened from the main menu's LEVEL EDITOR button. A grid canvas for
## authoring skirmish maps with the same shapes the levels use —
## indestructible gravity slabs (purple), destructible dirt (brown)
## and player spawn points — plus export/import of the result as a
## JSON level file under user://levels/.
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
## Layout follows the shared menu pattern (MenuTheme, MenuBackground,
## brand column on the left, canvas filling the remaining space); the
## file operations sit in the bars under the canvas. The data model is
## deliberately plain ({kind, x, y, w, h} pieces and {x, y} spawns in
## a fixed 1152x648 level space) so CustomLevel.gd can build a real
## playable scene from the files.

const LEVELS_DIR := "user://levels"
const FORMAT := "forms-level/1"
const NAME_CHARS := \
	"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_- "

@onready var _indestructible_tool: Button = %IndestructibleTool
@onready var _destructible_tool: Button = %DestructibleTool
@onready var _spawn_tool: Button = %SpawnTool
@onready var _erase_tool: Button = %EraseTool
@onready var _canvas: Control = %EditorCanvas
@onready var _file_name_edit: LineEdit = %FileNameEdit
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _file_select: OptionButton = %FileSelect
@onready var _load_file_button: Button = %LoadFileButton
@onready var _download_button: Button = %DownloadButton
@onready var _open_dialog: FileDialog = %OpenDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _clear_button: Button = %ClearButton
@onready var _back_button: Button = %BackButton
@onready var _status_text: Label = %StatusText

var _files: PackedStringArray = []

## Issue #464 rework: the file currently open in the editor — the
## target SAVE writes back to ("" while the canvas belongs to a level
## that was never saved or loaded from disk).
var _current_path := ""

## The loaded file's level NAME — SAVE writes in place while the name
## field still shows it; typing a different name creates a new level.
var _loaded_name := ""


func _ready() -> void:
	_indestructible_tool.pressed.connect(
		func() -> void: _canvas.set_tool("indestructible"))
	_destructible_tool.pressed.connect(
		func() -> void: _canvas.set_tool("destructible"))
	_spawn_tool.pressed.connect(
		func() -> void: _canvas.set_tool("spawn"))
	_erase_tool.pressed.connect(
		func() -> void: _canvas.set_tool("erase"))
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_load_file_button.pressed.connect(_on_load_file_pressed)
	_download_button.pressed.connect(_on_download_pressed)
	_open_dialog.file_selected.connect(_on_open_dialog_selected)
	_save_dialog.file_selected.connect(_on_save_dialog_selected)
	_clear_button.pressed.connect(_on_clear_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_indestructible_tool.set_pressed_no_signal(true)
	_canvas.set_tool("indestructible")
	_back_button.grab_focus()
	_ensure_levels_dir()
	_refresh_file_list()
	_set_status("drag on the canvas to place ground, click for spawns")


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
		var rect: Rect2 = piece["rect"]
		pieces.append({
			"kind": piece["kind"],
			"x": rect.position.x,
			"y": rect.position.y,
			"w": rect.size.x,
			"h": rect.size.y,
		})
	var spawns: Array = []
	for spawn in _canvas.get_spawns():
		var pos: Vector2 = spawn
		spawns.append({"x": pos.x, "y": pos.y})
	return {
		"format": FORMAT,
		"name": name,
		"pieces": pieces,
		"spawns": spawns,
	}


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
		var w := float((raw as Dictionary).get("w", 0.0))
		var h := float((raw as Dictionary).get("h", 0.0))
		if w <= 0.0 or h <= 0.0:
			continue
		pieces.append({
			"kind": kind,
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
	_current_path = path
	var loaded_name := str(level.get("name", ""))
	_loaded_name = loaded_name if not loaded_name.is_empty() \
		else path.get_file().get_basename()
	_file_name_edit.text = _loaded_name
	_refresh_file_list(path.get_file().get_basename()
		if path.begins_with(LEVELS_DIR) else "")
	_set_status("loaded %s (%d pieces, %d spawns)" % [
		path.get_file(), pieces.size(), spawns.size()])
	return true


func _on_load_pressed() -> void:
	if _files.is_empty():
		_set_status("no saved level files yet")
		return
	var id := _file_select.get_selected_id()
	if id < 0 or id >= _files.size():
		_set_status("select a level file first")
		return
	_load_from_path("%s/%s" % [LEVELS_DIR, _files[id]])


func _on_clear_pressed() -> void:
	_canvas.clear_all()
	_set_status("canvas cleared")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


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
