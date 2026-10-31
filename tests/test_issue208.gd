extends Node
## Regression check for issue #208: Teams menu rework.
##
## Asserts the menu delivers the reworked flow end to end:
##   - the default set of teams = the teams that are in the levels, with
##     NEUTRAL names (owner rework: no "Player Team"/"Enemies" concept
##     in the configuration), listed in a DROP-DOWN below the header;
##   - picking a team in the drop-down edits it; the editor column is
##     scrollable (ScrollContainer present);
##   - "+ Add team" appends a team to the set and selects it;
##   - the members window shows every member as a clickable figure with
##     an editable name, plus a + button right of the rightmost member;
##     clicking a figure opens a delete confirmation that removes it;
##     the leftmost member stays first (order is turn order);
##   - the shape picker is graphical: one button per shape, the team's
##     shape stays the pressed one;
##   - "Save" persists the whole set to user://team.cfg and keeps the
##     single-team fields the levels apply in sync (slot order only:
##     teams[0] = the figures the player controls, teams[1] = the
##     computer team's AI parameters until in-game choice lands).
##
## Run headless: godot --headless res://tests/test_issue208.tscn
## Exit code 0 = pass.

const SHAPES := ["square", "circle", "triangle", "star", "ellipse"]


func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	DirAccess.remove_absolute("user://team.cfg")  # start from defaults
	var menu: Control = load("res://TeamMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame

	# --- Default set of teams = the teams that are in the levels, NEUTRAL.
	if GameConfig.teams.size() != 2:
		failures.append("default set must list the 2 level teams, got %d" % GameConfig.teams.size())
	else:
		if GameConfig.teams[0]["label"] != "Team 1":
			failures.append("teams[0] must have a neutral label, got %s" % GameConfig.teams[0]["label"])
		if GameConfig.teams[1]["label"] != "Team 2":
			failures.append("teams[1] must have a neutral label, got %s" % GameConfig.teams[1]["label"])

	# --- Teams sit in a drop-down below the header; the editor is scrollable.
	var team_select: OptionButton = menu.get_node("%TeamSelect")
	if team_select == null or team_select.item_count != 2:
		failures.append("team drop-down must list one item per team")
	elif team_select.selected != 0:
		failures.append("drop-down must start on the first team, got %d" % team_select.selected)
	elif team_select.get_item_text(1) != "Team 2":
		failures.append("drop-down items must be the team labels, got %s" % team_select.get_item_text(1))
	var scroll: ScrollContainer = menu.get_node("Column/Scroll")
	if scroll == null:
		failures.append("editing column must be inside a ScrollContainer")

	# --- Picking a team in the drop-down switches the edited team.
	team_select.select(1)
	team_select.item_selected.emit(1)
	await get_tree().process_frame
	if menu.get_node("%EditingLabel").text != "Editing: Team 2":
		failures.append("drop-down pick must edit that team, got %s" % menu.get_node("%EditingLabel").text)
	team_select.select(0)
	team_select.item_selected.emit(0)
	await get_tree().process_frame

	# --- Graphical shape picker: one button per shape, current one pressed.
	var picker: HBoxContainer = menu.get_node("%ShapePicker")
	if picker.get_child_count() != SHAPES.size():
		failures.append("shape picker must show all %d shapes graphically" % SHAPES.size())
	else:
		var pressed_shapes: Array[String] = []
		for button in picker.get_children():
			if button.toggle_mode and button.button_pressed:
				pressed_shapes.append(str(button.tooltip_text).to_lower())
		if pressed_shapes != ["square"]:
			failures.append("default shape must be pressed, got %s" % str(pressed_shapes))

	# --- Members window: 3 member cards, no + while at the level cap (3).
	var members_row: HBoxContainer = menu.get_node("%MembersRow")
	if members_row.get_child_count() != 3:
		failures.append("members window must show the 3 default members, got %d" % members_row.get_child_count())
	# Names are editable LineEdits under a clickable figure Button.
	var first_card: VBoxContainer = members_row.get_child(0)
	if not (first_card.get_child(0) is Button) or not (first_card.get_child(1) is LineEdit):
		failures.append("member card must be a clickable figure with an editable name")

	# --- Clicking a member's figure offers deletion; confirming removes it.
	(first_card.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	var dialog: ConfirmationDialog = menu.get_node("%DeleteDialog")
	if not dialog.visible:
		failures.append("clicking a member figure must open the delete dialog")
	else:
		dialog.confirmed.emit()
		await get_tree().process_frame
		var names: Array = GameConfig.teams[0]["names"]
		if names.size() != 2 or str(names[0]) != "Player 2":
			failures.append("confirmed delete must remove the FIRST member, order kept: %s" % str(names))

	# --- With room left, the + button reappears and adds one on the right.
	if members_row.get_child_count() != 3:  # 2 members + the + button
		failures.append("members window must show + right of the rightmost member, got %d" % members_row.get_child_count())
	else:
		(members_row.get_child(2) as Button).pressed.emit()
		await get_tree().process_frame
		if GameConfig.teams[0]["names"].size() != 3 \
				or str(GameConfig.teams[0]["names"][2]) != "Member 3":
			failures.append("+ must append a member on the right: %s" % str(GameConfig.teams[0]["names"]))

	# --- Editing a name in the window renames the member in place.
	var name_edit: LineEdit = (members_row.get_child(0) as VBoxContainer).get_child(1)
	name_edit.text_changed.emit("Hero")  # what an in-window name edit fires
	await get_tree().process_frame
	if GameConfig.teams[0]["names"][0] != "Hero":
		failures.append("name edit must update the member name, got %s" % str(GameConfig.teams[0]["names"][0]))

	# --- Graphical shape pick reaches the team.
	(picker.get_child(2) as Button).pressed.emit()  # triangle
	await get_tree().process_frame
	if GameConfig.teams[0]["shape"] != "triangle":
		failures.append("picking a shape graphically must set the team shape")

	# --- "+ Add team" appends a team to the set and selects it.
	(menu.get_node("%AddTeamButton") as Button).pressed.emit()
	await get_tree().process_frame
	if GameConfig.teams.size() != 3:
		failures.append("+ Add team must append a team, got %d" % GameConfig.teams.size())
	if team_select.item_count != 3 or team_select.selected != 2:
		failures.append("drop-down must show and select the new team")
	if menu.get_node("%EditingLabel").text != "Editing: Team 3":
		failures.append("new team must be selected for editing, got %s" % menu.get_node("%EditingLabel").text)

	# --- Save persists the set and syncs the fields levels apply.
	GameConfig.teams[0]["color"] = Color(0, 1, 1)
	GameConfig.teams[1]["skill"] = 9
	(menu.get_node("%SaveButton") as Button).pressed.emit()
	await get_tree().process_frame
	var cfg := ConfigFile.new()
	if cfg.load("user://team.cfg") != OK:
		failures.append("Save must write team.cfg")
	else:
		var saved: Array = cfg.get_value("teams", "set", [])
		if saved.size() != 3:
			failures.append("Save must persist the whole set, got %d teams" % saved.size())
		if GameConfig.team_shape != "triangle" or GameConfig.team_color != Color(0, 1, 1):
			failures.append("Save must sync the player team fields levels apply")
		if GameConfig.ai_skill != 9:
			failures.append("Save must take AI skill from the second team, got %d" % GameConfig.ai_skill)
		# Reload round-trip: the set comes back exactly as saved.
		GameConfig.teams = []
		GameConfig.load_teams()
		if GameConfig.teams.size() != 3 or GameConfig.teams[0]["shape"] != "triangle" \
				or str(GameConfig.teams[0]["names"][0]) != "Hero":
			failures.append("saved set must round-trip through load_teams: %s" % str(GameConfig.teams))

	menu.queue_free()
	DirAccess.remove_absolute("user://team.cfg")  # never leak state
	await get_tree().process_frame

	if failures.is_empty():
		print("TEST_ISSUE208 PASS")
	else:
		for failure in failures:
			print("TEST_ISSUE208 FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
