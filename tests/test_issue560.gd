extends Node
## Regression check for issue #560: every character in the game uses the
## new visual system (the modular character), and the legacy ShapeVisual
## script is gone.
##
##  1. FULL MIGRATION: no production script or scene references the
##     legacy ShapeVisual script, and the file itself is deleted — no
##     unused legacy character visuals remain;
##  2. EVERY SHAPE: apply_team_look dresses the modular character in
##     every gameplay silhouette (square, circle, triangle, star,
##     ellipse) with the team color — the same call the gameplay
##     figures (Player/Npc, issue #556) use;
##  3. PERSONALITIES: distinct member indices rest in distinct moods
##     (the menu cards and level-config cells pass the same index the
##     gameplay figures use, so one team reads as several characters);
##  4. MENUS: TeamMenu (shape picker + member cards) and the
##     LevelConfigMenu member grid draw their figure previews with the
##     modular character, not the legacy shape.
##
## Run headless: godot --headless res://tests/test_issue560.tscn
## Exit code 0 = pass.

const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")
const TeamMenuScene := preload("res://scenes/menus/TeamMenu.tscn")
const LevelConfigMenuScene := preload("res://scenes/menus/LevelConfigMenu.tscn")

const GAME_SHAPES := ["square", "circle", "triangle", "star", "ellipse"]
const PICKER_FACE := Color(0.9, 0.9, 0.95)

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _modular_visuals(under: Node) -> Array:
	var found: Array = []
	for child in under.get_children():
		if child.get_script() == VisualScript:
			found.append(child)
		found.append_array(_modular_visuals(child))
	return found


func _ready() -> void:
	# --- 1) the legacy visual system is fully retired ---------------------
	_check(not FileAccess.file_exists("res://scripts/ShapeVisual.gd"),
			"the legacy ShapeVisual script is deleted")
	var menu := TeamMenuScene.instantiate()
	add_child(menu)
	var config_menu := LevelConfigMenuScene.instantiate()
	add_child(config_menu)
	for source in ["res://scripts/TeamMenu.gd", "res://scripts/LevelConfigMenu.gd",
			"res://scripts/Player.gd", "res://scripts/Npc.gd"]:
		var text := FileAccess.get_file_as_string(source)
		_check(not text.contains("res://scripts/ShapeVisual.gd"),
				"%s no longer loads the legacy visual" % source)

	# --- 2) every gameplay shape dresses the modular character -----------
	var team_color := Color(0.35, 0.75, 0.95)
	for i in GAME_SHAPES.size():
		var figure: Control = VisualScript.new()
		figure.apply_team_look(team_color, GAME_SHAPES[i], i)
		add_child(figure)
		_check(figure.body_shape == GAME_SHAPES[i],
				"%s team look dresses the modular character" % GAME_SHAPES[i])
		_check(figure.body_color == team_color,
				"%s team look applies the team color" % GAME_SHAPES[i])
		_check(figure.has_expression(),
				"%s team look sets a resting personality" % GAME_SHAPES[i])

	# --- 3) distinct members rest in distinct moods -----------------------
	var moods: Array = []
	for i in GAME_SHAPES.size():
		moods.append(VisualScript.personality_for_index(i))
	var unique := {}
	for mood in moods:
		unique[mood] = true
	_check(unique.size() >= 4,
			"member indices spread across distinct personalities")
	_check(VisualScript.personality_for_index(0)
			!= VisualScript.personality_for_index(1),
			"two team members do not share one resting face")

	# --- 4) the menus preview the REAL characters -------------------------
	# TeamMenu: 5 shape-picker buttons (the light-gray neutral faces)...
	var picker_shapes := {}
	var member_faces: Array = []
	for visual in _modular_visuals(menu):
		if visual.body_color == PICKER_FACE:
			picker_shapes[visual.body_shape] = true
		elif visual.has_expression():
			member_faces.append(visual)
	_check(picker_shapes.size() == GAME_SHAPES.size(),
			"the shape picker previews every silhouette as a modular character")
	# ...and one expressive modular figure per member of the selected team.
	var team_shape := str(GameConfig.teams[0].get("shape", "square"))
	for face in member_faces:
		_check(face.body_shape == team_shape,
				"a member card keeps the team silhouette")
	_check(member_faces.size()
			== GameConfig.teams[0].get("names", []).size(),
			"every member card is an expressive modular character")
	# The level-config grid cells are modular characters too.
	_check(not _modular_visuals(config_menu).is_empty(),
			"the level-config member grid draws modular characters")
	for visual in _modular_visuals(config_menu):
		_check(visual.has_expression(),
				"every level-config figure rests in its personality")

	# A frame so every queued draw pass really runs headless.
	await get_tree().process_frame
	_check(is_instance_valid(menu) and is_instance_valid(config_menu),
			"the draw pass leaves the menus alive")

	if failures == 0:
		print("PASS: issue #560 full migration to the new visual system")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
