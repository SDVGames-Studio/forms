extends Node
## Issue #169 smoke test: team customisation persists and applies to levels.

func _ready() -> void:
	var failures: Array[String] = []
	# Customise and save.
	GameConfig.team_shape = "triangle"
	GameConfig.team_color = Color(0, 1, 0)
	GameConfig.member_names = ["Alpha", "Beta", "Gamma"]
	GameConfig.team_size = 2
	GameConfig.save_team()
	# Static fields round-trip through a fresh load.
	GameConfig.team_shape = "square"
	GameConfig.team_color = Color(1, 1, 1)
	GameConfig.member_names = ["1", "2", "3"]
	GameConfig.load_team()
	if GameConfig.team_shape != "triangle":
		failures.append("shape did not persist: " + GameConfig.team_shape)
	if GameConfig.team_color != Color(0, 1, 0):
		failures.append("color did not persist")
	if GameConfig.member_names[1] != "Beta":
		failures.append("names did not persist: " + str(GameConfig.member_names))
	# Level applies team size + customisation.
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame
	var members := get_tree().get_nodes_in_group("player_team")
	if members.size() != 2:
		failures.append("expected 2 members, got " + str(members.size()))
	for i in members.size():
		var member: Node = members[i]
		if member.get("display_name") != ["Alpha", "Beta"][i]:
			failures.append("member %d name wrong: %s" % [i, member.get("display_name")])
		if member.get("team_color") != Color(0, 1, 0):
			failures.append("member %d color not applied" % i)
		if member.get("team_shape") != "triangle":
			failures.append("member %d shape not applied" % i)
		var visual: ColorRect = null
		var shape_visual: Control = null
		for child in member.get_children():
			if child is ColorRect and child.name != "HealthBarBackground":
				visual = child
			elif child is Control and child.has_method("set_shape"):
				shape_visual = child
		if visual != null and visual.visible:
			failures.append("member %d square visual still visible" % i)
		if shape_visual == null:
			failures.append("member %d missing shape visual" % i)
	# Clean up the saved file so the test never leaks state.
	DirAccess.remove_absolute("user://team.cfg")
	if failures.is_empty():
		print("TEST_ISSUE169 PASS")
	else:
		for failure in failures:
			print("TEST_ISSUE169 FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
