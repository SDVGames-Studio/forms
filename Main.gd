extends Control
## Main menu for Forms.
##
## New game opens the levels menu (issue #32); Settings is a placeholder
## until its screen exists; Quit closes the game.

@onready var _new_game_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	# Issue #252: the debug-mode switch (and any future setting) loads
	# before any level can build its figures.
	GameConfig.load_settings()
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
