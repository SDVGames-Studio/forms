extends Control
## Team menu, reworked for issue #208: editor for the whole SET of teams.
##
## - The list of teams sits at the top, right below the header; clicking a
##   team edits it, "+ Add team" appends a new team to the set.
## - The editing column is scrollable, so nothing is lost on small screens.
## - The members are shown in a visual window exactly as they look in the
##   game (shape figure + team color + name). The leftmost member is the
##   first in the team; clicking a figure offers to DELETE that member;
##   the + button to the right of the rightmost member adds a new one;
##   clicking a member's name edits it in place.
## - The shape picker is graphical: one little figure per shape.
## - "Save" persists the whole set to user://team.cfg (GameConfig.teams).
##   The first team ("Player Team") stays the player's figures in every
##   level; the "Enemies" team feeds the computer opponents' AI skill and
##   friendly-fire (issue #180 behavior, kept unchanged in-game).
##
## The default set of teams mirrors the teams that are in the levels: the
## player team plus the computer (NPC) team.

const SHAPES: Array[String] = ["square", "circle", "triangle", "star", "ellipse"]

## Palette for new teams — the first two slots match the two teams the
## levels are authored with (player yellow, NPC pink).
const TEAM_PALETTE: Array[Color] = [
	Color(1, 0.84, 0.2), Color(0.75, 0.2, 0.45), Color(0.35, 0.6, 1),
	Color(0.3, 0.8, 0.4), Color(0.9, 0.3, 0.3), Color(0.2, 0.8, 0.85),
	Color(0.95, 0.6, 0.2), Color(0.65, 0.4, 0.95),
]

@onready var _team_list_box: HBoxContainer = %TeamListBox
@onready var _add_team_button: Button = %AddTeamButton
@onready var _editing_label: Label = %EditingLabel
@onready var _shape_picker: HBoxContainer = %ShapePicker
@onready var _color: ColorPickerButton = %TeamColorPicker
@onready var _members_row: HBoxContainer = %MembersRow
@onready var _skill: HSlider = %SkillSlider
@onready var _friendly_fire: HSlider = %FriendlyFireSlider
@onready var _save_button: Button = %SaveButton
@onready var _back_button: Button = %BackButton
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog

## Index into GameConfig.teams of the team being edited.
var _selected := 0
var _shape_buttons: Array[Button] = []
## Member index offered for deletion (dialog is open); -1 = none.
var _pending_member := -1


func _ready() -> void:
	# Load the saved customisation before filling in the controls.
	GameConfig.load_team()
	GameConfig.load_teams()
	_add_team_button.pressed.connect(_on_add_team_pressed)
	_color.color_changed.connect(_on_color_changed)
	_skill.value_changed.connect(
		func(value: float) -> void: _team()["skill"] = int(value))
	_friendly_fire.value_changed.connect(
		func(value: float) -> void: _team()["friendly_fire"] = int(value))
	_save_button.pressed.connect(_on_save_pressed)
	_back_button.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://SettingsMenu.tscn"))
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	_build_shape_picker()
	_refresh_all()


## The team dictionary currently being edited.
func _team() -> Dictionary:
	return GameConfig.teams[_selected]


func _refresh_all() -> void:
	_rebuild_team_list()
	_rebuild_members()
	_sync_controls()


## Fill every control from the selected team (without echoing signals).
func _sync_controls() -> void:
	var team := _team()
	_editing_label.text = "Editing: %s" % team["label"]
	_color.color = team["color"]
	_skill.set_value_no_signal(clampi(int(team["skill"]), 0, 10))
	_friendly_fire.set_value_no_signal(clampi(int(team["friendly_fire"]), 0, 10))
	for i in _shape_buttons.size():
		_shape_buttons[i].set_pressed_no_signal(SHAPES[i] == team["shape"])


# ------------------------------------------------------------------ teams --

func _rebuild_team_list() -> void:
	_clear_children(_team_list_box)
	for i in GameConfig.teams.size():
		var team: Dictionary = GameConfig.teams[i]
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = i == _selected
		button.icon = _swatch(team["color"])
		button.text = str(team["label"])
		button.tooltip_text = "Edit this team"
		button.add_theme_font_size_override("font_size", 22)
		var index := i
		button.pressed.connect(func() -> void: _on_team_selected(index))
		_team_list_box.add_child(button)


func _on_team_selected(index: int) -> void:
	_selected = index
	_refresh_all()


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
	})
	_selected = GameConfig.teams.size() - 1
	_refresh_all()


func _on_color_changed(color: Color) -> void:
	_team()["color"] = color
	_rebuild_team_list()
	_rebuild_members()


# ----------------------------------------------------------------- shapes --

## Graphical shape picker: one button per shape, each showing the little
## figure drawn exactly like in the game (ShapeVisual).
func _build_shape_picker() -> void:
	for shape in SHAPES:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(88, 88)
		button.tooltip_text = shape.capitalize()
		var picked := shape
		button.pressed.connect(func() -> void: _on_shape_picked(picked))
		var visual: Control = load("res://scripts/ShapeVisual.gd").new()
		visual.size = Vector2(56, 56)
		visual.set_anchors_preset(Control.PRESET_CENTER)
		visual.set_shape(shape)
		visual.set_shape_color(Color(0.9, 0.9, 0.95))
		button.add_child(visual)
		_shape_buttons.append(button)
		_shape_picker.add_child(button)


func _on_shape_picked(shape: String) -> void:
	_team()["shape"] = shape
	for i in _shape_buttons.size():
		_shape_buttons[i].set_pressed_no_signal(SHAPES[i] == shape)
	_rebuild_members()


# ---------------------------------------------------------------- members --

## The visual members window: one card per member — the game figure on a
## clickable button (click = offer to delete) plus the editable name —
## and a + button right of the rightmost member.
func _rebuild_members() -> void:
	_clear_children(_members_row)
	var team := _team()
	var names: Array = team["names"]
	for i in names.size():
		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override("separation", 6)
		var figure := Button.new()
		figure.custom_minimum_size = Vector2(100, 100)
		figure.tooltip_text = "Click to remove this member" \
				if names.size() > 1 else "A team keeps at least one member"
		var visual: Control = load("res://scripts/ShapeVisual.gd").new()
		visual.size = Vector2(72, 72)
		visual.set_anchors_preset(Control.PRESET_CENTER)
		visual.set_shape(str(team["shape"]))
		visual.set_shape_color(team["color"])
		figure.add_child(visual)
		var index := i
		figure.pressed.connect(func() -> void: _on_member_clicked(index))
		var name_edit := LineEdit.new()
		name_edit.text = str(names[i])
		name_edit.max_length = 16
		name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_edit.custom_minimum_size = Vector2(150, 40)
		name_edit.add_theme_font_size_override("font_size", 20)
		name_edit.text_changed.connect(
			func(text: String) -> void: _team()["names"][index] = text)
		card.add_child(figure)
		card.add_child(name_edit)
		_members_row.add_child(card)
	if names.size() < GameConfig.MAX_TEAM_MEMBERS:
		var plus := Button.new()
		plus.text = "+"
		plus.tooltip_text = "Add a member"
		plus.custom_minimum_size = Vector2(100, 100)
		plus.add_theme_font_size_override("font_size", 40)
		plus.pressed.connect(_on_add_member)
		_members_row.add_child(plus)


## Clicking a member's figure asks for confirmation, then deletes it.
func _on_member_clicked(index: int) -> void:
	var names: Array = _team()["names"]
	if names.size() <= 1:
		return
	_pending_member = index
	_delete_dialog.dialog_text = "Remove %s from %s?" % [names[index], _team()["label"]]
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_member < 0:
		return
	var names: Array = _team()["names"]
	if _pending_member < names.size():
		names.remove_at(_pending_member)
	_pending_member = -1
	_rebuild_members()


func _on_add_member() -> void:
	var names: Array = _team()["names"]
	if names.size() >= GameConfig.MAX_TEAM_MEMBERS:
		return
	names.append("Member %d" % (names.size() + 1))
	_rebuild_members()


# ------------------------------------------------------------------- save --

func _on_save_pressed() -> void:
	GameConfig.save_teams()
	_save_button.text = "Saved!"
	get_tree().create_timer(2.0).timeout.connect(
		func() -> void: _save_button.text = "Save")


# ---------------------------------------------------------------- helpers --

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Small square icon in the team color for the team-list buttons.
func _swatch(color: Color) -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
