extends Node2D
class_name GravityFieldDebug
## Issue #290: debug gravity vector field overlay.
##
## Draws the level's gravity field as arrows on a world-space grid with a
## cell width of TWO character widths (2 x 64 = 128 px): at every grid
## point an arrow shows the direction gravity pulls a figure standing
## there — the SAME contract the figures follow (Player/Npc
## _physics_process): an authored central line is the level's gravity
## contract and beats terrain surface gravity (down above the line, up
## below it), otherwise the nearest indestructible surface bends gravity
## (LevelTerrain.gravity_at), otherwise gravity is straight down.
##
## Switched by the "Gravity Field" entry in the settings menu, next to the
## debug mode (GameConfig.debug_gravity_field). The camera creates exactly
## one overlay per level; if a second camera ever appears, the newer
## overlay removes itself (group dedup) so the field never draws twice.
## The node is top_level at the world origin: the grid lives in WORLD
## space and does not move or rotate with the view.

const Stats := preload("res://scripts/CharacterStats.gd")

## Issue #290: "grid with cell width equal to two character's width".
const CELL := 2.0 * Stats.BODY_SIZE
## Arrow geometry: a fixed length — the field shows DIRECTION (the
## magnitude is the same unit-vector x GRAVITY pull everywhere).
const ARROW_LENGTH := 44.0
const ARROW_WIDTH := 2.0
const HEAD_LENGTH := 9.0
const HEAD_SPREAD := 6.0
const FIELD_COLOR := Color(0.25, 0.85, 1.0, 0.6)
const POINT_RADIUS := 2.0

## The level's authored central line (y > 0), sampled from the figures
## once they are in the tree; -1 = not authored (or not known yet).
var _center_line_y := -1.0
## Last drawn world rect — the field is static, so redraw only when the
## visible region actually changes (camera move/zoom/rotate).
var _last_rect := Rect2(0.0, 0.0, -1.0, -1.0)


func _ready() -> void:
	top_level = true
	z_index = 50
	global_position = Vector2.ZERO
	# Dedup: every camera creates one overlay; the FIRST stays, any later
	# duplicate frees itself so arrows never draw on top of each other.
	add_to_group("gravity_field_debug")
	for other in get_tree().get_nodes_in_group("gravity_field_debug"):
		if other != self and is_instance_valid(other):
			queue_free()
			return


func _process(_delta: float) -> void:
	visible = GameConfig.debug_gravity_field
	if not visible:
		return
	_sample_center_line()
	var rect := _world_view_rect()
	if rect.position.distance_squared_to(_last_rect.position) > 1.0 \
			or rect.size.distance_squared_to(_last_rect.size) > 1.0:
		_last_rect = rect
		queue_redraw()


## The central line is authored per FIGURE (Player/Npc export), so read it
## from whichever team member is in the tree — the value is the same for
## every figure of the level (Level3/Level4 stage it on all of them).
func _sample_center_line() -> void:
	if _center_line_y > 0.0:
		return
	for group in ["player_team", "enemy_team"]:
		for fig in get_tree().get_nodes_in_group(group):
			var line = fig.get("center_line_y")
			if line != null and float(line) > 0.0:
				_center_line_y = float(line)
				return


## Unit gravity at an arbitrary world point — the figures' contract
## (central line > nearest terrain source > straight down).
func _gravity_at(world_pos: Vector2) -> Vector2:
	if _center_line_y > 0.0:
		return Vector2.DOWN if world_pos.y < _center_line_y else Vector2.UP
	if get_tree().get_first_node_in_group("gravity_source") != null:
		return LevelTerrain.gravity_at(get_tree(), world_pos)
	return Vector2.DOWN


func _draw() -> void:
	var rect := _world_view_rect()
	# Align the grid to multiples of CELL so the field stays pinned to the
	# WORLD (panning the view slides the window, never the arrows).
	var first := (rect.position / CELL).floor() * CELL
	var last := rect.position + rect.size
	var x := first.x
	while x <= last.x:
		var y := first.y
		while y <= last.y:
			var point := Vector2(x, y)
			_draw_arrow(point, _gravity_at(point))
			y += CELL
		x += CELL


## One grid point: a dot marks the sample point, a centered arrow shows
## the gravity direction there.
func _draw_arrow(point: Vector2, dir: Vector2) -> void:
	draw_circle(point, POINT_RADIUS, FIELD_COLOR)
	var half := dir * (ARROW_LENGTH * 0.5)
	var tip := point + half
	draw_line(point - half, tip, FIELD_COLOR, ARROW_WIDTH, true)
	var head := dir.orthogonal()
	var left := tip - dir * HEAD_LENGTH + head * HEAD_SPREAD
	var right := tip - dir * HEAD_LENGTH - head * HEAD_SPREAD
	draw_line(tip, left, FIELD_COLOR, ARROW_WIDTH, true)
	draw_line(tip, right, FIELD_COLOR, ARROW_WIDTH, true)


## The world-space rectangle currently visible in the viewport (the
## canvas transform already carries the camera's move/zoom/rotation, so
## the four transformed corners give the covered world region).
func _world_view_rect() -> Rect2:
	var vp := get_viewport()
	var xform: Transform2D = vp.get_canvas_transform().affine_inverse()
	var view := vp.get_visible_rect()
	var a := xform * view.position
	var rect := Rect2(a, Vector2.ZERO)
	rect = rect.expand(xform * view.position)
	rect = rect.expand(xform * view.end)
	rect = rect.expand(xform * Vector2(view.position.x, view.end.y))
	rect = rect.expand(xform * Vector2(view.end.x, view.position.y))
	return rect
