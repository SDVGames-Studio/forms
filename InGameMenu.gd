extends CanvasLayer
## In-game menu (issue #31).
##
## F10 opens the menu and pauses the game; Esc closes it and unpauses.
## Issue #211: the menu only works during gameplay — every level scene's
## root is in the "level" group, so outside levels (main menu, submenus)
## F10 does nothing.
## Buttons: Main Menu (return to the main menu), Settings (placeholder
## until its screen exists), Cancel (close without leaving the level).
## The layer runs while the tree is paused so its buttons stay usable.

var _panel: Control
var _cancel_button: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	layer = 10
	_build_ui()
	_panel.visible = false


func open_menu() -> void:
	## Public entry point (issue #78: on-screen MENU button).
	if _is_level_active() and not _panel.visible and not get_tree().paused:
		_open()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_F10 or key.physical_keycode == KEY_F10:
			if _is_level_active() and not _panel.visible and not get_tree().paused:
				_open()
			get_viewport().set_input_as_handled()
		elif _panel.visible and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
			_close()
			get_viewport().set_input_as_handled()


func _is_level_active() -> bool:
	## Issue #211: gameplay scenes put their root in the "level" group.
	return not get_tree().get_nodes_in_group("level").is_empty()


func _open() -> void:
	_panel.visible = true
	get_tree().paused = true
	_cancel_button.grab_focus()


func _close() -> void:
	_panel.visible = false
	get_tree().paused = false


func _build_ui() -> void:
	_panel = ColorRect.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_panel as ColorRect).color = Color(0.05, 0.03, 0.1, 0.75)
	add_child(_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	center.add_child(rows)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 0.84, 0.2))
	rows.add_child(title)

	rows.add_child(_make_button("MainMenuButton", "Main Menu", _on_main_menu_pressed))
	rows.add_child(_make_button("SettingsButton", "Settings", _on_settings_pressed))
	_cancel_button = _make_button("CancelButton", "Cancel", _close)
	rows.add_child(_cancel_button)


func _make_button(button_name: String, label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(300, 60)
	button.text = label
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(handler)
	return button


func _on_main_menu_pressed() -> void:
	_close()
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_settings_pressed() -> void:
	print("Settings pressed") # TODO: open the settings screen.
