extends Node
## Regression check for issue #180: AI behavior configuration.
##
## The AI behavior parameters (skill, friendly-fire) belong to the TEAM
## configuration: they persist with the team, map onto the NPC difficulty
## bands and reach every computer figure; friendly fire passes through.
##
## Run headless: godot --headless res://tests/test_issue180.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var failures := 0

	# Skill bands map onto the NPC difficulty (0..3 easy, 4..7 normal,
	# 8..10 hard).
	var level := Node2D.new()
	add_child(level)
	for npc_name: String in ["Npc", "Npc2", "Npc3"]:
		var body := CharacterBody2D.new()
		body.name = npc_name
		body.set_script(load("res://Npc.gd"))
		level.add_child(body)

	GameConfig.enemy_count = 3
	GameConfig.ai_skill = 0
	GameConfig.ai_friendly_fire = 7
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame
	for npc_name in ["Npc", "Npc2", "Npc3"]:
		var npc: Node = level.get_node(npc_name)
		if int(npc.get("difficulty")) != 0:
			failures += 1
			push_error("FAIL: skill 0 must map to easy difficulty on %s" % npc_name)
		if int(npc.get("ai_friendly_fire")) != 7:
			failures += 1
			push_error("FAIL: friendly-fire 7 must reach %s" % npc_name)

	GameConfig.ai_skill = 5
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame
	if int(level.get_node("Npc").get("difficulty")) != 1:
		failures += 1
		push_error("FAIL: skill 5 must map to normal difficulty")
	GameConfig.ai_skill = 10
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame
	if int(level.get_node("Npc").get("difficulty")) != 2:
		failures += 1
		push_error("FAIL: skill 10 must map to hard difficulty")

	# Persistence round-trip: skill and friendly-fire live in team.cfg.
	GameConfig.ai_skill = 3
	GameConfig.ai_friendly_fire = 10
	GameConfig.save_team()
	GameConfig.ai_skill = 5
	GameConfig.ai_friendly_fire = 0
	GameConfig.load_team()
	if GameConfig.ai_skill != 3 or GameConfig.ai_friendly_fire != 10:
		failures += 1
		push_error("FAIL: AI parameters must persist with the team in team.cfg")

	# Restore defaults so other tests / runs start clean.
	GameConfig.ai_skill = 5
	GameConfig.ai_friendly_fire = 0
	GameConfig.save_team()

	if failures == 0:
		print("PASS: issue #180 AI behavior configuration applied")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
