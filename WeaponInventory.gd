extends CanvasLayer
## Weapon inventory HUD (issue #49).
##
## Visible only inside level scenes (issue #78: gated by the "level"
## group, never on the main/levels menu screens). On touchscreen devices
## the panel starts hidden and is toggled with an inventory button in the
## top-right corner (issue #78).
##
## Issue #64 refactor: the panel sits in the BOTTOM-RIGHT corner, the
## weapons are laid out as a 2-column TABLE of icon slots (no title, no
## text names — simple geometrical shape icons), and weapons are chosen
## with digit keys 1-4 or a left mouse click on a slot. Slots ignore
## keyboard focus so arrow keys never touch the inventory.

var selected_weapon := 0

var _slots: Array = []

var _panel: PanelContainer
var _toggle_button: Button
var _mobile_open := false

const WEAPONS := ["Shotgun", "Rocket", "Grenade", "Spear"]

## Issue #64: icon shapes per weapon, mirroring the held-weapon visuals
## in Weapon.gd (shotgun: wide yellow bar, rocket: orange bar, grenade:
## green circle, spear: long thin bar).
const ICONS: Array = [
	{"shape": "rect", "size": Vector2(26, 6), "color": Color(0.95, 0.85, 0.3, 1)},
	{"shape": "rect", "size": Vector2(30, 8), "color": Color(0.9, 0.35, 0.15, 1)},
	{"shape": "circle", "radius": 8.0, "color": Color(0.3, 0.7, 0.3, 1)},
	{"shape": "rect", "size": Vector2(40, 4), "color": Color(0.8, 0.8, 0.9, 1)},
]


func _ready() -> void:
	layer = 10
	visible = false
	_panel = PanelContainer.new()
	# Issue #64: bottom-right corner instead of center-right.
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -150.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = -12.0
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

	# Issue #64: table (grid) instead of a vertical list, no title.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel.add_child(grid)

	for i in WEAPONS.size():
		var slot := Button.new()
		slot.toggle_mode = true
		slot.custom_minimum_size = Vector2(60, 44)
		# Issue #64: arrow keys must never reach the inventory.
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(set_selected.bind(i))
		slot.add_child(_make_icon(i))
		_slots.append(slot)
		grid.add_child(slot)

	_update_highlight()


## Issue #64: a simple geometrical shape drawn instead of a text name.
func _make_icon(index: int) -> Control:
	var icon := ShapeIcon.new()
	icon.icon = ICONS[index]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	return icon


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


## Issue #64: minimal icon canvas — draws one shape centered in the slot.
class ShapeIcon extends Control:
	var icon: Dictionary

	func _draw() -> void:
		var c := size / 2.0
		var col: Color = icon.get("color", Color.WHITE)
		if icon.get("shape", "rect") == "circle":
			draw_circle(c, icon.get("radius", 8.0), col)
		else:
			var s: Vector2 = icon.get("size", Vector2(20, 6))
			draw_rect(Rect2(c - s / 2.0, s), col)
