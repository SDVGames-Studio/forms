extends Node
## Regression check for issue #537 (LevelConfigMenu rework + the
## owner's follow-up):
##  - The "Your team size" and "Enemy count" rows are GONE.
##  - Every team row shows the NAME on the left followed by the little
##    member GRID: one square per member wearing the team's shape and
##    color, CENTERED in its recessed gray square.
##  - The grid is tiered with a fixed footprint: 3 members -> 1x4
##    (cells 31.5 px), from the 4th member 2x8, from the 16th 4x16;
##    64 teammates is the hard maximum (the top tier runs full, no "+"),
##    1 the floor (a team always fields a figure).
##  - FREE squares carry a "+"; _add_member appends, _remove_member
##    drops (click wiring is exercised via the same handlers).
##  - "+ Add team" PULLS from the game's team set: with the default
##    two-team set the third level team is the FIRST team again, but
##    with a fresh, level-unused color (item 5).
##
## Run headless: godot --headless res://tests/test_issue537.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://scenes/menus/LevelConfigMenu.tscn")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE537 %s — %s" % ["ok" if ok else "FAIL", what])


## First GridContainer of team row `index` in the menu's TeamsList.
func _grid_of(menu: Node, index: int) -> GridContainer:
	var list: VBoxContainer = menu.get_node("%TeamsList")
	var seen := -1
	for row in list.get_children():
		if row is HBoxContainer:
			seen += 1
			if seen == index:
				for child in row.get_children():
					if child is GridContainer:
						return child
	return null


func _ready() -> void:
	var saved_teams := GameConfig.teams.duplicate(true)
	GameConfig.load_teams()
	var menu := MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame

	_check("the team-size row is gone",
		menu.get_node_or_null("%TeamSizeSpinBox") == null)
	_check("the enemy-count row is gone",
		menu.get_node_or_null("%EnemyCountSpinBox") == null)

	var team_count := GameConfig.teams.size()
	var rows := 0
	for row in menu.get_node("%TeamsList").get_children():
		if row is HBoxContainer:
			rows += 1
			var first := row.get_child(0)
			_check("team %d name sits on the left" % rows,
				first is Label and first.text == str(GameConfig.teams[rows - 1]["label"]))
	_check("one row per configured team", rows == team_count)

	# Default tier: 3 members play in the 1x4 grid — 3 filled squares
	# wearing the team's shape/color, one free "+" square, big cells.
	var grid := _grid_of(menu, 0)
	_check("team 0 carries a member grid", grid != null)
	var members: Array = GameConfig.teams[0]["names"]
	if grid != null:
		var shape_cells := 0
		var plus_cells := 0
		var centered := true
		for cell in grid.get_children():
			var is_shape := false
			for cell_child in cell.get_children():
				if cell_child.get_script() != null \
						and str(cell_child.get("shape")) == str(GameConfig.teams[0]["shape"]) \
						and cell_child.get("shape_color") == GameConfig.teams[0]["color"]:
					is_shape = true
					# Item 1: full-rect anchors with an inset keep the
					# shape centered in the gray square.
					if not (absf(cell_child.anchor_right - 1.0) < 0.01
							and absf(cell_child.anchor_bottom - 1.0) < 0.01
							and cell_child.offset_left > 0.0):
						centered = false
				if cell_child is Label and cell_child.text == "+":
					plus_cells += 1
			if is_shape:
				shape_cells += 1
		_check("1x4 tier: grid holds 4 squares for %d members" % members.size(),
			grid.get_child_count() == 4)
		_check("one square per member, one free spot",
			shape_cells == members.size() and plus_cells == 1)
		_check("shapes are centered in their squares", centered)
		_check("1x4 cells keep the grid footprint",
			absf(grid.get_child(0).custom_minimum_size.x - 31.5) < 0.01)

	# Item 3: appending a member — the 4th member bumps the grid to 2x8
	# (16 squares, smaller cells, same 132 px footprint).
	var count_before: int = members.size()
	menu._add_member(0)
	_check("add member appends a teammate",
		GameConfig.teams[0]["names"].size() == count_before + 1)
	grid = _grid_of(menu, 0)
	if grid != null:
		_check("4th member bumps the grid to the 2x8 tier",
			grid.get_child_count() == 16)
		_check("2x8 cells shrink to keep the footprint",
			absf(grid.get_child(0).custom_minimum_size.x - 14.75) < 0.01)

	# Item 2: clicking a filled square removes that teammate.
	var before: int = GameConfig.teams[0]["names"].size()
	menu._remove_member(0, 0)
	_check("remove member drops a teammate",
		GameConfig.teams[0]["names"].size() == before - 1)
	# The floor: one member always stays on a team.
	var solo: Array = ["Solo"]
	GameConfig.teams[1]["names"] = solo
	menu._rebuild_team_rows()
	menu._remove_member(1, 0)
	_check("floor: the last member of a team is kept",
		GameConfig.teams[1]["names"].size() == 1)

	# Item 4: the 4x16 tier is the ceiling — at 64 members the grid runs
	# full (no free spot) and nothing more can be appended.
	var many: Array = []
	for i in range(1, 64):
		many.append("Member %d" % i)
	GameConfig.teams[1]["names"] = many
	menu._rebuild_team_rows()
	await get_tree().process_frame
	grid = _grid_of(menu, 1)
	_check("63 members play in the 4x16 tier",
		grid != null and grid.get_child_count() == 64)
	menu._add_member(1)
	_check("64 teammates is the maximum",
		GameConfig.teams[1]["names"].size() == 64)
	menu._rebuild_team_rows()
	await get_tree().process_frame
	grid = _grid_of(menu, 1)
	if grid != null:
		var plus_at_max := 0
		for cell in grid.get_children():
			for cell_child in cell.get_children():
				if cell_child is Label and cell_child.text == "+":
					plus_at_max += 1
		_check("the full 4x16 tier has no free spot left", plus_at_max == 0)
	menu._add_member(1)
	_check("past 64 nothing is appended",
		GameConfig.teams[1]["names"].size() == 64)

	# Item 5: "+ Add team" pulls the next definition from the GAME's
	# team set — with the default two-team set the third level team is
	# the FIRST team again, but with a fresh, level-unused color.
	GameConfig.teams = GameConfig.default_teams()
	menu._game_team_set = GameConfig.teams.duplicate(true)
	menu._rebuild_team_rows()
	await get_tree().process_frame
	var used: Array = []
	for team in GameConfig.teams:
		used.append(team["color"])
	menu._on_add_team_pressed()
	var added_ok := GameConfig.teams.size() == 3
	if added_ok:
		var added: Dictionary = GameConfig.teams[2]
		_check("added team comes from the game's set",
			str(added["label"]) == str(menu._game_team_set[0]["label"])
			and str(added["shape"]) == str(menu._game_team_set[0]["shape"]))
		_check("added team wears a fresh color",
			not used.has(added["color"]))
		_check("added team starts at the default squad size",
			added["names"].size() == GameConfig.DEFAULT_TEAM_MEMBERS)
	else:
		_check("added team comes from the game's set", false)

	menu.queue_free()
	GameConfig.teams = saved_teams

	if _fails.is_empty():
		print("PASS: issue #537 level-config grid reworked (v2)")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % _fails.size())
		get_tree().quit(1)
