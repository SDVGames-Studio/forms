extends Control
## Levels menu for Forms (issue #32).
##
## Shown when the player presses "New game" in the main menu. Level buttons
## start the level configuration menu (issue #137); Back returns to the
## main menu.

@onready var _level1_button: Button = %Level1Button
@onready var _level2_button: Button = %Level2Button
@onready var _level3_button: Button = %Level3Button
@onready var _duel_button: Button = %DuelButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_level1_button.pressed.connect(_on_level1_pressed)
	_level2_button.pressed.connect(_on_level2_pressed)
	_level3_button.pressed.connect(_on_level3_pressed)
	_duel_button.pressed.connect(_on_duel_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_level1_button.grab_focus()


func _on_level1_pressed() -> void:
	GameConfig.level_path = "res://Level.tscn"
	get_tree().change_scene_to_file("res://LevelConfigMenu.tscn")


func _on_level2_pressed() -> void:
	GameConfig.level_path = "res://Level2.tscn"
	get_tree().change_scene_to_file("res://LevelConfigMenu.tscn")


func _on_level3_pressed() -> void:
	GameConfig.level_path = "res://Level3.tscn"
	get_tree().change_scene_to_file("res://LevelConfigMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


## Issue #121: spectate a computer-vs-computer duel — no player team.
func _on_duel_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelDuel.tscn")
