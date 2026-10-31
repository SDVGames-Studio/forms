extends Control
## Level configuration menu (issue #137).
##
## Shown after the player picks a level in the levels menu. Lets them set
## team size and enemy count before the level begins; AI behavior lives
## in the team menu since issue #180. Start applies the settings and
## loads the level, Back returns to the levels menu.

@onready var _title: Label = %Title
@onready var _team_size: SpinBox = %TeamSizeSpinBox
@onready var _enemy_count: SpinBox = %EnemyCountSpinBox
@onready var _turn_time: SpinBox = %TurnTimeSpinBox
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_team_size.value_changed.connect(func(value: float) -> void: GameConfig.team_size = int(value))
	_enemy_count.value_changed.connect(func(value: float) -> void: GameConfig.enemy_count = int(value))
	_turn_time.value_changed.connect(func(value: float) -> void: GameConfig.turn_time = value)
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_team_size.set_value_no_signal(GameConfig.team_size)
	_enemy_count.set_value_no_signal(GameConfig.enemy_count)
	_turn_time.set_value_no_signal(GameConfig.turn_time)
	if GameConfig.level_path.is_empty():
		# Opened directly (e.g. from the editor): fall back to level 1.
		GameConfig.level_path = "res://Level.tscn"
	_title.text = _title.text + " — " + GameConfig.level_path.get_file().get_basename()
	_start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(GameConfig.level_path)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelsMenu.tscn")
