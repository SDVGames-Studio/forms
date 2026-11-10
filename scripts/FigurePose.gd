class_name FigurePose
extends RefCounted
## Issue #270: figure pose versus the level's gravity.
##
## The character's BOTTOM must face the ground whatever direction gravity
## pulls — on the circular arena (Level5) gravity points toward the disc
## centre, so figures walking the rim stand sideways or upside-down. The
## physics already follow that gravity (LevelTerrain.gravity_vector drives
## up_direction and the walk tangent), but the BODY VISUAL stayed vertical.
##
## This helper rotates only the children that REPRESENT the figure's body
## — the body visual (authored ColorRect, the ShapeVisual replacement or
## the collision capsule). The name label, health bar, shield, the debug
## TEXT (HP number, damage popup), the weapon and the camera keep the
## world-aligned frame so text stays readable, the held weapon keeps
## aiming in world space and the camera never tilts. The debug ARROW is
## the one exception (issue #298): it points at the TOP of the figure, so
## it rotates with the body — on the radial arena a sideways figure must
## show a sideways arrow, not the old always-world-up one.
##
## Note: Control is NOT a Node2D in Godot 4 (both extend CanvasItem), so
## the two branches set the same `rotation` through their own type; a
## Control also needs its pivot moved to the rect's centre for an
## in-place spin (default pivot is the top-left corner).
##
## On flat levels gravity is straight down, the target angle is 0 and the
## call is a no-op.


## Rotate the figure's body children so their bottom (+Y local) points
## along `grav`. Call every physics frame with the CURRENT gravity unit
## vector (see Player/Npc _physics_process); the direction changes
## smoothly as a figure walks around a disc, so the per-frame assignment
## reads as a smooth tilt, not a snap.
static func align_to_gravity(figure: Node2D, grav: Vector2) -> void:
	if grav.length_squared() < 0.5:
		return
	var target := grav.angle() - PI / 2.0
	for child in figure.get_children():
		# Issue #298: the debug arrow is a plain Node2D (not a body child)
		# but must follow the same tilt — it points at the figure's TOP,
		# which rotates with the body under tilted gravity.
		var arrow := child as Node2D
		if arrow != null and child.name == "DebugArrow":
			arrow.rotation = target
		if not is_body_child(child):
			continue
		var node2d := child as Node2D
		if node2d != null:
			node2d.rotation = target
			continue
		var control := child as Control
		if control != null:
			control.pivot_offset = control.size / 2.0
			control.rotation = target


## True for the children that depict/carry the figure's BODY geometry:
## collision shapes, ShapeVisual bodies and plain body ColorRects. The
## HUD rects (Shield, HealthBarBackground) are excluded by name; Labels,
## the Weapon node, the Camera and the debug attachments are not
## ColorRects/shapes and fall out on their own. Public so the regression
## test can pick the same set.
static func is_body_child(node: Node) -> bool:
	if node is CollisionShape2D or node is CollisionPolygon2D:
		return true
	if node.has_method("set_shape"):
		return true
	var rect := node as ColorRect
	if rect != null:
		return rect.name != "Shield" and rect.name != "HealthBarBackground"
	return false
