extends Control
## Editing canvas for the level editor (issue #464).
##
## Pure visual authoring: ground pieces and spawn points are stored as
## data (no physics) and drawn in code with the same colors the ground
## scripts use for themselves. The canvas shows a fixed 1152x648
## logical level space (the game's base viewport) and scales itself to
## fit whatever rectangle its container gives it — mouse input is
## translated back into level coordinates, so drawing feels the same
## at any scale.
##
## Tools (set via set_tool, driven by the editor's tool palette):
##  - "indestructible": drag a rectangle for a purple gravity slab;
##  - "destructible": drag a rectangle for a brown dirt chunk;
##  - "spawn": click to drop a player spawn point;
##  - "erase": click a piece or spawn to remove it.
##
## Everything snaps to a 32 px grid. A drag smaller than MIN_PIECE
## falls back to DEFAULT_SIZE centred on the click, so a single click
## still places a piece.

const IndestructibleGroundScript := preload(
	"res://scripts/IndestructibleGround.gd")
const DestructibleGroundScript := preload(
	"res://scripts/DestructibleGround.gd")

## The logical level space the editor authors (base game viewport).
const CANVAS_SIZE := Vector2(1152, 648)
const SNAP := 32.0
const MIN_PIECE := Vector2(32, 32)
const DEFAULT_SIZE := Vector2(128, 64)
const ERASE_RADIUS := 20.0
const BG_COLOR := Color(0.08, 0.09, 0.12, 1)
const GRID_COLOR := Color(1, 1, 1, 0.05)
const GRID_MAJOR_COLOR := Color(1, 1, 1, 0.1)
const BORDER_COLOR := Color(0.655, 0.545, 0.98, 0.6)
const SPAWN_COLOR := Color(0.95, 0.85, 0.35, 1)

var _tool := "indestructible"
var _pieces: Array = []
var _spawns: Array = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO
var _hover := Vector2(-1000, -1000)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_rescale)
	_rescale()
	queue_redraw()


func _rescale() -> void:
	if size.x > 1.0 and size.y > 1.0:
		scale = size / CANVAS_SIZE


func set_tool(kind: String) -> void:
	_tool = kind
	queue_redraw()


func get_tool() -> String:
	return _tool


func set_pieces(pieces: Array) -> void:
	_pieces = pieces.duplicate(true)
	queue_redraw()


func get_pieces() -> Array:
	return _pieces.duplicate(true)


func set_spawns(spawns: Array) -> void:
	_spawns = spawns.duplicate(true)
	queue_redraw()


func get_spawns() -> Array:
	return _spawns.duplicate(true)


func clear_all() -> void:
	_pieces.clear()
	_spawns.clear()
	_dragging = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press(_local_snap_mouse())
			accept_event()
		elif _dragging:
			_release(_local_snap_mouse())
			accept_event()
	elif event is InputEventMouseMotion:
		_hover = get_local_mouse_position()
		queue_redraw()


func _press(pos: Vector2) -> void:
	match _tool:
		"spawn":
			_spawns.append(pos)
			queue_redraw()
		"erase":
			_erase_at(pos)
		_:
			_dragging = true
			_drag_start = pos
			_drag_end = pos
			queue_redraw()


func _release(pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	var rect := Rect2(_drag_start, pos - _drag_start).abs()
	if rect.size.x < MIN_PIECE.x or rect.size.y < MIN_PIECE.y:
		rect = Rect2(pos - DEFAULT_SIZE * 0.5, DEFAULT_SIZE)
	rect = rect.intersection(Rect2(Vector2.ZERO, CANVAS_SIZE))
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		_pieces.append({"kind": _tool, "rect": rect})
	queue_redraw()


func _erase_at(pos: Vector2) -> void:
	for i in range(_spawns.size() - 1, -1, -1):
		if pos.distance_to(_spawns[i] as Vector2) <= ERASE_RADIUS:
			_spawns.remove_at(i)
			queue_redraw()
			return
	for i in range(_pieces.size() - 1, -1, -1):
		if (_pieces[i]["rect"] as Rect2).has_point(pos):
			_pieces.remove_at(i)
			queue_redraw()
			return


func _local_snap_mouse() -> Vector2:
	return get_local_mouse_position().snapped(Vector2(SNAP, SNAP))


func _tool_color() -> Color:
	if _tool == "indestructible":
		return IndestructibleGroundScript.COLOR
	return DestructibleGroundScript.COLOR


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), BG_COLOR)
	_draw_grid()
	for piece in _pieces:
		var rect: Rect2 = piece["rect"]
		var color: Color = IndestructibleGroundScript.COLOR \
			if piece["kind"] == "indestructible" \
			else DestructibleGroundScript.COLOR
		draw_rect(rect, Color(color, 0.85))
		draw_rect(rect, color, false, 2.0)
	for spawn in _spawns:
		var pos: Vector2 = spawn
		draw_arc(pos, 14.0, 0.0, TAU, 40, SPAWN_COLOR, 2.0)
		draw_circle(pos, 5.0, SPAWN_COLOR)
	_draw_preview()
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), BORDER_COLOR, false, 2.0)


func _draw_preview() -> void:
	if _dragging:
		var rect := Rect2(_drag_start, _drag_end - _drag_start).abs()
		var color := _tool_color()
		draw_rect(rect, Color(color, 0.35))
		draw_rect(rect, color, false, 2.0)
	elif _hover.x >= 0.0 and _hover.y >= 0.0 \
			and _hover.x <= CANVAS_SIZE.x and _hover.y <= CANVAS_SIZE.y:
		var snapped := _hover.snapped(Vector2(SNAP, SNAP))
		if _tool == "spawn":
			draw_arc(snapped, 14.0, 0.0, TAU, 40,
				Color(SPAWN_COLOR, 0.5), 2.0)
		elif _tool != "erase":
			var rect := Rect2(snapped - DEFAULT_SIZE * 0.5, DEFAULT_SIZE)
			var color := _tool_color()
			draw_rect(rect, Color(color, 0.15))
			draw_rect(rect, Color(color, 0.5), false, 1.0)


func _draw_grid() -> void:
	var major_every := SNAP * 4.0
	var x := SNAP
	while x < CANVAS_SIZE.x:
		draw_line(Vector2(x, 0.0), Vector2(x, CANVAS_SIZE.y),
			GRID_MAJOR_COLOR if fmod(x, major_every) < 0.5
			else GRID_COLOR)
		x += SNAP
	var y := SNAP
	while y < CANVAS_SIZE.y:
		draw_line(Vector2(0.0, y), Vector2(CANVAS_SIZE.x, y),
			GRID_MAJOR_COLOR if fmod(y, major_every) < 0.5
			else GRID_COLOR)
		y += SNAP
