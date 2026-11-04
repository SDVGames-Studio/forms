class_name HudPose
extends RefCounted
## Issue #311: the per-figure HUD versus the CURRENT view frame.
##
## Issue #270 deliberately kept the name label, the health bar and the
## debug text world-aligned so text stays readable — correct while the
## view itself was world-aligned (STATIC camera). Issue #289 added the
## CHARACTER camera: the view rotates with the figure's gravity frame,
## so world-aligned HUD text renders TILTED on screen — upside-down
## after a central-line flip, sideways on a disc rim.
##
## The HUD must live in the coordinate system the view CURRENTLY shows:
## every HUD child (a Control that is NOT a body child — the name label,
## the health bar background + fill, the shield, the debug HP number and
## the damage popup) is rotated by the ACTIVE camera's rotation each
## frame. The camera eases its angle (ZoomCamera.ROTATION_SMOOTH), so the
## per-frame assignment rides the same ease and the text never lags the
## view by more than a frame. With the static camera the target is 0 and
## everything stays exactly as before.
##
## Issue #311 rework: the pivot is the FIGURE ORIGIN, not the rect's
## centre. The HUD rects are authored around the figure's origin in the
## world frame (name above the head, bar and debug HP under it, damage
## popup above-right). Spinning each rect around its own centre kept
## those WORLD-frame offsets, so under the rotated character camera the
## whole cluster slid around the figure — after a 180° flip the names
## and HP sat BELOW the figures on screen. Rotating each rect around the
## figure origin carries the authored offset into the view frame along
## with the text, so on screen the HUD sits exactly where the static
## camera shows it, whatever the view rotation.


## Rotate the figure's HUD children so they render upright on screen at
## their authored spot in the coordinate system the current view shows.
## Call every physics frame, right after FigurePose.align_to_gravity
## (see Player/Npc _physics_process).
static func align_to_view(figure: Node) -> void:
	var viewport := figure.get_viewport()
	var camera := viewport.get_camera_2d() if viewport != null else null
	var target := camera.rotation if camera != null else 0.0
	for child in figure.get_children():
		var control := child as Control
		if control == null or FigurePose.is_body_child(control):
			continue
		# A Control rotates around `pivot_offset`, and the point at
		# `position + pivot_offset` in figure space stays FIXED. With the
		# pivot at -position that fixed point is the figure's origin, so
		# the rect orbits the figure exactly like the body does.
		control.pivot_offset = -control.position
		control.rotation = target


## True for the children that make up a figure's on-screen HUD — the
## name label, the health bar, the shield and the debug text. Symmetric
## with FigurePose.is_body_child (that one answers "is this the body?";
## this one answers "is this the HUD?"). Public so the regression test
## can pick the same set.
static func is_hud_child(node: Node) -> bool:
	if node is CollisionShape2D or node is CollisionPolygon2D:
		return false
	if node.has_method("set_shape"):
		return false
	return node is Control and not FigurePose.is_body_child(node)
