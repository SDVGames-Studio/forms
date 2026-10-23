extends Control
## Main menu for Forms.
##
## Buttons are wired in _ready(): Level 1 / Level 2 start the respective
## level (issue #29); Settings is a placeholder until its screen exists;
## Quit closes the game.

@onready var _level1_button: Button = %PlayButton
@onready var _level2_button: Button = %Level2Button
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_level1_button.pressed.connect(_on_level1_pressed)
	_level2_button.pressed.connect(_on_level2_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_level1_button.grab_focus()


func _on_level1_pressed() -> void:
	get_tree().change_scene_to_file("res://Level.tscn")


func _on_level2_pressed() -> void:
	get_tree().change_scene_to_file("res://Level2.tscn")


func _on_settings_pressed() -> void:
	print("Settings pressed") # TODO: open the settings screen.


func _on_quit_pressed() -> void:
	get_tree().quit()
