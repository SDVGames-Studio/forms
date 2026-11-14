extends Node
## Regression check for issue #537 (LevelConfigMenu rework):
##  - The "Your team size" and "Enemy count" rows are GONE (since #521
##    the team set drives the level, so the spinboxes left the menu).
##  - Every team row shows the NAME on the left followed by the little
##    member GRID: one square per member of the team (names drives the
##    count), each square a recessed cell whose ShapeVisual wears the
##    team's shape and color — a triangle team shows triangles.
##
## Run headless: godot --headless res://tests/test_issue537.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://scenes/menus/LevelConfigMenu.tscn")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE537 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var saved_teams := GameConfig.teams
	GameConfig.load_teams()
	var menu := MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame

	_check("the team-size row is gone",
		menu.get_node_or_null("%TeamSizeSpinBox") == null)
	_check("the enemy-count row is gone",
		menu.get_node_or_null("%EnemyCountSpinBox") == null)

	var list: VBoxContainer = menu.get_node("%TeamsList")
	var team_count := GameConfig.teams.size()
	var rows := 0
	for row in list.get_children():
		if row is HBoxContainer:
			rows += 1
			var team: Dictionary = GameConfig.teams[rows - 1]
			var first := row.get_child(0)
			_check("team %d name sits on the left" % rows,
				first is Label and first.text == str(team["label"]))
			var grid: GridContainer = null
			for child in row.get_children():
				if child is GridContainer:
					grid = child
			_check("team %d carries a member grid" % rows, grid != null)
			if grid == null:
				continue
			_check("team %d grid has one square per member" % rows,
				grid.get_child_count() == team["names"].size())
			var shape_cells := 0
			for cell in grid.get_children():
				for cell_child in cell.get_children():
					if cell_child.get_script() != null \
							and str(cell_child.get("shape")) == str(team["shape"]) \
							and cell_child.get("shape_color") == team["color"]:
						shape_cells += 1
			_check("team %d squares wear the team's shape and color" % rows,
				shape_cells == team["names"].size())
	menu.queue_free()
	_check("one row per configured team", rows == team_count)
	GameConfig.teams = saved_teams

	if _fails.is_empty():
		print("PASS: issue #537 level-config team rows reworked")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % _fails.size())
		get_tree().quit(1)
