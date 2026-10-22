extends Control
## Main menu for Forms.
##
## Buttons are wired in _ready(): Play starts the simple level (issue #1);
## Settings is a placeholder until its screen exists; Quit closes the game.

@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://Level.tscn")


func _on_settings_pressed() -> void:
	print("Settings pressed") # TODO: open the settings screen.


func _on_quit_pressed() -> void:
	get_tree().quit()
