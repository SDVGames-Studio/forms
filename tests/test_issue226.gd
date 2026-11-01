extends Node
## Regression check for issue #226: every default team has its own body
## shape and the levels actually stage the shapes (player team vs the
## computer team must differ).
##
## Run headless: godot --headless res://tests/test_issue226.tscn
## Exit code 0 = pass.

const LEVELS := ["res://Level.tscn", "res://LevelDuel.tscn"]


func _ready() -> void:
	var ok := true

	# Fresh defaults: distinct shape per team.
	GameConfig.teams = GameConfig.default_teams()
	var shapes: Array[String] = []
	for team in GameConfig.teams:
		shapes.append(str(team["shape"]))
	print("ISSUE226 default team shapes=", shapes)
	ok = ok and shapes.size() >= 2 and shapes[0] != shapes[1]
	ok = ok and shapes.has("square") and shapes.has("circle")

	# An NPC renders a non-square team shape: the ColorRect body hides
	# and a same-sized ShapeVisual body takes its place.
	var npc: CharacterBody2D = load("res://Npc.gd").new()
	add_child(npc)
	for i in 5:
		await get_tree().physics_frame
	npc.set_team_shape("circle")
	var visual := npc.get_node_or_null("VisualShape")
	print("ISSUE226 npc VisualShape=", visual != null,
		" shape=", visual.shape if visual else "-",
		" color_ok=", visual.shape_color == npc.team_color if visual else false,
		" rect_hidden=", not npc._visual.visible)
	ok = ok and visual != null and str(visual.shape) == "circle"
	ok = ok and visual.shape_color == npc.team_color
	ok = ok and not npc._visual.visible
	npc.queue_free()
	for i in 5:
		await get_tree().physics_frame

	# Levels: after GameConfig.apply the computer team's shape differs
	# from the player team's shape.
	for path in LEVELS:
		GameConfig.teams = GameConfig.default_teams()
		GameConfig._sync_from_teams()
		var level: Node = load(path).instantiate()
		add_child(level)
		for i in 10:
			await get_tree().physics_frame
		var enemy_shape := ""
		for figure in get_tree().get_nodes_in_group("enemy_team"):
			if figure.get("team_shape") != null:
				enemy_shape = str(figure.get("team_shape"))
		print("ISSUE226 ", path, " player=", GameConfig.team_shape,
			" enemy=", enemy_shape)
		ok = ok and enemy_shape != "" and enemy_shape != GameConfig.team_shape
		level.queue_free()
		for i in 5:
			await get_tree().physics_frame

	print("ISSUE226 ok=", ok)
	get_tree().quit(0 if ok else 1)
