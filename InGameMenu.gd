extends CanvasLayer
## In-game menu (issue #31).
##
## Esc toggles the menu (issue #254 — previously F10 opened it):
## the first press opens the menu and pauses the game, the next press
## closes it and unpauses.
## Issue #211: the menu only works during gameplay — every level scene's
## root is in the "level" group, so outside levels (main menu, submenus)
## Esc does nothing.
## Buttons: Main Menu (return to the main menu), Settings (opens the
## SAME settings screen as the main menu — issue #304 — instanced over
## the paused game so the running level survives), Cancel (close without
## leaving the level).
## The layer runs while the tree is paused so its buttons stay usable.

var _panel: Control
var _cancel_button: Button
var _settings_button: Button

## Issue #348: the in-game menu follows the main-menu template but with a
## TRANSPARENT background — the paused game stays visible behind the same
## dim color the settings overlay screens use.
const SHADOW_COLOR := Color(0.05, 0.03, 0.1, 0.75)
const MENU_THEME := preload("res://MenuTheme.tres")
const DIM_TEXT := Color(0.467, 0.49, 0.545, 1)
const ACCENT := Color(0.655, 0.545, 0.98, 1)

## Issue #304: the settings screen instanced over the pause panel while
## it is open (null = closed).
var _settings_menu: Control = null


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
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			if _panel.visible:
				_close()
				get_viewport().set_input_as_handled()
			elif _is_level_active() and not get_tree().paused:
				_open()
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
	# Issue #348: same composition as the main menu — dim over the game,
	# margin layout, brand column (title + subtitle + accent rule), nav
	# buttons on the right, footer bottom-left — just transparent.
	_panel = ColorRect.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_panel as ColorRect).color = SHADOW_COLOR
	_panel.theme = MENU_THEME
	add_child(_panel)

	var layout := MarginContainer.new()
	layout.name = "Layout"
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 72)
	layout.add_theme_constant_override("margin_top", 56)
	layout.add_theme_constant_override("margin_right", 72)
	layout.add_theme_constant_override("margin_bottom", 72)
	_panel.add_child(layout)

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", 64)
	layout.add_child(columns)

	var brand := VBoxContainer.new()
	brand.name = "Brand"
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_theme_constant_override("separation", 10)
	columns.add_child(brand)

	var title := Label.new()
	title.name = "Title"
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 56)
	brand.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "ESC RETURNS TO THE GAME"
	subtitle.add_theme_color_override("font_color", DIM_TEXT)
	subtitle.add_theme_font_size_override("font_size", 17)
	brand.add_child(subtitle)

	var rule := ColorRect.new()
	rule.name = "AccentRule"
	rule.custom_minimum_size = Vector2(260, 4)
	rule.color = ACCENT
	brand.add_child(rule)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(spacer)

	var nav := VBoxContainer.new()
	nav.name = "Nav"
	nav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_theme_constant_override("separation", 14)
	columns.add_child(nav)

	nav.add_child(_make_button("MainMenuButton", "Main Menu", _on_main_menu_pressed))
	_settings_button = _make_button("SettingsButton", "Settings", _on_settings_pressed)
	nav.add_child(_settings_button)
	_cancel_button = _make_button("CancelButton", "Cancel", _close)
	nav.add_child(_cancel_button)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 32.0
	footer.offset_top = -52.0
	footer.offset_right = 500.0
	footer.offset_bottom = -24.0
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.add_theme_constant_override("separation", 10)
	_panel.add_child(footer)

	var studio := Label.new()
	studio.name = "Studio"
	studio.text = "SDVGAMES"
	studio.add_theme_color_override("font_color", DIM_TEXT)
	studio.add_theme_font_size_override("font_size", 14)
	footer.add_child(studio)

	var version := Label.new()
	version.name = "VersionLabel"
	version.text = "v0.1.0"
	version.add_theme_color_override("font_color", DIM_TEXT)
	version.add_theme_font_size_override("font_size", 14)
	footer.add_child(version)


func _make_button(button_name: String, label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(340, 64)
	button.text = label
	button.pressed.connect(handler)
	return button


func _on_main_menu_pressed() -> void:
	_close()
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_settings_pressed() -> void:
	## Issue #304: open the shared settings screen (the same one the main
	## menu opens) over the paused game — a scene change would drop the
	## running level. This layer runs while paused, so the overlay and its
	## submenus stay usable.
	if _settings_menu != null:
		return
	_panel.visible = false
	_settings_menu = (load("res://SettingsMenu.tscn") as PackedScene).instantiate()
	_settings_menu.in_game = true
	_settings_menu.back_requested.connect(_on_settings_closed)
	add_child(_settings_menu)


func _on_settings_closed() -> void:
	## Back/Esc from the settings screen returns to the pause panel; the
	## game stays paused until Cancel/Esc resumes it.
	if _settings_menu != null:
		_settings_menu.queue_free()
		_settings_menu = null
	_panel.visible = true
	_settings_button.grab_focus()
