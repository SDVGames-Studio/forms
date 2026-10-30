extends Control
## Team customisation menu (issue #169).
##
## Opened from the main menu. Lets the player customise and SAVE their
## team: members' shape, team color, number of members and members' names.
## Settings persist to user://team.cfg (via GameConfig) and are applied to
## the player's figures in every level.

const SHAPES: Array[String] = ["square", "circle", "triangle", "star", "ellipse"]

@onready var _shape: OptionButton = %ShapeOptionButton
@onready var _color: ColorPickerButton = %TeamColorPicker
@onready var _size: SpinBox = %TeamSizeSpinBox
@onready var _names: Array[LineEdit] = [%Name1Edit, %Name2Edit, %Name3Edit]
@onready var _preview_row: HBoxContainer = %PreviewRow
@onready var _save_button: Button = %SaveButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	for shape in SHAPES:
		_shape.add_item(shape.capitalize())
	_shape.item_selected.connect(func(index: int) -> void:
		GameConfig.team_shape = SHAPES[index]
		_refresh_preview())
	_color.color_changed.connect(func(color: Color) -> void:
		GameConfig.team_color = color
		_refresh_preview())
	_size.value_changed.connect(_on_size_changed)
	_save_button.pressed.connect(_on_save_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	# Load the saved customisation before filling in the controls.
	GameConfig.load_team()
	_shape.select(maxi(SHAPES.find(GameConfig.team_shape), 0))
	_color.color = GameConfig.team_color
	_size.set_value_no_signal(clampi(_count_named(), 1, 3))
	for i in _names.size():
		_names[i].text = GameConfig.member_names[i]
		_names[i].text_changed.connect(func(_text: String) -> void: _refresh_preview())
	_update_name_edits()
	_refresh_preview()
	_shape.grab_focus()
	_shape.grab_focus()


## Number of members with a non-empty name (names beyond it stay default).
func _count_named() -> int:
	var count := 0
	for name_edit in _names:
		if not name_edit.text.strip_edges().is_empty():
			count += 1
	return maxi(count, 1)


func _on_size_changed(value: float) -> void:
	_update_name_edits()
	for i in int(value):
		GameConfig.member_names[i] = _names[i].text
	_refresh_preview()


## Issue #169 rework: live preview of the team — one little figure per
## member with the picked shape, team color and name.
func _refresh_preview() -> void:
	for child in _preview_row.get_children():
		child.queue_free()
	for i in int(_size.value):
		var slot := VBoxContainer.new()
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		var figure := Control.new()
		figure.custom_minimum_size = Vector2(72, 72)
		var visual: Control = load("res://scripts/ShapeVisual.gd").new()
		visual.set_anchors_preset(Control.PRESET_FULL_RECT)
		visual.set_shape(SHAPES[_shape.selected])
		visual.set_shape_color(_color.color)
		figure.add_child(visual)
		var label := Label.new()
		label.text = _names[i].text.strip_edges()
		if label.text.is_empty():
			label.text = GameConfig.member_names[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		slot.add_child(figure)
		slot.add_child(label)
		_preview_row.add_child(slot)


func _update_name_edits() -> void:
	for i in _names.size():
		_names[i].editable = i < int(_size.value)
		_names[i].modulate = Color(1, 1, 1, 1.0 if _names[i].editable else 0.4)


func _on_save_pressed() -> void:
	GameConfig.team_size = int(_size.value)
	for i in GameConfig.team_size:
		var text := _names[i].text.strip_edges()
		GameConfig.member_names[i] = text if not text.is_empty() else GameConfig.member_names[i]
	GameConfig.save_team()
	_save_button.text = "Saved!"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")
