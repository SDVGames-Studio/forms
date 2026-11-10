extends Control
## Levels menu for Forms (issue #32).
##
## Shown when the player presses "New game" in the main menu. Level buttons
## start the level configuration menu (issue #137); Back returns to the
## main menu.

@onready var _level1_button: Button = %Level1Button
@onready var _level2_button: Button = %Level2Button
@onready var _level3_button: Button = %Level3Button
@onready var _level4_button: Button = %Level4Button
@onready var _level5_button: Button = %Level5Button
@onready var _duel_button: Button = %DuelButton
@onready var _duel3_button: Button = %Duel3v3Button
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_level1_button.pressed.connect(_on_level1_pressed)
	_level2_button.pressed.connect(_on_level2_pressed)
	_level3_button.pressed.connect(_on_level3_pressed)
	_level4_button.pressed.connect(_on_level4_pressed)
	_level5_button.pressed.connect(_on_level5_pressed)
	_duel_button.pressed.connect(_on_duel_pressed)
	_duel3_button.pressed.connect(_on_duel3_pressed)
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


func _on_level4_pressed() -> void:
	GameConfig.level_path = "res://Level4.tscn"
	get_tree().change_scene_to_file("res://LevelConfigMenu.tscn")


## Issue #250: the circular arena — an indestructible core with a
## destructible outer ring, three teams by default.
func _on_level5_pressed() -> void:
	GameConfig.level_path = "res://Level5.tscn"
	get_tree().change_scene_to_file("res://LevelConfigMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the main menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()


## Issue #121: spectate a computer-vs-computer duel — no player team.
func _on_duel_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelDuel.tscn")


## Issue #366: the same spectated computer-vs-computer duel, but with
## bigger teams — three AI figures per side on a wider battlefield.
func _on_duel3_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelDuelBig.tscn")
