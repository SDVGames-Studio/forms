extends Node
## Regression check for issue #537 rework v5 (owner report 2026-11-14:
## "change the Color square's color to the team's actual color" +
## "Check the position of first Color square").
##
## The color square between the team name and the member grid must
## literally BE the team's actual color: the old ColorPickerButton
## inherited the menu theme's flat gray Button style and hid the color
## entirely. It must also sit in the same place in EVERY row — between
## name and grid, one fixed size, vertically centered (a taller 2x8
## tier stretched it before) — and still recolor the team for this
## game only, with Start persisting the original color.
##
## Run headless: godot --headless res://tests/test_issue537_v5.tscn
## Exit code 0 = pass.

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE537V5 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var saved_teams := GameConfig.teams.duplicate(true)
	var saved_path := GameConfig.level_path

	# A set whose colors would be invisible on a flat gray button:
	# team 1 dark olive (the owner's murky screenshot tone), teams 2
	# and 3 the palette pink/blue, shapes mixed, team 1 in the 2x8 tier
	# (6 members) so its row is the TALL one that stretched the square.
	GameConfig.teams = [
		{
			"label": "Team 1", "color": Color(0.478, 0.451, 0.353),
			"shape": "triangle", "names": ["A", "B", "C", "D", "E", "F"],
			"skill": 5, "friendly_fire": 0, "language": "en",
			"controller": "player",
		},
		{
			"label": "Team 2", "color": Color(0.75, 0.2, 0.45, 1),
			"shape": "square", "names": ["G"],
			"skill": 5, "friendly_fire": 0, "language": "en",
			"controller": "computer",
		},
		{
			"label": "Team 3", "color": Color(0.35, 0.6, 1, 1),
			"shape": "square", "names": ["H", "I"],
			"skill": 5, "friendly_fire": 0, "language": "en",
			"controller": "computer",
		},
	]
	GameConfig.save_teams()
	GameConfig.level_path = "res://scenes/levels/Level1.tscn"

	var menu: Node = (load("res://scenes/menus/LevelConfigMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	var rows := (menu.get_node("%TeamsList") as VBoxContainer).get_children()
	_check("three team rows built", rows.size() == 3)

	var swatches: Array = []
	for i in rows.size():
		var row := rows[i] as HBoxContainer
		var names: Array = []
		for child in row.get_children():
			names.append(child.get_class())
		# [Label, ColorRect, GridContainer, OptionButton, Button]
		_check("row %d order name|square|grid|controller|remove" % i,
			names == ["Label", "ColorRect", "GridContainer", "OptionButton", "Button"])
		var swatch := row.get_child(1) as ColorRect
		swatches.append(swatch)
		var want: Color = GameConfig.teams[i]["color"]
		_check("row %d square shows the team's actual color %s" % [i, want],
			swatch.color.is_equal_approx(want))
		_check("row %d square fixed 30x30, no stretch" % i,
			swatch.custom_minimum_size == Vector2(30, 30)
			and swatch.size_flags_vertical == Control.SIZE_SHRINK_CENTER)

	# Position: the square sits BETWEEN the name and the member grid in
	# every row, and the tall 2x8 first row keeps the same offsets.
	var first := (rows[0].get_child(1) as ColorRect)
	var second := (rows[1].get_child(1) as ColorRect)
	_check("every square left-aligned with the others",
		absf(first.position.x - second.position.x) < 0.5)
	_check("square vertically centered in the tall first row",
		absf((first.position.y + first.size.y * 0.5)
			- rows[0].size.y * 0.5) <= 1.0)
	_check("square size identical across rows",
		first.size == second.size)

	# Recolor through the popup path still works and stays per-game:
	# live set recolors, Start persists the ORIGINAL color.
	menu._open_color_picker(0, first)
	_check("picker popup opened with the team color",
		menu._color_popup != null and menu._color_popup.visible
		and menu._color_picker.color.is_equal_approx(Color(0.478, 0.451, 0.353)))
	_check("picker wired to recolor the live set",
		menu._color_picker.color_changed.get_connections().size() >= 1)
	# The engine emits color_changed on USER interaction (a code-set
	# color does not emit), so drive the wired path directly.
	menu._apply_team_color(0, Color(0.3, 0.8, 0.4))
	_check("live set recolored by the picker",
		(GameConfig.teams[0]["color"] as Color).is_equal_approx(Color(0.3, 0.8, 0.4)))
	menu._color_popup.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	# popup_closed rebuilds the rows — the square wears the new color.
	var rebuilt := (menu.get_node("%TeamsList") as VBoxContainer).get_children()[0].get_child(1) as ColorRect
	_check("square wears the picked color after close",
		rebuilt.color.is_equal_approx(Color(0.3, 0.8, 0.4)))
	_check("Start keeps the original for the save",
		(menu._game_identity[0]["color"] as Color).is_equal_approx(Color(0.478, 0.451, 0.353)))

	menu.queue_free()
	await get_tree().process_frame

	# Restore the pre-test world so the run leaves no trace.
	GameConfig.teams = saved_teams
	GameConfig.save_teams()
	GameConfig.level_path = saved_path

	if _fails.is_empty():
		print("ISSUE537_V5 PASS — color square = actual team color")
		get_tree().quit(0)
	else:
		print("ISSUE537_V5 FAIL — %d check(s): %s" % [_fails.size(), ", ".join(_fails)])
		get_tree().quit(1)
