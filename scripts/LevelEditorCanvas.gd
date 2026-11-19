extends Control
## Editing canvas for the level editor (issues #464 and #632).
##
## Pure visual authoring: ground pieces and spawn points are stored as
## data (no physics) and drawn in code with the same colors the ground
## scripts use for themselves. The canvas shows a fixed 1152x648
## logical level space (the game's base viewport) and scales itself to
## fit whatever rectangle its container gives it — mouse input is
## translated back into level coordinates, so drawing feels the same
## at any scale.
##
## Ground tools (set_tool, driven by the editor's tool palette):
##  - "indestructible": the drawn pieces are purple gravity ground;
##  - "destructible": the drawn pieces are brown dirt;
##  - "spawn": click to drop a player spawn point;
##  - "erase": click a piece or spawn to remove it.
##
## Issue #632 SHAPE palette (set_shape) — combines with the ground
## tools above:
##  - "rect": drag a rectangle (the original authoring shape);
##  - "tri": drag the bounding box of an upward-pointing triangle;
##  - "circle": drag from the disc's centre to its edge;
##  - "loop": click vertices of a segmented line — clicking back on
##    the marked FIRST vertex (>= 3 points) closes the loop;
##  - "curve": click the bezier's start, end and then its bend — a
##    quadratic curve stored as the three points in click order.
##
## Everything snaps to a 32 px grid. Box drags smaller than MIN_PIECE
## fall back to DEFAULT_SIZE centred on the click, so a single click
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
## Issue #632: circle fallback radius (a click instead of a drag) and
## the click distance that CLOSES a loop on its first vertex.
const DEFAULT_RADIUS := 64.0
const CLOSE_RADIUS := 20.0
## Issue #632: the ground ribbon a bezier curve authors and how finely
## it is sampled (CustomLevel builds the same strip).
const CURVE_THICKNESS := 48.0
const CURVE_SAMPLES := 24
const ERASE_RADIUS := 20.0
const BG_COLOR := Color(0.08, 0.09, 0.12, 1)
const GRID_COLOR := Color(1, 1, 1, 0.05)
const GRID_MAJOR_COLOR := Color(1, 1, 1, 0.1)
const BORDER_COLOR := Color(0.655, 0.545, 0.98, 0.6)
const SPAWN_COLOR := Color(0.95, 0.85, 0.35, 1)

var _tool := "indestructible"
var _shape := "rect"
var _pieces: Array = []
var _spawns: Array = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO
var _hover := Vector2(-1000, -1000)
## Issue #632: vertices clicked so far for the multi-click shapes
## ("loop" / "curve") — cleared when the piece is placed.
var _pending := PackedVector2Array()


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
	_cancel_pending()
	queue_redraw()


func get_tool() -> String:
	return _tool


func set_shape(shape: String) -> void:
	_shape = shape
	_cancel_pending()
	queue_redraw()


func get_shape() -> String:
	return _shape


func set_pieces(pieces: Array) -> void:
	_pieces = pieces.duplicate(true)
	# Legacy (#464) pieces carry no shape key — they are rectangles.
	for piece in _pieces:
		if piece.get("shape", "") == "":
			piece["shape"] = "rect"
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
	_cancel_pending()
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
		if _dragging:
			_drag_end = _local_snap_mouse()
		queue_redraw()


func _press(pos: Vector2) -> void:
	match _tool:
		"spawn":
			_spawns.append(pos)
			queue_redraw()
		"erase":
			_erase_at(pos)
		_:
			match _shape:
				"loop", "curve":
					_press_pending(pos)
				_:
					_dragging = true
					_drag_start = pos
					_drag_end = pos
					queue_redraw()


func _press_pending(pos: Vector2) -> void:
	# Loop: clicking back on the marked first vertex closes the shape.
	if _shape == "loop" and _pending.size() >= 3 \
			and pos.distance_to(_pending[0]) <= CLOSE_RADIUS:
		_pieces.append({"kind": _tool, "shape": "loop",
			"points": _pending.duplicate()})
		_cancel_pending()
		return
	_pending.append(pos)
	# Curve: start, end and bend — the third click completes it.
	if _shape == "curve" and _pending.size() == 3:
		_pieces.append({"kind": _tool, "shape": "curve",
			"points": _pending.duplicate()})
		_cancel_pending()


func _release(pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	match _shape:
		"circle":
			_release_circle(pos)
		"tri":
			_release_box(pos, "tri")
		_:
			_release_box(pos, "rect")
	queue_redraw()


func _release_box(pos: Vector2, shape: String) -> void:
	var rect := Rect2(_drag_start, pos - _drag_start).abs()
	if rect.size.x < MIN_PIECE.x or rect.size.y < MIN_PIECE.y:
		rect = Rect2(pos - DEFAULT_SIZE * 0.5, DEFAULT_SIZE)
	rect = rect.intersection(Rect2(Vector2.ZERO, CANVAS_SIZE))
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		_pieces.append({"kind": _tool, "shape": shape, "rect": rect})


func _release_circle(pos: Vector2) -> void:
	var center := _drag_start
	var radius := center.distance_to(pos)
	if radius < SNAP:
		radius = DEFAULT_RADIUS
	radius = minf(radius, minf(CANVAS_SIZE.x, CANVAS_SIZE.y) * 0.5)
	center.x = clampf(center.x, radius, CANVAS_SIZE.x - radius)
	center.y = clampf(center.y, radius, CANVAS_SIZE.y - radius)
	_pieces.append({"kind": _tool, "shape": "circle",
		"rect": Rect2(center - Vector2(radius, radius),
			Vector2(radius * 2.0, radius * 2.0))})


func _cancel_pending() -> void:
	if not _pending.is_empty():
		_pending.clear()
		queue_redraw()


func _erase_at(pos: Vector2) -> void:
	for i in range(_spawns.size() - 1, -1, -1):
		if pos.distance_to(_spawns[i] as Vector2) <= ERASE_RADIUS:
			_spawns.remove_at(i)
			queue_redraw()
			return
	for i in range(_pieces.size() - 1, -1, -1):
		if _piece_has_point(_pieces[i], pos):
			_pieces.remove_at(i)
			queue_redraw()
			return


func _piece_has_point(piece: Dictionary, pos: Vector2) -> bool:
	match str(piece.get("shape", "rect")):
		"circle":
			var rect: Rect2 = piece["rect"]
			return pos.distance_to(rect.get_center()) \
				<= minf(rect.size.x, rect.size.y) * 0.5
		"tri":
			return Geometry2D.is_point_in_polygon(
				pos, triangle_polygon(piece["rect"]))
		"loop":
			return Geometry2D.is_point_in_polygon(
				pos, piece["points"])
		"curve":
			return Geometry2D.is_point_in_polygon(pos,
				curve_strip_polygon(piece["points"], CURVE_THICKNESS))
		_:
			return (piece["rect"] as Rect2).has_point(pos)


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
		_draw_piece(piece)
	for spawn in _spawns:
		var pos: Vector2 = spawn
		draw_arc(pos, 14.0, 0.0, TAU, 40, SPAWN_COLOR, 2.0)
		draw_circle(pos, 5.0, SPAWN_COLOR)
	_draw_preview()
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), BORDER_COLOR, false, 2.0)


func _draw_piece(piece: Dictionary) -> void:
	var color: Color = IndestructibleGroundScript.COLOR \
		if piece["kind"] == "indestructible" \
		else DestructibleGroundScript.COLOR
	match str(piece.get("shape", "rect")):
		"circle":
			var rect: Rect2 = piece["rect"]
			var center := rect.get_center()
			var radius := minf(rect.size.x, rect.size.y) * 0.5
			draw_circle(center, radius, Color(color, 0.85))
			draw_arc(center, radius, 0.0, TAU, 48, color, 2.0)
		"tri":
			var pts := triangle_polygon(piece["rect"])
			draw_colored_polygon(pts, Color(color, 0.85))
			_draw_outline(pts, color)
		"loop":
			var loop_pts: PackedVector2Array = piece["points"]
			draw_colored_polygon(loop_pts, Color(color, 0.85))
			_draw_outline(loop_pts, color)
		"curve":
			var strip := curve_strip_polygon(
				piece["points"], CURVE_THICKNESS)
			draw_colored_polygon(strip, Color(color, 0.85))
			_draw_outline(strip, color)
		_:
			var rect: Rect2 = piece["rect"]
			draw_rect(rect, Color(color, 0.85))
			draw_rect(rect, color, false, 2.0)


func _draw_outline(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, 2.0)


func _draw_preview() -> void:
	if _dragging:
		_draw_drag_preview()
		return
	if not _pending.is_empty():
		_draw_pending_preview()
		return
	if _hover.x >= 0.0 and _hover.y >= 0.0 \
			and _hover.x <= CANVAS_SIZE.x and _hover.y <= CANVAS_SIZE.y:
		var snapped := _hover.snapped(Vector2(SNAP, SNAP))
		if _tool == "spawn":
			draw_arc(snapped, 14.0, 0.0, TAU, 40,
				Color(SPAWN_COLOR, 0.5), 2.0)
		elif _tool != "erase":
			var color := _tool_color()
			match _shape:
				"circle":
					draw_circle(snapped, DEFAULT_RADIUS,
						Color(color, 0.15))
					draw_arc(snapped, DEFAULT_RADIUS, 0.0, TAU, 40,
						Color(color, 0.5), 1.0)
				"loop", "curve":
					draw_circle(snapped, 4.0, Color(color, 0.6))
				"tri":
					var ghost := Rect2(snapped - DEFAULT_SIZE * 0.5,
						DEFAULT_SIZE)
					var tri := triangle_polygon(ghost)
					draw_colored_polygon(tri, Color(color, 0.15))
					_draw_outline(tri, Color(color, 0.5))
				_:
					var ghost := Rect2(snapped - DEFAULT_SIZE * 0.5,
						DEFAULT_SIZE)
					draw_rect(ghost, Color(color, 0.15))
					draw_rect(ghost, Color(color, 0.5), false, 1.0)


func _draw_drag_preview() -> void:
	var color := _tool_color()
	match _shape:
		"circle":
			var radius := _drag_start.distance_to(_drag_end)
			draw_circle(_drag_start, radius, Color(color, 0.3))
			draw_arc(_drag_start, radius, 0.0, TAU, 48, color, 2.0)
			draw_circle(_drag_start, 3.0, color)
		"tri":
			var rect := Rect2(_drag_start, _drag_end - _drag_start).abs()
			var tri := triangle_polygon(rect)
			draw_colored_polygon(tri, Color(color, 0.35))
			_draw_outline(tri, color)
		_:
			var rect := Rect2(_drag_start, _drag_end - _drag_start).abs()
			draw_rect(rect, Color(color, 0.35))
			draw_rect(rect, color, false, 2.0)


func _draw_pending_preview() -> void:
	var color := _tool_color()
	var snapped := _hover.snapped(Vector2(SNAP, SNAP))
	if _shape == "loop":
		# Placed vertices, the live segment to the cursor and — from
		# the third vertex on — the ring that marks the closing click.
		for p in _pending:
			draw_circle(p, 4.0, color)
		var chain := _pending.duplicate()
		chain.append(snapped)
		draw_polyline(chain, Color(color, 0.8), 2.0)
		if _pending.size() >= 3:
			draw_arc(_pending[0], CLOSE_RADIUS, 0.0, TAU, 32,
				Color(color, 0.5), 2.0)
	else:
		# Curve: one point placed — a straight hint line; two placed —
		# the live curve bending toward the cursor (the future bend).
		if _pending.size() == 1:
			draw_line(_pending[0], snapped, Color(color, 0.6), 2.0)
			draw_circle(_pending[0], 4.0, color)
			draw_circle(snapped, 4.0, Color(color, 0.6))
		else:
			var live := PackedVector2Array([
				_pending[0], _pending[1], snapped])
			draw_colored_polygon(
				curve_strip_polygon(live, CURVE_THICKNESS),
				Color(color, 0.25))
			draw_circle(_pending[0], 4.0, color)
			draw_circle(_pending[1], 4.0, color)


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


## Issue #632: the upward-pointing triangle inscribed in the dragged
## box — base on the box's bottom edge, apex on its top edge.
static func triangle_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.end.x, rect.end.y),
		Vector2(rect.get_center().x, rect.position.y),
	])


## Point on the authoring quadratic bezier at t — pts is the stored
## click order [start, end, control].
static func curve_point(pts: PackedVector2Array,
		t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * pts[0] + 2.0 * u * t * pts[2] + t * t * pts[1]


## First derivative of curve_point — the curve's tangent direction.
static func curve_tangent(pts: PackedVector2Array,
		t: float) -> Vector2:
	var d := 2.0 * ((1.0 - t) * (pts[2] - pts[0])
		+ t * (pts[1] - pts[2]))
	return d if d.length() > 0.001 else Vector2.RIGHT


## The ground ribbon a curve authors: the bezier sampled CURVE_SAMPLES
## times and offset CURVE_THICKNESS/2 to both sides of the tangent
## normals — a closed strip polygon.
static func curve_strip_polygon(pts: PackedVector2Array,
		thickness: float) -> PackedVector2Array:
	if pts.size() < 3:
		return PackedVector2Array()
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in CURVE_SAMPLES + 1:
		var t := float(i) / float(CURVE_SAMPLES)
		var tangent := curve_tangent(pts, t)
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var p := curve_point(pts, t)
		top.append(p + normal * thickness * 0.5)
		bottom.append(p - normal * thickness * 0.5)
	var rev := bottom.duplicate()
	rev.reverse()
	top.append_array(rev)
	return top
