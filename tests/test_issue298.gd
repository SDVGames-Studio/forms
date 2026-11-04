extends Node
## Regression check for issue #298: the per-figure debug arrow must point
## at the TOP of the figure under ANY gravity. FigurePose.align_to_gravity
## now rotates the DebugArrow with the body children, so a figure standing
## on a tilted ground (radial arena, sloped grounds) shows a tilted arrow
## instead of the old always-world-up one. The debug TEXT (HP number,
## damage popup) keeps rotation 0 so it stays readable.
##
## Run headless: godot --headless res://tests/test_issue298.tscn
## Exit code 0 = pass.

const Pose := preload("res://scripts/FigurePose.gd")
const Info := preload("res://scripts/DebugInfo.gd")
const EPS := 0.05


func _ready() -> void:
	GameConfig.debug_mode = true
	var figure := CharacterBody2D.new()
	add_child(figure)
	var shape := CollisionShape2D.new()
	figure.add_child(shape)
	var rect := ColorRect.new()
	rect.name = "Body"
	figure.add_child(rect)
	Info.attach(figure)

	var arrow := figure.get_node_or_null(NodePath("DebugArrow")) as Node2D
	var hp := figure.get_node_or_null(NodePath("DebugHp"))
	print("ISSUE298 attached=", arrow != null and hp != null)
	var ok := arrow != null and hp != null
	if not ok:
		print("ISSUE298 ok=false")
		get_tree().quit(1)
		return

	# Tilted gravity cases: flat, 3/9 o'clock disc rims, a diagonal.
	var gravities := [
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2(0.6, 0.8).normalized(),
	]
	for grav in gravities:
		var target: float = grav.angle() - PI / 2.0
		Pose.align_to_gravity(figure, grav)
		# The ARROW follows the body tilt (the #298 fix)…
		if absf(wrapf(arrow.rotation - target, -PI, PI)) > EPS:
			print("FAIL arrow grav=", grav, " rot=", arrow.rotation,
					" want=", target)
			ok = false
		# …the body visual still tilts (the #270 behaviour)…
		if absf(wrapf(shape.rotation - target, -PI, PI)) > EPS:
			print("FAIL shape grav=", grav, " rot=", shape.rotation,
					" want=", target)
			ok = false
		# …and the debug text stays world-aligned/readable.
		if absf(float(hp.get("rotation"))) > EPS:
			print("FAIL hp label grav=", grav, " rot=", hp.get("rotation"))
			ok = false

	# Flat gravity: the arrow must sit at rotation 0, not a wrapped ±PI.
	Pose.align_to_gravity(figure, Vector2.DOWN)
	if absf(arrow.rotation) > EPS:
		print("FAIL flat arrow rot=", arrow.rotation)
		ok = false

	print("ISSUE298 ok=", ok)
	get_tree().quit(0 if ok else 1)
