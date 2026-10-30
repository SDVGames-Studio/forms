extends Node
## Issue #178 regression test: the health bar background must not be
## converted into a second body shape (the "double shapes" bug).

func _ready() -> void:
	var failures: Array[String] = []
	GameConfig.team_shape = "star"
	GameConfig.team_color = Color.RED
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	for member in get_tree().get_nodes_in_group("player_team"):
		var shapes := 0
		for child in member.get_children():
			if child is Control and child.has_method("set_shape"):
				shapes += 1
		if shapes != 1:
			failures.append("%s has %d shape visuals, expected 1" % [member.name, shapes])
		var bar := member.get_node_or_null("HealthBarBackground") as ColorRect
		if bar == null or not bar.visible:
			failures.append("%s health bar background missing or hidden" % member.name)
	if failures.is_empty():
		print("TEST_ISSUE178 PASS")
	else:
		for failure in failures:
			print("TEST_ISSUE178 FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
