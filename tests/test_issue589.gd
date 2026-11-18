extends Node
## Regression check for issue #589 — the team's NAME is editable in the
## teams customization menu (TeamMenu):
##  - A "Team name" LineEdit sits under the "Editing:" caption and shows
##    the selected team's current name.
##  - Typing a non-empty name renames the team immediately: the label in
##    GameConfig.teams, the "Editing:" caption and the team drop-down
##    entry all follow.
##  - An emptied or whitespace-only field keeps the previous name.
##  - Switching teams in the drop-down reloads the field with the newly
##    selected team's name, and that team can be renamed too.
##
## Run headless: godot --headless res://tests/test_issue589.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://scenes/menus/TeamMenu.tscn")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE589 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var saved_teams := GameConfig.teams.duplicate(true)
	GameConfig.load_teams()
	var menu := MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame

	var name_edit: LineEdit = menu.get_node("%TeamNameEdit")
	var select: OptionButton = menu.get_node("%TeamSelect")
	var editing_label: Label = menu.get_node("%EditingLabel")
	var old_first := str(GameConfig.teams[0]["label"])

	_check("team name field exists and shows the team's name",
		name_edit != null and name_edit.text == old_first)

	# Typing a new name renames the team everywhere it is shown.
	name_edit.text_changed.emit("Yellow Ones")
	_check("typing renames the team in the config",
		str(GameConfig.teams[0]["label"]) == "Yellow Ones")
	_check("the Editing caption follows the rename",
		editing_label.text == "Editing: Yellow Ones")
	_check("the drop-down entry follows the rename",
		select.get_item_text(0) == "Yellow Ones")

	# Empty/whitespace keeps the previous name.
	name_edit.text_changed.emit("   ")
	_check("whitespace-only edit keeps the previous name",
		str(GameConfig.teams[0]["label"]) == "Yellow Ones")

	# Switching teams reloads the field; the other team renames too.
	var second := str(GameConfig.teams[1]["label"])
	select.item_selected.emit(1)
	await get_tree().process_frame
	_check("switching teams reloads the name field",
		name_edit.text == second)
	name_edit.text_changed.emit("Pink Crew")
	_check("the second team renames independently",
		str(GameConfig.teams[1]["label"]) == "Pink Crew"
		and str(GameConfig.teams[0]["label"]) == "Yellow Ones")
	_check("the first team keeps its renamed drop-down entry",
		select.get_item_text(0) == "Yellow Ones")

	menu.queue_free()
	GameConfig.teams = saved_teams

	if _fails.is_empty():
		print("PASS: issue #589 team name editable in TeamMenu")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % _fails.size())
		get_tree().quit(1)
