extends Node
## Regression check for issue #137: the level configuration menu settings
## are applied to a level — extra teammates and enemies beyond the chosen
## sizes are removed and the chosen difficulty reaches the NPCs.
##
## Run headless: godot --headless res://tests/test_issue137.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var failures := 0

	# A stand-in level with the standard cast: Player + Teammate1/2 + 3 NPCs.
	var level := Node2D.new()
	add_child(level)
	for node_name: String in ["Player", "Teammate1", "Teammate2", "Npc", "Npc2", "Npc3"]:
		var body := CharacterBody2D.new()
		body.name = node_name
		body.set_script(load("res://Npc.gd") if node_name.begins_with("Npc") else null)
		level.add_child(body)

	GameConfig.team_size = 2
	GameConfig.enemy_count = 1
	GameConfig.difficulty = 2
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame

	if level.get_node_or_null(NodePath("Player")) == null:
		failures += 1
		push_error("FAIL: the hero must stay")
	if level.get_node_or_null(NodePath("Teammate1")) == null:
		failures += 1
		push_error("FAIL: Teammate1 must stay for team size 2")
	if level.get_node_or_null(NodePath("Teammate2")) != null \
			and not level.get_node("Teammate2").is_queued_for_deletion():
		failures += 1
		push_error("FAIL: Teammate2 must be removed for team size 2")
	if level.get_node_or_null(NodePath("Npc")) == null:
		failures += 1
		push_error("FAIL: Npc must stay for enemy count 1")
	for extra: String in ["Npc2", "Npc3"]:
		var node := level.get_node_or_null(NodePath(extra))
		if node != null and not node.is_queued_for_deletion():
			failures += 1
			push_error("FAIL: %s must be removed for enemy count 1" % extra)
	if int(level.get_node("Npc").get("difficulty")) != 2:
		failures += 1
		push_error("FAIL: chosen difficulty must reach the NPC")

	if failures == 0:
		print("PASS: issue #137 level configuration applied")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
