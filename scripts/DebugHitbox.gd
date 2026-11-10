extends Node2D
## Issue #402: transparent collision-hitbox overlay for the debug mode.
##
## DebugInfo.attach parents one overlay to EVERY CollisionShape2D /
## CollisionPolygon2D child of a figure. Being the SHAPE node's child, the
## overlay follows its transform exactly — authored offsets and the
## FigurePose gravity tilt (#270 rotates the collision nodes like the body
## visual). _draw reads the shape RESOURCE live, so runtime shape tweaks
## show up on the next redraw.
##
## The FIRST hitbox of a figure is transparent purple (the issue's main
## request); every further hitbox gets its own palette color so several
## different hitboxes stay visually separate (DebugInfo assigns the color).

## Palette color for this overlay; DebugInfo sets it (purple for the first
## shape, a different hue per further shape).
@export var overlay_color := Color(0.6, 0.2, 0.95, 1.0)

## The fill is what makes the hitbox read as "transparent"; the outline
## gives the shape a readable edge in the same hue.
const FILL_ALPHA := 0.3
const OUTLINE_ALPHA := 0.9
const OUTLINE_WIDTH := 2.0
## Circle/capsule outline resolution (draw_arc point count).
const ARC_POINTS := 32


func _ready() -> void:
	# z_index lifts the overlay ABOVE the opaque body visuals: the level
	# scenes disagree about the shape/visual child order (Level.tscn's
	# Player lists the visual first, Teammate1 the shape first), so tree
	# order alone would hide the hitbox behind the body half of the time.
	z_index = 1


func _draw() -> void:
	var fill := Color(overlay_color.r, overlay_color.g, overlay_color.b, FILL_ALPHA)
	var outline := Color(overlay_color.r, overlay_color.g, overlay_color.b, OUTLINE_ALPHA)
	var node := get_parent()
	if node is CollisionPolygon2D:
		_draw_poly((node as CollisionPolygon2D).polygon, fill, outline)
		return
	var holder := node as CollisionShape2D
	if holder == null or holder.shape == null:
		return
	var shape := holder.shape
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size
		var rect := Rect2(-size / 2.0, size)
		draw_rect(rect, fill)
		draw_rect(rect, outline, false, OUTLINE_WIDTH)
	elif shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius
		draw_circle(Vector2.ZERO, radius, fill)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, ARC_POINTS, outline, OUTLINE_WIDTH)
	elif shape is CapsuleShape2D:
		_draw_capsule(shape as CapsuleShape2D, fill, outline)
	elif shape is SegmentShape2D:
		var seg := shape as SegmentShape2D
		draw_line(seg.a, seg.b, outline, OUTLINE_WIDTH * 3.0)
	elif shape is ConvexPolygonShape2D:
		_draw_poly((shape as ConvexPolygonShape2D).points, fill, outline)
	elif shape is ConcavePolygonShape2D:
		var pts := (shape as ConcavePolygonShape2D).segments
		for i in range(0, pts.size() - 1, 2):
			draw_line(pts[i], pts[i + 1], outline, OUTLINE_WIDTH)


## Filled polygon plus a closed outline loop (CollisionPolygon2D and
## ConvexPolygonShape2D share the shape).
func _draw_poly(points: PackedVector2Array, fill: Color, outline: Color) -> void:
	if points.size() < 3:
		return
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(fill)
	draw_polygon(points, colors)
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, outline, OUTLINE_WIDTH)


## Capsule = straight rect middle + two half-circle caps. CapsuleShape2D
## height is the FULL end-to-end height, so the middle is height - 2r.
func _draw_capsule(cap: CapsuleShape2D, fill: Color, outline: Color) -> void:
	var body: float = maxf(cap.height - 2.0 * cap.radius, 0.0)
	draw_rect(Rect2(Vector2(-cap.radius, -body / 2.0),
			Vector2(2.0 * cap.radius, body)), fill)
	draw_circle(Vector2(0.0, -body / 2.0), cap.radius, fill)
	draw_circle(Vector2(0.0, body / 2.0), cap.radius, fill)
	draw_line(Vector2(-cap.radius, -body / 2.0),
			Vector2(-cap.radius, body / 2.0), outline, OUTLINE_WIDTH)
	draw_line(Vector2(cap.radius, -body / 2.0),
			Vector2(cap.radius, body / 2.0), outline, OUTLINE_WIDTH)
	draw_arc(Vector2(0.0, -body / 2.0), cap.radius, PI, TAU, ARC_POINTS,
			outline, OUTLINE_WIDTH)
	draw_arc(Vector2(0.0, body / 2.0), cap.radius, 0.0, PI, ARC_POINTS,
			outline, OUTLINE_WIDTH)
