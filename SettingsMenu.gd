extends Control
## Settings menu (issue #175).
##
## Hosts the settings entries; the team customisation ("My team") moved here
## from the main menu. Issue #180: the entry is renamed to "Teams" — the
## team menu configures the player's team AND the computer team's AI
## behavior. Back returns to the main menu.

@onready var _team_button: Button = %TeamButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_team_button.pressed.connect(_on_team_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_team_button.grab_focus()


func _on_team_pressed() -> void:
	get_tree().change_scene_to_file("res://TeamMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
