extends Control
## Level editor for Forms (issue #464).
##
## Opened from the main menu's LEVEL EDITOR button. A grid canvas for
## authoring skirmish maps with the same shapes the levels use —
## indestructible gravity slabs (purple), destructible dirt (brown)
## and player spawn points — plus export/import of the result as a
## JSON level file under user://levels/.
##
## Layout follows the shared menu pattern (MenuTheme, MenuBackground,
## brand column on the left, canvas filling the remaining space); the
## file operations sit in a bottom bar. The data model is deliberately
## plain ({kind, x, y, w, h} pieces and {x, y} spawns in a fixed
## 1152x648 level space) so a future level loader can build real
## scenes from the files.

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
@onready var _clear_button: Button = %ClearButton
@onready var _back_button: Button = %BackButton
@onready var _status_text: Label = %StatusText

var _files: PackedStringArray = []


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


func _on_save_pressed() -> void:
	var safe := _sanitize_name(_file_name_edit.text)
	if safe.is_empty():
		_set_status("enter a level name before saving")
		return
	_file_name_edit.text = safe
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
	var data := {
		"format": FORMAT,
		"name": safe,
		"pieces": pieces,
		"spawns": spawns,
	}
	var stem := safe.replace(" ", "_")
	var path := "%s/%s.json" % [LEVELS_DIR, stem]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("cannot write %s" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_refresh_file_list(stem)
	_set_status("saved %s (%d pieces, %d spawns)" % [
		path, pieces.size(), spawns.size()])


func _on_load_pressed() -> void:
	if _files.is_empty():
		_set_status("no saved level files yet")
		return
	var id := _file_select.get_selected_id()
	if id < 0 or id >= _files.size():
		_set_status("select a level file first")
		return
	var path := "%s/%s" % [LEVELS_DIR, _files[id]]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY \
			or str((parsed as Dictionary).get("format", "")) != FORMAT:
		_set_status("%s is not a forms level file" % _files[id])
		return
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
	_file_name_edit.text = str(level.get("name", _files[id].get_basename()))
	_set_status("loaded %s (%d pieces, %d spawns)" % [
		_files[id], pieces.size(), spawns.size()])


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
