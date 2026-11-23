extends Control
## Editing canvas for the level editor (issues #464 and #632).
##
## Pure visual authoring: ground pieces and spawn points are stored as
## data (no physics) and drawn in code with the same colors the ground
## scripts use for themselves. The canvas shows a fixed 1152x648
## logical level space (the game's base viewport) through a movable,
## zoomable CAMERA (issue #675) that by default fits the rectangle its
## container gives it — mouse input is translated back into level
## coordinates, so drawing feels the same at any scale.
##
## Issue #675 — the view CAMERA over the level map: the mouse wheel
## zooms toward the cursor (clamped to 0.5x–4x of the fitted view) and
## a MIDDLE- or RIGHT-button drag pans. Zoomed out the level stays
## centered; zoomed in the offset clamps so the map never leaves the
## viewport. Edit hit distances (handles, outlines, the loop-closing
## radius) and the handle dots keep their ON-SCREEN size at any zoom,
## and the editor's RESET VIEW button restores the fitted whole-map
## view.
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
## Issue #673 — the BRUSH shape: a click-drag stroke paints ground
## cell by cell (one snapped 32 px grid cell per step, the drag
## interpolated so fast strokes leave no gaps) in the ground kind
## the tool column selects. A cell paints only where no piece
## covers it yet (any kind), so strokes never stack duplicates or
## overlap existing ground — erase first to repaint a cell in the
## other kind. (Uniting the painted cells into bigger pieces is
## issue #638, a separate work order.)
##
## Issue #639 EDIT tool — every placed figure gets clickable, movable
## points: with the tool active each piece draws its handles (the
## figure's own points: four corners for a rect, the three vertices
## of a tri, the centre and right-edge point for a circle, the stored
## vertices for loop/curve) and dragging one moves ONLY that point —
## every other point stays exactly where it was (#639 rework). A
## rect/tri corner drag frees the box: the piece becomes a loop
## polygon (the level format's free-form shape) keeping its current
## points, and just the dragged point moves. The circle centre handle
## carries the whole disc along (a circle's position IS its centre),
## the circle edge handle sets the radius, loop/curve vertices move
## freely — all snapped to the same grid, kept inside the level space.
##
## Issue #640 — the EDIT tool also ADDS points: a click on a
## figure's OUTLINE (away from the handles) inserts a vertex right
## there. A loop gains the point on the clicked edge; rect / tri /
## circle / curve figures first become free loop polygons keeping
## their current outline (a circle's disc is sampled to
## ADD_DISC_SEGMENTS corners, a curve's ribbon to ADD_CURVE_SAMPLES
## steps per side, so their shape survives) and then gain the point.
## A ring preview follows the nearest edge under the cursor, so the
## add spot is discoverable before the click.
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
## Issue #639: how near the cursor must be to grab an edit handle
## (level-space pixels) and how big the handle dots draw.
const HANDLE_GRAB := 18.0
const HANDLE_SIZE := 4.0
## Issue #640: how near the cursor must be to a figure's OUTLINE for
## an add-point click, and how finely a circle's disc / a curve's
## ribbon are sampled when such a figure becomes an editable loop.
const EDGE_GRAB := 14.0
const ADD_DISC_SEGMENTS := 12
const ADD_CURVE_SAMPLES := 8
## Issue #632: the ground ribbon a bezier curve authors and how finely
## it is sampled (CustomLevel builds the same strip).
const CURVE_THICKNESS := 48.0
const CURVE_SAMPLES := 24
const ERASE_RADIUS := 20.0
const BG_COLOR := Color(0.08, 0.09, 0.12, 1)
## Issue #675: the void behind the level map when the camera looks
## past its edges, and the camera's zoom limits / wheel step (1.0 =
## the whole level fitted into the canvas).
const VOID_COLOR := Color(0.05, 0.055, 0.08, 1)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.2
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
## Issue #633: the level's optional ground PICTURE — a background
## image chosen in the editor (kept as its PNG bytes so level files
## can embed it) that fills every ground piece; the kind-colored
## outline keeps indestructible/destructible readable.
var _pic: Texture2D = null
var _pic_name := ""
var _pic_png := PackedByteArray()
## Issue #639: the edit-tool grab (indices into _pieces and that
## piece's handle list) and the handle under the cursor, for
## highlighting. -1 = none.
var _grab_piece := -1
var _grab_handle := -1
var _hover_piece := -1
var _hover_handle := -1
## Issue #640: where an add-point click would land right now (the
## snapped point on the nearest outline edge); negative = none.
var _add_preview := Vector2(-1000, -1000)
## Issue #675: the view camera — a zoom multiplier over the fitted
## view (1.0 = whole level), the level-space point at the canvas's
## top-left corner, and whether a middle/right drag is panning now.
var _view_zoom := 1.0
var _view_offset := Vector2.ZERO
var _panning := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_update_view)
	_update_view()
	queue_redraw()


## Issue #675: canvas pixels per level pixel under the camera — the
## container's fit scale times the zoom (ONE until laid out).
func _view_scale() -> Vector2:
	if size.x <= 1.0 or size.y <= 1.0:
		return Vector2.ONE
	return size / CANVAS_SIZE * _view_zoom


## Issue #675: clamp the camera. Zoomed OUT the visible span exceeds
## the level, so the map centers; zoomed IN the offset pans inside it
## and the map always covers the viewport.
func _update_view() -> void:
	var visible := CANVAS_SIZE / _view_zoom
	if visible.x >= CANVAS_SIZE.x:
		_view_offset.x = (CANVAS_SIZE.x - visible.x) * 0.5
	else:
		_view_offset.x = clampf(_view_offset.x, 0.0,
			CANVAS_SIZE.x - visible.x)
	if visible.y >= CANVAS_SIZE.y:
		_view_offset.y = (CANVAS_SIZE.y - visible.y) * 0.5
	else:
		_view_offset.y = clampf(_view_offset.y, 0.0,
			CANVAS_SIZE.y - visible.y)
	queue_redraw()


func get_view_zoom() -> float:
	return _view_zoom


func get_view_offset() -> Vector2:
	return _view_offset


## Issue #675: back to the fitted whole-map view (RESET VIEW).
func reset_view() -> void:
	_view_zoom = 1.0
	_view_offset = Vector2.ZERO
	_update_view()


## Issue #675: zoom by `factor`, keeping the level point under
## `anchor_view` (canvas-local pixels) under the cursor still.
func _zoom_at(factor: float, anchor_view: Vector2) -> void:
	var anchor_level := anchor_view / _view_scale() + _view_offset
	_view_zoom = clampf(_view_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_view_offset = anchor_level - anchor_view / _view_scale()
	_update_view()


## Issue #675: the level→canvas transform the whole map draws under
## (scale from the fit view + zoom, offset as the origin shift).
func _view_transform() -> Transform2D:
	var s := _view_scale()
	return Transform2D(Vector2(s.x, 0.0), Vector2(0.0, s.y),
		-_view_offset * s)


## Issue #675: the cursor in LEVEL coordinates under the camera.
func _level_mouse_position() -> Vector2:
	return get_local_mouse_position() / _view_scale() + _view_offset


## Issue #675: an edit hit distance in level px that stays the same
## SIZE ON SCREEN whatever the zoom (`px` is a screen-space radius).
func _screen_hit(px: float) -> float:
	return px / maxf(_view_scale().x, 0.001)


func set_tool(kind: String) -> void:
	_tool = kind
	release_handle()
	_hover_piece = -1
	_hover_handle = -1
	_add_preview = Vector2(-1000, -1000)
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
	if _grab_piece >= _pieces.size():
		release_handle()
	_add_preview = Vector2(-1000, -1000)
	queue_redraw()


func get_pieces() -> Array:
	return _pieces.duplicate(true)


func set_spawns(spawns: Array) -> void:
	_spawns = spawns.duplicate(true)
	queue_redraw()


func get_spawns() -> Array:
	return _spawns.duplicate(true)


## Issue #633: the ground picture (level-wide, both ground kinds).
func set_ground_picture(tex: Texture2D, pic_name: String,
		png: PackedByteArray) -> void:
	_pic = tex
	_pic_name = pic_name
	_pic_png = png
	queue_redraw()


func clear_ground_picture() -> void:
	_pic = null
	_pic_name = ""
	_pic_png = PackedByteArray()
	queue_redraw()


## The current ground picture as {texture, name, png}; empty when none.
func get_ground_picture() -> Dictionary:
	if _pic == null:
		return {}
	return {"texture": _pic, "name": _pic_name, "png": _pic_png}


func has_ground_picture() -> bool:
	return _pic != null


func clear_all() -> void:
	_pieces.clear()
	_spawns.clear()
	_dragging = false
	release_handle()
	_cancel_pending()
	_add_preview = Vector2(-1000, -1000)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Issue #675: the camera — the wheel zooms toward the cursor;
		# a middle/right press-and-drag pans (and any authoring drag in
		# progress is dropped so the two never fight over the click).
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(ZOOM_STEP, get_local_mouse_position())
			accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / ZOOM_STEP, get_local_mouse_position())
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE \
				or mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			if _panning:
				_dragging = false
				release_handle()
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# Issue #639: the edit tool grabs a handle instead of
			# authoring — searched with the RAW cursor position (the
			# snap grid would shift the hit test). Issue #640: a click
			# that lands on no handle but near a figure's OUTLINE adds
			# a vertex there instead.
			if _tool == "edit":
				if not grab_handle_at(_level_mouse_position()):
					add_point_at(_level_mouse_position())
			else:
				_press(_level_snap_mouse())
			accept_event()
		elif _dragging:
			_release(_level_snap_mouse())
			accept_event()
		elif _grab_piece >= 0:
			release_handle()
			accept_event()
	elif event is InputEventMouseMotion:
		# Issue #675: a middle/right drag pans the map instead of
		# authoring — the offset moves against the drag, like sliding
		# the paper under a magnifier.
		if _panning:
			_view_offset -= (event as InputEventMouseMotion).relative \
				/ _view_scale()
			_update_view()
			accept_event()
			return
		_hover = _level_mouse_position()
		if _dragging:
			if _shape == "brush":
				# Issue #673: the stroke keeps painting while dragged.
				brush_stroke_to(_level_snap_mouse())
			else:
				_drag_end = _level_snap_mouse()
		elif _grab_piece >= 0:
			drag_handle_to(_level_snap_mouse())
		elif _tool == "edit":
			_update_hover_handle(_level_mouse_position())
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
				"brush":
					brush_stroke_start(pos)
				_:
					_dragging = true
					_drag_start = pos
					_drag_end = pos
					queue_redraw()


func _press_pending(pos: Vector2) -> void:
	# Loop: clicking back on the marked first vertex closes the shape
	# (CLOSE_RADIUS keeps its size on screen whatever the zoom).
	if _shape == "loop" and _pending.size() >= 3 \
			and pos.distance_to(_pending[0]) <= _screen_hit(CLOSE_RADIUS):
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
		"brush":
			pass  # the stroke painted its cells during the drag
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


## Issue #673: start a brush stroke at level-space `pos` — the cell
## under the click paints immediately, the drag continues it (public:
## the UI test drives strokes directly, like the edit-tool handles).
func brush_stroke_start(pos: Vector2) -> void:
	_dragging = true
	_drag_start = pos.snapped(Vector2(SNAP, SNAP))
	_drag_end = _drag_start
	_brush_paint_to(_drag_start)


## Issue #673: continue the stroke to `pos` — paints every cell the
## straight segment from the last painted point crosses (half-cell
## steps, so a fast drag leaves no gap in the staircase).
func brush_stroke_to(pos: Vector2) -> void:
	if not _dragging:
		return
	_brush_paint_to(pos.snapped(Vector2(SNAP, SNAP)))


## Issue #673: finish the stroke (the painted cells stay).
func brush_stroke_end() -> void:
	if _dragging:
		_dragging = false
		queue_redraw()


func _brush_paint_to(pos: Vector2) -> void:
	var steps := int(_drag_end.distance_to(pos) / (SNAP * 0.5))
	for i in steps + 1:
		_brush_paint_cell(_drag_end.lerp(pos,
			float(i) / float(maxi(steps, 1))))
	_drag_end = pos


## Issue #673: paint one grid cell at `pos` — skipped when any piece
## already covers the cell's centre, so a stroke never overlaps
## ground (its own earlier cells included); the cell clips to the
## level space like every authoring shape.
func _brush_paint_cell(pos: Vector2) -> void:
	var origin := pos.snapped(Vector2(SNAP, SNAP))
	var cell := Rect2(origin, Vector2(SNAP, SNAP)).intersection(
		Rect2(Vector2.ZERO, CANVAS_SIZE))
	if cell.size.x <= 0.0 or cell.size.y <= 0.0:
		return
	var center := cell.get_center()
	for piece in _pieces:
		if _piece_has_point(piece, center):
			return
	_pieces.append({"kind": _tool, "shape": "rect", "rect": cell})
	queue_redraw()


## Issue #639: the editable points of a piece — the figure's OWN
## points: the four corners for a rect, the three vertices for a tri
## (its bounding box stays an authoring-only concept), the centre and
## right-edge point for a circle, the stored vertices for loop/curve.
static func piece_handles(piece: Dictionary) -> PackedVector2Array:
	match str(piece.get("shape", "rect")):
		"circle":
			var crect: Rect2 = piece["rect"]
			var center := crect.get_center()
			var radius := minf(crect.size.x, crect.size.y) * 0.5
			return PackedVector2Array([center,
				center + Vector2(radius, 0.0)])
		"tri":
			return triangle_polygon(piece["rect"])
		"loop", "curve":
			return piece["points"]
		_:
			var rect: Rect2 = piece["rect"]
			return PackedVector2Array([
				rect.position,
				Vector2(rect.end.x, rect.position.y),
				rect.end,
				Vector2(rect.position.x, rect.end.y)])


## Issue #639: start dragging the handle nearest `pos` (level-space
## coordinates) when one is within HANDLE_GRAB. Later pieces win
## ties, matching erase's topmost convention. Returns true on a grab.
func grab_handle_at(pos: Vector2) -> bool:
	_grab_piece = -1
	_grab_handle = -1
	var best := _screen_hit(HANDLE_GRAB)
	for pi in _pieces.size():
		var handles := piece_handles(_pieces[pi])
		for hi in handles.size():
			var dist := pos.distance_to(handles[hi])
			if dist <= best:
				best = dist
				_grab_piece = pi
				_grab_handle = hi
	if _grab_piece >= 0:
		_hover_piece = _grab_piece
		_hover_handle = _grab_handle
	queue_redraw()
	return _grab_piece >= 0


## Issue #639: move the grabbed handle to `pos` (snapped by the
## caller), reshaping its piece.
func drag_handle_to(pos: Vector2) -> void:
	if _grab_piece < 0 or _grab_piece >= _pieces.size():
		return
	_apply_handle(_grab_piece, _grab_handle,
		pos.clamp(Vector2.ZERO, CANVAS_SIZE))
	queue_redraw()


## Issue #640: the outline a piece's add-point click works on — the
## closed polygon the drawn figure covers: the rect's corners, the
## tri's vertices, the loop's points; a circle's disc and a curve's
## ribbon are sampled (ADD_DISC_SEGMENTS corners / ADD_CURVE_SAMPLES
## steps per side) so their shape survives the conversion.
static func add_point_outline(piece: Dictionary) -> PackedVector2Array:
	match str(piece.get("shape", "rect")):
		"circle":
			var crect: Rect2 = piece["rect"]
			return _disc_points(crect.get_center(),
				minf(crect.size.x, crect.size.y) * 0.5, ADD_DISC_SEGMENTS)
		"curve":
			return curve_strip_polygon(piece["points"],
				CURVE_THICKNESS, ADD_CURVE_SAMPLES)
		_:
			return piece_handles(piece)


## Issue #640: the nearest figure OUTLINE edge within EDGE_GRAB of
## `pos`, as [piece index, insertion index, on-edge point]; an empty
## array when no edge is near. Later pieces win ties, matching the
## grab/erase topmost convention.
func _nearest_edge(pos: Vector2) -> Array:
	var best := _screen_hit(EDGE_GRAB)
	var found: Array = [-1, -1, Vector2.ZERO]
	for pi in _pieces.size():
		var outline := add_point_outline(_pieces[pi])
		var count := outline.size()
		if count < 2:
			continue
		for hi in count:
			var closest := Geometry2D.get_closest_point_to_segment(
				pos, outline[hi], outline[(hi + 1) % count])
			var dist := pos.distance_to(closest)
			if dist <= best:
				best = dist
				found = [pi, hi + 1, closest]
	return found if found[0] >= 0 else []


## Issue #640: add a vertex to the figure whose outline passes near
## `pos` — on the clicked edge, snapped to the grid like every other
## authoring click. Loops gain the point directly; rect / tri /
## circle / curve figures become free loop polygons keeping their
## current outline (see add_point_outline) and then gain it. Returns
## true when a point was added.
func add_point_at(pos: Vector2) -> bool:
	var edge := _nearest_edge(pos)
	if edge.is_empty():
		return false
	var piece: Dictionary = _pieces[edge[0]]
	var points := add_point_outline(piece)
	points.insert(edge[1], (edge[2] as Vector2).snapped(
		Vector2(SNAP, SNAP)).clamp(Vector2.ZERO, CANVAS_SIZE))
	piece.erase("rect")
	piece["shape"] = "loop"
	piece["points"] = points
	_add_preview = Vector2(-1000, -1000)
	queue_redraw()
	return true


## Issue #639: stop dragging (the piece keeps its new shape).
func release_handle() -> void:
	if _grab_piece >= 0:
		_grab_piece = -1
		_grab_handle = -1
		queue_redraw()


func _apply_handle(pi: int, hi: int, pos: Vector2) -> void:
	var piece: Dictionary = _pieces[pi]
	match str(piece.get("shape", "rect")):
		"circle":
			_apply_circle_handle(piece, hi, pos)
		"loop", "curve":
			var points: PackedVector2Array = piece["points"]
			if hi >= 0 and hi < points.size():
				points[hi] = pos
				piece["points"] = points
		_:
			_apply_free_point_handle(piece, hi, pos)


## Issue #639 rework: a rect/tri corner drag moves ONLY the grabbed
## point — every other point of the figure stays exactly still. The
## axis-aligned box can not express that, so the piece becomes a free
## loop polygon with its current points and the dragged point moves;
## CustomLevel builds loops of both ground kinds the same way.
func _apply_free_point_handle(piece: Dictionary, hi: int,
		pos: Vector2) -> void:
	var points := piece_handles(piece)
	if hi < 0 or hi >= points.size():
		return
	points[hi] = pos
	piece.erase("rect")
	piece["shape"] = "loop"
	piece["points"] = points


## Circle handles: index 0 moves the centre (radius kept, clamped
## inside the level), index 1 sets the radius from the distance.
func _apply_circle_handle(piece: Dictionary, hi: int, pos: Vector2) -> void:
	var rect: Rect2 = piece["rect"]
	var center := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.5
	if hi == 0:
		center = pos.clamp(Vector2(radius, radius),
			CANVAS_SIZE - Vector2(radius, radius))
	else:
		var limit := minf(minf(center.x, center.y),
			minf(CANVAS_SIZE.x - center.x, CANVAS_SIZE.y - center.y))
		radius = clampf(center.distance_to(pos), SNAP, maxf(SNAP, limit))
	piece["rect"] = Rect2(center - Vector2(radius, radius),
		Vector2(radius * 2.0, radius * 2.0))


func _update_hover_handle(pos: Vector2) -> void:
	_hover_piece = -1
	_hover_handle = -1
	_add_preview = Vector2(-1000, -1000)
	var best := _screen_hit(HANDLE_GRAB)
	for pi in _pieces.size():
		var handles := piece_handles(_pieces[pi])
		for hi in handles.size():
			if pos.distance_to(handles[hi]) <= best:
				best = pos.distance_to(handles[hi])
				_hover_piece = pi
				_hover_handle = hi
	# Issue #640: near no handle but near an outline edge — preview
	# where an add-point click would land (the handles win ties).
	if _hover_piece < 0:
		var edge := _nearest_edge(pos)
		if not edge.is_empty():
			_add_preview = (edge[2] as Vector2).snapped(
				Vector2(SNAP, SNAP)).clamp(Vector2.ZERO, CANVAS_SIZE)


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


func _level_snap_mouse() -> Vector2:
	return _level_mouse_position().snapped(Vector2(SNAP, SNAP))


func _tool_color() -> Color:
	if _tool == "indestructible":
		return IndestructibleGroundScript.COLOR
	return DestructibleGroundScript.COLOR


func _draw() -> void:
	# Issue #675: the void behind the map first (screen space), then
	# every level-space drawing under the camera transform.
	draw_rect(Rect2(Vector2.ZERO, size), VOID_COLOR)
	draw_set_transform_matrix(_view_transform())
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), BG_COLOR)
	_draw_grid()
	for piece in _pieces:
		_draw_piece(piece)
	for spawn in _spawns:
		var pos: Vector2 = spawn
		draw_arc(pos, 14.0, 0.0, TAU, 40, SPAWN_COLOR, 2.0)
		draw_circle(pos, 5.0, SPAWN_COLOR)
	_draw_preview()
	# Issue #639: the edit tool draws every piece's handles on top.
	if _tool == "edit":
		_draw_handles()
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), BORDER_COLOR, false, 2.0)
	draw_set_transform_matrix(Transform2D())


func _draw_piece(piece: Dictionary) -> void:
	var color: Color = IndestructibleGroundScript.COLOR \
		if piece["kind"] == "indestructible" \
		else DestructibleGroundScript.COLOR
	match str(piece.get("shape", "rect")):
		"circle":
			var rect: Rect2 = piece["rect"]
			var center := rect.get_center()
			var radius := minf(rect.size.x, rect.size.y) * 0.5
			if _pic != null:
				var disc := _disc_points(center, radius)
				draw_polygon(disc, _fill(disc.size()),
					_bounds_uvs(disc), _pic)
			else:
				draw_circle(center, radius, Color(color, 0.85))
			draw_arc(center, radius, 0.0, TAU, 48, color, 2.0)
		"tri":
			var pts := triangle_polygon(piece["rect"])
			_draw_shape_fill(pts, color)
		"loop":
			var loop_pts: PackedVector2Array = piece["points"]
			_draw_shape_fill(loop_pts, color)
		"curve":
			var strip := curve_strip_polygon(
					piece["points"], CURVE_THICKNESS)
			_draw_shape_fill(strip, color)
		_:
			var rect: Rect2 = piece["rect"]
			if _pic != null:
				draw_texture_rect(_pic, rect, false)
			else:
				draw_rect(rect, Color(color, 0.85))
			draw_rect(rect, color, false, 2.0)


## Issue #633: polygon piece fill — the ground picture stretched over
## the polygon bounds, or the translucent kind color; the kind-colored
## outline stays in both cases.
func _draw_shape_fill(pts: PackedVector2Array, color: Color) -> void:
	if _pic != null:
		draw_polygon(pts, _fill(pts.size()), _bounds_uvs(pts), _pic)
	else:
		draw_colored_polygon(pts, Color(color, 0.85))
	_draw_outline(pts, color)


## A regular polygon disc — the picture fill's geometry for circles
## (48 segments) and a converted circle's editable outline
## (ADD_DISC_SEGMENTS).
static func _disc_points(center: Vector2, radius: float,
		segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


## White per-vertex colors for a textured draw_polygon.
static func _fill(count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	for i in count:
		colors.append(Color.WHITE)
	return colors


## UVs mapping `points` onto a texture stretched over their bounding
## box (zero-size axes collapse so nothing divides by zero).
static func _bounds_uvs(points: PackedVector2Array) \
		-> PackedVector2Array:
	var aabb := Rect2(points[0], Vector2.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	var span := Vector2(
		aabb.size.x if aabb.size.x > 0.001 else 1.0,
		aabb.size.y if aabb.size.y > 0.001 else 1.0)
	var uvs := PackedVector2Array()
	for p in points:
		uvs.append((p - aabb.position) / span)
	return uvs


func _draw_outline(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, 2.0)


## Issue #639: the edit-tool handle dots — a dark base circle keeps
## them readable on any fill; the grabbed/hovered one lights up.
## Issue #640: with nothing grabbed or hovered, the ring on the
## nearest outline edge previews where a click adds a vertex.
func _draw_handles() -> void:
	# Issue #675: the dots keep their on-screen size at any zoom.
	var handle_size := HANDLE_SIZE / _view_zoom
	for pi in _pieces.size():
		var handles := piece_handles(_pieces[pi])
		for hi in handles.size():
			var active: bool = (pi == _grab_piece and hi == _grab_handle) \
				or (pi == _hover_piece and hi == _hover_handle)
			var color := Color(SPAWN_COLOR, 1.0) if active \
				else Color(1, 1, 1, 0.95)
			draw_circle(handles[hi], handle_size + 2.0,
				Color(0.08, 0.09, 0.12, 0.9))
			draw_circle(handles[hi], handle_size, color)
	if _grab_piece < 0 and _hover_piece < 0 \
			and _add_preview.x >= 0.0 and _add_preview.y >= 0.0:
		draw_arc(_add_preview, handle_size + 3.0, 0.0, TAU, 24,
			Color(SPAWN_COLOR, 0.9), 2.0)
		draw_circle(_add_preview, 2.5, Color(SPAWN_COLOR, 0.9))


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
		elif _tool != "erase" and _tool != "edit":
			var color := _tool_color()
			match _shape:
				"brush":
					var ghost := Rect2(snapped, Vector2(SNAP, SNAP)) \
						.intersection(Rect2(Vector2.ZERO, CANVAS_SIZE))
					if ghost.size.x > 0.0 and ghost.size.y > 0.0:
						draw_rect(ghost, Color(color, 0.3))
						draw_rect(ghost, Color(color, 0.7), false, 1.0)
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
	if _shape == "brush":
		return  # the live stroke paints cells — they are the preview
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


## The ground ribbon a curve authors: the bezier sampled `samples`
## times and offset CURVE_THICKNESS/2 to both sides of the tangent
## normals — a closed strip polygon.
static func curve_strip_polygon(pts: PackedVector2Array,
		thickness: float,
		samples: int = CURVE_SAMPLES) -> PackedVector2Array:
	if pts.size() < 3:
		return PackedVector2Array()
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in samples + 1:
		var t := float(i) / float(samples)
		var tangent := curve_tangent(pts, t)
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var p := curve_point(pts, t)
		top.append(p + normal * thickness * 0.5)
		bottom.append(p - normal * thickness * 0.5)
	var rev := bottom.duplicate()
	rev.reverse()
	top.append_array(rev)
	return top
