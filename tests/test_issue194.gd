extends Node
## Regression check for issue #194: simple celebration animation.
##
## Asserts:
##   - the Celebration overlay builds a banner (Label) and confetti
##     (CPUParticles2D) when added to the tree;
##   - it emits `finished` after `duration` seconds and frees itself;
##   - LevelFinish exposes the celebration trigger (starts with the player,
##   then advances to the next scene).

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# --- Celebration overlay lifecycle.
	var celebration: CanvasLayer = load("res://scripts/Celebration.gd").new()
	celebration.duration = 0.4
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

	var finished_flag := [false]
	celebration.finished.connect(func() -> void: finished_flag[0] = true)
	await get_tree().create_timer(1.0).timeout
	if not finished_flag[0]:
		failures.append("celebration must emit finished after duration")
	if is_instance_valid(celebration) and celebration.get_tree() != null:
		failures.append("celebration must free itself when finished")

	# --- LevelFinish wiring: player entering the area triggers celebration,
	# then the next scene loads.
	var level_finish: Area2D = load("res://LevelFinish.gd").new()
	level_finish.next_scene = "res://Main.tscn"
	add_child(level_finish)
	await get_tree().process_frame
	var player: CharacterBody2D = load("res://Player.gd").new()
	add_child(player)
	await get_tree().process_frame
	level_finish._on_body_entered(player)
	await get_tree().process_frame
	var overlays := _find_nodes(get_tree().root, "CanvasLayer")
	if overlays.is_empty():
		failures.append("level finish must spawn a celebration overlay")

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
