extends Node
## Regression check for issue #194: simple celebration animation.
##
## Asserts:
##   - the Celebration overlay builds a banner (Label) and confetti
##     (CPUParticles2D) when added to the tree;
##   - it emits `finished` after `duration` seconds and frees itself.
##   - Issue #194 rework (owner, 2026-11-27): the default animation is
##     longer than the old 2.0 s, and before the end the emitter stops
##     spawning and gravity surges so the remaining confetti flies away
##     out through the bottom edge.
##
## Issue #614 removed the Finish trigger area — the celebration-on-win
## wiring is covered by tests/test_issue614.gd.

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# --- Rework: the default animation got a little longer.
	var probe: CanvasLayer = load("res://scripts/Celebration.gd").new()
	if probe.duration <= 2.0:
		failures.append("default duration must be longer than the old 2.0 s, got %s" % probe.duration)
	probe.free()

	# --- Celebration overlay lifecycle.
	var celebration: CanvasLayer = load("res://scripts/Celebration.gd").new()
	celebration.duration = 2.0
	add_child(celebration)
	await get_tree().process_frame

	if celebration.get_tree() == null:
		failures.append("celebration must be inside the tree")
	var labels := _find_nodes(celebration, "Label")
	var particles := _find_nodes(celebration, "CPUParticles2D")
	if labels.size() != 1:
		failures.append("expected exactly 1 banner label, got %d" % labels.size())
	if particles.size() != 1:
		failures.append("expected exactly 1 confetti emitter, got %d" % particles.size())
	var label: Label = labels[0] if labels.size() == 1 else null
	if label != null and label.text.is_empty():
		failures.append("banner label must have text")
	var confetti: CPUParticles2D = particles[0] if particles.size() == 1 else null
	if confetti != null and not confetti.emitting:
		failures.append("confetti must be raining while the animation plays")

	# --- Fly-away: past the rain cutoff the emitter must have stopped
	# spawning and gravity must be surging downward, so the remaining
	# particles sweep out through the bottom edge before the finish.
	await get_tree().create_timer(1.0).timeout
	if confetti != null and is_instance_valid(confetti):
		if confetti.emitting:
			failures.append("confetti must stop spawning before the animation ends")
		if confetti.gravity.y <= 500.0:
			failures.append("confetti gravity must surge during the fly-away, got %s" % confetti.gravity.y)

	var finished_flag := [false]
	celebration.finished.connect(func() -> void: finished_flag[0] = true)
	await get_tree().create_timer(1.6).timeout
	if not finished_flag[0]:
		failures.append("celebration must emit finished after duration")
	if is_instance_valid(celebration) and celebration.get_tree() != null:
		failures.append("celebration must free itself when finished")

	if failures.is_empty():
		print("ISSUE194 OK: simple celebration animation")
	else:
		for f in failures:
			print("ISSUE194 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _find_nodes(root: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != root and node.get_class() == type_name:
			found.append(node)
		for child in node.get_children():
			stack.append(child)
	return found
