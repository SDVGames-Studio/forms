extends Control
## Levels menu for Forms (issue #32).
##
## Shown when the player presses "New game" in the main menu. Level buttons
## start the respective level; Back returns to the main menu.

@onready var _level1_button: Button = %Level1Button
@onready var _level2_button: Button = %Level2Button
@onready var _level3_button: Button = %Level3Button
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_level1_button.pressed.connect(_on_level1_pressed)
	_level2_button.pressed.connect(_on_level2_pressed)
	_level3_button.pressed.connect(_on_level3_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_level1_button.grab_focus()


func _on_level1_pressed() -> void:
	get_tree().change_scene_to_file("res://Level.tscn")


func _on_level2_pressed() -> void:
	get_tree().change_scene_to_file("res://Level2.tscn")


func _on_level3_pressed() -> void:
	get_tree().change_scene_to_file("res://Level3.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
