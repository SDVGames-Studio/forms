extends Control
## Main menu for Forms.
##
## Buttons are wired in _ready(): Play and Settings are placeholders
## until their screens exist; Quit closes the game.

@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_play_button.grab_focus()


func _on_play_pressed() -> void:
	print("Play pressed") # TODO: go to the battle setup screen.


func _on_settings_pressed() -> void:
	print("Settings pressed") # TODO: open the settings screen.


func _on_quit_pressed() -> void:
	get_tree().quit()
