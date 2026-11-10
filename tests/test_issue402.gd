extends Node
## Regression check for issue #402: with the debug mode on, every
## collision hitbox of a figure gets a transparent overlay — PURPLE for
## the first shape, a DIFFERENT palette color per further shape. The
## overlays are parented to the shape nodes themselves (authored offsets
## and the FigurePose tilt #270 are inherited) and lifted above the
## opaque body visual via z_index. With the debug mode off nothing is
## built at all (issue #252 behaviour unchanged).
##
## Run headless: godot --headless res://tests/test_issue402.tscn
## Exit code 0 = pass.

const Info := preload("res://scripts/DebugInfo.gd")
const Pose := preload("res://scripts/FigurePose.gd")
const EPS := 0.05


func _ready() -> void:
	var ok := true

	# Debug OFF: attach must build NOTHING (no debug text, no hitboxes).
	GameConfig.debug_mode = false
	var dark := CharacterBody2D.new()
	add_child(dark)
	dark.add_child(_capsule_holder("DarkShape"))
	Info.attach(dark)
	if dark.get_node_or_null(NodePath("DebugHp")) != null:
		print("FAIL debug-off still built the debug text")
		ok = false
	var dark_overlays := _overlay_count(dark)
	if dark_overlays != 0:
		print("FAIL debug-off built hitbox overlays: ", dark_overlays)
		ok = false

	# Debug ON with TWO different hitboxes: one overlay per shape node,
	# purple first, a different color second, drawn above the body.
	GameConfig.debug_mode = true
	var figure := CharacterBody2D.new()
	add_child(figure)
	var body := ColorRect.new()
	body.name = "BodyVisual"
	figure.add_child(body)
	var first := _capsule_holder("FirstShape")
	figure.add_child(first)
	var second := CollisionShape2D.new()
	second.name = "SecondShape"
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	second.shape = circle
	figure.add_child(second)
	Info.attach(figure)

	var overlay1 := first.get_node_or_null(NodePath("DebugHitbox0")) as Node2D
	var overlay2 := second.get_node_or_null(NodePath("DebugHitbox1")) as Node2D
	if overlay1 == null or overlay2 == null:
		print("FAIL hitbox overlays missing (", overlay1, ", ", overlay2, ")")
		ok = false
	else:
		var color1: Color = overlay1.get("overlay_color")
		var color2: Color = overlay2.get("overlay_color")
		# The FIRST hitbox is purple (the issue's main request).
		if not color1.is_equal_approx(Color(0.6, 0.2, 0.95, 1.0)):
			print("FAIL first hitbox not purple: ", color1)
			ok = false
		# A second, DIFFERENT hitbox gets a DIFFERENT color.
		if color1.is_equal_approx(color2):
			print("FAIL both hitboxes share one color: ", color1)
			ok = false
		if not color2.is_equal_approx(Info.hitbox_color(1)):
			print("FAIL second hitbox color != palette slot 1: ", color2)
			ok = false
		# Both draw ABOVE the opaque body visual (z_index > 0), so the
		# child order shape-vs-visual cannot hide them.
		if overlay1.z_index <= 0 or overlay2.z_index <= 0:
			print("FAIL overlays not lifted above the body (z ",
					overlay1.z_index, ", ", overlay2.z_index, ")")
			ok = false
		# Parented to the SHAPE node: they follow its FigurePose tilt.
		Pose.align_to_gravity(figure, Vector2.LEFT)
		var tilted: float = overlay1.get_global_transform().get_rotation()
		if absf(wrapf(tilted - first.rotation, -PI, PI)) > EPS:
			print("FAIL overlay tilt ", tilted, " vs shape ", first.rotation)
			ok = false

	# No overlay leaked onto the figure root or the body visual.
	if figure.get_node_or_null(NodePath("DebugHitbox0")) != null:
		print("FAIL overlay attached to the figure root")
		ok = false
	if _overlay_count(figure) != 2:
		print("FAIL figure carries ", _overlay_count(figure), " overlays, want 2")
		ok = false
	# The palette wraps instead of going out of range.
	if not Info.hitbox_color(Info.HITBOX_COLORS.size()).is_equal_approx(
			Info.hitbox_color(0)):
		print("FAIL palette does not wrap")
		ok = false

	print("ISSUE402 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _capsule_holder(holder_name: String) -> CollisionShape2D:
	var holder := CollisionShape2D.new()
	holder.name = holder_name
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 64.0
	holder.shape = capsule
	return holder


## Count DebugHitbox* nodes anywhere under `figure`.
func _overlay_count(figure: Node) -> int:
	var count := 0
	for child in figure.get_children():
		if String(child.name).begins_with("DebugHitbox"):
			count += 1
		count += _overlay_count(child)
	return count
