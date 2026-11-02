extends Node
## Regression check for issue #254: the in-game menu hotkey is Esc
## (was F10). Esc must toggle the menu during gameplay — first press
## opens it and pauses the tree, second press closes it and unpauses —
## and F10 must no longer open it.
##
## Run headless: godot --headless res://tests/test_issue254.tscn
## Exit code 0 = pass.


func _ready() -> void:
	add_to_group("level")  # Issue #211: the menu only works in levels.
	var menu: CanvasLayer = load("res://InGameMenu.gd").new()
	add_child(menu)
	# Let the menu build its panel.
	await get_tree().physics_frame

	var failures := []
	var panel: Control = menu.get("_panel")

	# F10 must no longer open the menu.
	_press_key(menu, KEY_F10)
	if panel.visible:
		failures.append("F10 must not open the menu")
	_close_tree_state(menu)

	# Esc opens the menu and pauses the game.
	_press_key(menu, KEY_ESCAPE)
	if not panel.visible:
		failures.append("Esc must open the menu")
	if not get_tree().paused:
		failures.append("opening the menu must pause the tree")

	# Esc again closes it and unpauses.
	_press_key(menu, KEY_ESCAPE)
	if panel.visible:
		failures.append("second Esc must close the menu")
	if get_tree().paused:
		failures.append("closing the menu must unpause the tree")

	print("ISSUE254 ok=", failures.is_empty())
	for failure in failures:
		push_error(failure)
	get_tree().paused = false
	get_tree().quit(0 if failures.is_empty() else 1)


func _press_key(menu: CanvasLayer, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	menu._unhandled_input(event)


func _close_tree_state(menu: CanvasLayer) -> void:
	# Reset after a failed F10 press so later checks start clean.
	menu._close()
