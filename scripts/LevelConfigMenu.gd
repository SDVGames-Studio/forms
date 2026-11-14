extends Control
## Level configuration menu (issue #137).
##
## Shown after the player picks a level in the levels menu. Lets them set
## team size and enemy count before the level begins; AI behavior lives
## in the team menu since issue #180. Start applies the settings and
## loads the level, Back returns to the levels menu.
##
## Issue #521 (one-device multiplayer): the menu also edits the TEAM SET
## for the level — add/remove teams and choose who plays each one,
## computer or player. Player teams are played by humans in hot-seat on
## this device (the configured teams beyond the first are dealt across
## the level's enemy figures; GameConfig.apply swaps a player team's
## computer figures for human figures). Start persists the set to
## team.cfg together with the controller choices.
##
## Issue #537 rework: the "Your team size" and "Enemy count" rows are
## GONE — since #521 the level follows the team set, so each team's
## size is shown right in the team row as a little grid of member
## squares (one square per member, wearing the team's shape and color)
## next to the team name on the left.

## Palette for teams added here (mirrors TeamMenu's).
const TEAM_PALETTE: Array[Color] = [
	Color(1, 0.84, 0.2), Color(0.75, 0.2, 0.45), Color(0.35, 0.6, 1),
	Color(0.3, 0.8, 0.4), Color(0.9, 0.3, 0.3), Color(0.2, 0.8, 0.85),
	Color(0.95, 0.6, 0.2), Color(0.65, 0.4, 0.95),
]
const SHAPES: Array[String] = ["square", "circle", "triangle", "star", "ellipse"]

## Issue #537: recessed background of one member square (matches the
## theme's darker panel tone so the shape pops on it).
const MEMBER_CELL_BG := Color(0.122, 0.137, 0.169)
const MEMBER_CELL_SIZE := 30.0

@onready var _title: Label = %Title
@onready var _turn_time: SpinBox = %TurnTimeSpinBox
@onready var _night_regime: CheckButton = %NightRegimeCheck
@onready var _spawn_regime: OptionButton = %SpawnRegimeOption
@onready var _teams_list: VBoxContainer = %TeamsList
@onready var _add_team_button: Button = %AddTeamButton
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_turn_time.value_changed.connect(func(value: float) -> void: GameConfig.turn_time = value)
	# Issue #367: the night regime is picked here, before the game.
	_night_regime.toggled.connect(func(on: bool) -> void: GameConfig.night_regime = on)
	# Issue #523: the spawn regime is picked here, before the game.
	for label in SpawnRegime.REGIME_LABELS:
		_spawn_regime.add_item(label)
	_spawn_regime.item_selected.connect(func(index: int) -> void:
		GameConfig.spawn_regime = index)
	# `select` does not emit `item_selected`, so the stored choice is
	# restored without being written back.
	_spawn_regime.select(GameConfig.spawn_regime)
	# Issue #521: the team set for the level — loaded here (once) and
	# edited directly in GameConfig.teams; Start persists it.
	GameConfig.load_teams()
	_add_team_button.pressed.connect(_on_add_team_pressed)
	_rebuild_team_rows()
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_turn_time.set_value_no_signal(GameConfig.turn_time)
	# Setting the property directly does not emit `toggled`, so the
	# stored choice is restored without being written back.
	_night_regime.button_pressed = GameConfig.night_regime
	if GameConfig.level_path.is_empty():
		# Opened directly (e.g. from the editor): fall back to level 1.
		GameConfig.level_path = "res://scenes/levels/Level.tscn"
	_title.text = _title.text + " — " + GameConfig.level_path.get_file().get_basename()
	_start_button.grab_focus()


func _on_start_pressed() -> void:
	# Issue #521: persist the edited team set (with the controller
	# choices) before the level applies it.
	GameConfig.save_teams()
	# Issue #463: the picked level's endless background music starts with
	# the level and survives the scene change (autoload).
	MusicManager.play_for_level(GameConfig.level_path)
	get_tree().change_scene_to_file(GameConfig.level_path)


# -------------------------------------------------- teams (issue #521) --

## One row per configured team (issue #537 layout): the team NAME on
## the left, then the little member GRID — one square per member of the
## team, each square wearing the team's shape and color — then who
## plays it (Computer/Player) and a Remove button. The minimum is two
## teams, the maximum GameConfig.MAX_TEAMS.
func _rebuild_team_rows() -> void:
	for child in _teams_list.get_children():
		_teams_list.remove_child(child)
		child.queue_free()
	for i in GameConfig.teams.size():
		var team: Dictionary = GameConfig.teams[i]
		var color: Color = team["color"] if team.get("color") is Color else Color(1, 1, 1)
		var shape := str(team["shape"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = str(team["label"])
		label.custom_minimum_size = Vector2(96, 0)
		label.add_theme_font_size_override("font_size", 18)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		row.add_child(_build_member_grid(team, shape, color))
		var controller := OptionButton.new()
		controller.add_item("Computer")
		controller.add_item("Player")
		controller.select(1 if GameConfig.team_controller(i) == "player" else 0)
		controller.custom_minimum_size = Vector2(140, 40)
		var team_index := i
		controller.item_selected.connect(func(index: int) -> void:
			var choice := "player" if index == 1 else "computer"
			GameConfig.teams[team_index]["controller"] = choice)
		row.add_child(controller)
		var remove := Button.new()
		remove.text = "Remove"
		remove.custom_minimum_size = Vector2(100, 40)
		remove.disabled = GameConfig.teams.size() <= 2
		remove.pressed.connect(func() -> void: _on_remove_team_pressed(i))
		row.add_child(remove)
		_teams_list.add_child(row)
	_add_team_button.disabled = GameConfig.teams.size() >= GameConfig.MAX_TEAMS


## Issue #537: the team's little grid table — one square per member
## (names drives the count), each square a recessed cell with the team's
## shape drawn in the team's color, so a triangle team shows triangles.
## Fixed three columns (MAX_TEAM_MEMBERS) keep the squares of different
## team sizes aligned into a grid; hovering a square names its member.
func _build_member_grid(team: Dictionary, shape: String, color: Color) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = GameConfig.MAX_TEAM_MEMBERS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var members: Array = team["names"]
	for member_index in members.size():
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(MEMBER_CELL_SIZE, MEMBER_CELL_SIZE)
		cell.tooltip_text = str(members[member_index])
		var bg := ColorRect.new()
		bg.color = MEMBER_CELL_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(bg)
		var visual: Control = load("res://scripts/ShapeVisual.gd").new()
		visual.custom_minimum_size = Vector2(20, 20)
		visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER,
				Control.PRESET_MODE_MINSIZE)
		visual.set_shape(shape)
		visual.set_shape_color(color)
		cell.add_child(visual)
		grid.add_child(cell)
	return grid


func _on_add_team_pressed() -> void:
	if GameConfig.teams.size() >= GameConfig.MAX_TEAMS:
		return
	var count := GameConfig.teams.size() + 1
	var names: Array[String] = []
	for i in range(1, GameConfig.MAX_TEAM_MEMBERS + 1):
		names.append("Member %d" % i)
	GameConfig.teams.append({
		"label": "Team %d" % count,
		"color": TEAM_PALETTE[(count - 1) % TEAM_PALETTE.size()],
		"shape": SHAPES[count % SHAPES.size()],
		"names": names,
		"skill": 5,
		"friendly_fire": 0,
		"controller": "computer",
		"language": GameConfig.DEFAULT_LANGUAGE,
	})
	_rebuild_team_rows()


func _on_remove_team_pressed(index: int) -> void:
	if GameConfig.teams.size() <= 2:
		return
	GameConfig.teams.remove_at(index)
	_rebuild_team_rows()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/LevelsMenu.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the levels menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
