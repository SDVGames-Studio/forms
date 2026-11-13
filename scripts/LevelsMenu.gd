extends Control
## Levels menu for Forms (issue #32).
##
## Shown when the player presses "New game" in the main menu. Level
## buttons start the level configuration menu (issue #137); Back
## returns to the main menu.
##
## Issue #464 rework: every level saved in the editor
## (user://levels/*.json) appears here as its own button under CUSTOM
## LEVELS and starts like a stock level — GameConfig.custom_level_name
## picks the file, CustomLevel.tscn builds the playable scene from it.

const LEVELS_DIR := "user://levels"

@onready var _level1_button: Button = %Level1Button
@onready var _level2_button: Button = %Level2Button
@onready var _level3_button: Button = %Level3Button
@onready var _level4_button: Button = %Level4Button
@onready var _level5_button: Button = %Level5Button
@onready var _duel_button: Button = %DuelButton
@onready var _duel3_button: Button = %Duel3v3Button
@onready var _custom_label: Label = %CustomLabel
@onready var _custom_box: VBoxContainer = %CustomLevels
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
	_rebuild_custom_levels()


## Issue #464 rework: one button per editor-saved level, under a
## CUSTOM LEVELS heading (hidden while the player has saved none).
## Saved levels play through CustomLevel.tscn — the level
## configuration menu and the game flow beyond it are unchanged.
func _rebuild_custom_levels() -> void:
	for child in _custom_box.get_children():
		child.queue_free()
	var stems: Array[String] = []
	if DirAccess.dir_exists_absolute(LEVELS_DIR):
		for fname in DirAccess.get_files_at(LEVELS_DIR):
			if fname.ends_with(".json"):
				stems.append(fname.get_basename())
	stems.sort()
	_custom_label.visible = not stems.is_empty()
	_custom_box.visible = not stems.is_empty()
	for stem in stems:
		var button := Button.new()
		button.text = stem.replace("_", " ")
		button.custom_minimum_size = Vector2(340, 56)
		button.pressed.connect(_on_custom_level_pressed.bind(stem))
		_custom_box.add_child(button)


## Start a custom level: remember which JSON to build from, then the
## usual level configuration menu → game flow takes over.
func _on_custom_level_pressed(stem: String) -> void:
	GameConfig.custom_level_name = stem
	GameConfig.level_path = "res://scenes/levels/CustomLevel.tscn"
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_level1_pressed() -> void:
	GameConfig.level_path = "res://scenes/levels/Level.tscn"
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_level2_pressed() -> void:
	GameConfig.level_path = "res://scenes/levels/Level2.tscn"
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_level3_pressed() -> void:
	GameConfig.level_path = "res://scenes/levels/Level3.tscn"
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_level4_pressed() -> void:
	GameConfig.level_path = "res://scenes/levels/Level4.tscn"
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


## Issue #250: the circular arena — an indestructible core with a
## destructible outer ring, three teams by default.
func _on_level5_pressed() -> void:
	GameConfig.level_path = "res://scenes/levels/Level5.tscn"
	get_tree().change_scene_to_file("res://scenes/menus/LevelConfigMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


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
	MusicManager.play_for_level("res://scenes/levels/LevelDuel.tscn")
	get_tree().change_scene_to_file("res://scenes/levels/LevelDuel.tscn")


## Issue #366: the same spectated computer-vs-computer duel, but with
## bigger teams — three AI figures per side on a wider battlefield.
func _on_duel3_pressed() -> void:
	MusicManager.play_for_level("res://scenes/levels/LevelDuelBig.tscn")
	get_tree().change_scene_to_file("res://scenes/levels/LevelDuelBig.tscn")
