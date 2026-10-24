extends CanvasLayer
## Weapon inventory HUD (issue #49).
##
## Visible only inside the levels (issue #49 rework: hidden on the main
## menu). Four slots — shotgun,
## rocket launcher, grenade, melee spear — drawn as rectangles of different
## shape with their number key. Select with keys 1–4 or by clicking a slot.
## The selected index is read by every Weapon.gd instance.

var selected_weapon := 0

var _slots: Array = []

## Issue #49 rework: the inventory HUD belongs in the levels only —
## never on the main/levels menu screens.
const LEVEL_SCENES := ["Level", "Level2", "Level3"]


const WEAPONS := ["Shotgun", "Rocket", "Grenade", "Spear"]


func _ready() -> void:
	layer = 10
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -150.0
	panel.offset_right = -12.0
	panel.offset_top = -110.0
	panel.offset_bottom = 110.0
	add_child(panel)

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
	var scene := get_tree().current_scene
	visible = scene != null and scene.name in LEVEL_SCENES


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
