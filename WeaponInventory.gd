extends CanvasLayer
## Weapon inventory HUD (issue #49).
##
## Visible only inside level scenes (issue #78: gated by the "level"
## group, never on the main/levels menu screens). On touchscreen devices
## the panel starts hidden and is toggled with an inventory button in the
## top-right corner (issue #78).

var selected_weapon := 0

var _slots: Array = []

var _panel: PanelContainer
var _toggle_button: Button
var _mobile_open := false



const WEAPONS := ["Shotgun", "Rocket", "Grenade", "Spear"]


func _ready() -> void:
	layer = 10
	visible = false
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -150.0
	panel.offset_right = -12.0
	panel.offset_top = -110.0
	panel.offset_bottom = 110.0
	add_child(_panel)

	_toggle_button = Button.new()
	_toggle_button.text = "🎒"
	_toggle_button.custom_minimum_size = Vector2(140, 64)
	_toggle_button.add_theme_font_size_override("font_size", 34)
	_toggle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toggle_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toggle_button.offset_left = -200.0
	_toggle_button.offset_right = -20.0
	_toggle_button.offset_top = 20.0
	_toggle_button.offset_bottom = 84.0
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_toggle_button.visible = false
	add_child(_toggle_button)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Weapons (1-4)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for i in WEAPONS.size():
		var slot := Button.new()
		slot.text = "%d. %s" % [i + 1, WEAPONS[i]]
		slot.toggle_mode = true
		slot.custom_minimum_size = Vector2(130, 34)
		slot.pressed.connect(set_selected.bind(i))
		vbox.add_child(slot)
		_slots.append(slot)

	_update_highlight()


func _process(_delta: float) -> void:
	if _panel == null:
		return
	var in_level := _is_in_level()
	_toggle_button.visible = in_level and DisplayServer.is_touchscreen_available()
	if not in_level:
		visible = false
		return
	if DisplayServer.is_touchscreen_available():
		visible = _mobile_open
		_panel.visible = _mobile_open
	else:
		visible = true
		_panel.visible = true


func _is_in_level() -> bool:
	return get_tree().get_first_node_in_group("level") != null


func _on_toggle_pressed() -> void:
	_mobile_open = not _mobile_open


func _unhandled_input(event: InputEvent) -> void:
	for i in WEAPONS.size():
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			set_selected(i)


func set_selected(index: int) -> void:
	selected_weapon = clampi(index, 0, WEAPONS.size() - 1)
	_update_highlight()


func _update_highlight() -> void:
	for i in _slots.size():
		_slots[i].button_pressed = i == selected_weapon
