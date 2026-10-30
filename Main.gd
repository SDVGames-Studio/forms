extends Control
## Main menu for Forms.
##
## New game opens the levels menu (issue #32); Settings is a placeholder
## until its screen exists; Quit closes the game.

@onready var _new_game_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
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
