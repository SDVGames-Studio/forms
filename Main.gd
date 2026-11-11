extends Control
## Main menu for Forms (docs/ui/main_menu.md §4).
##
## Asymmetric composition: branding on the left, exactly three primary
## options on the right (NEW GAME / SETTINGS / QUIT), fully static
## geometric background (MenuBackground) and a small footer with the
## game version. NEW GAME opens the existing level selection flow
## (LevelsMenu -> LevelConfigMenu); SETTINGS opens the SettingsMenu.

@onready var _new_game_button: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	# Issue #252: the debug-mode switch (and any future setting) loads
	# before any level can build its figures.
	GameConfig.load_settings()
	# Issue #476: the main menu's endless theme — starts on every entry
	# into the main menu; starting a level swaps in the level's track.
	MusicManager.play_for_level("res://Main.tscn")
	_version_label.text = "v%s" % ProjectSettings.get_setting(
		"application/config/version", "0.0.0")
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelsMenu.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://SettingsMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


## Issue #303: Escape is the cancel button in every menu — on the root
## menu cancel means leaving the game, same as the Quit button.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_quit_pressed()
