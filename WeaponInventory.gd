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

## Issue #129: on touchscreen devices the inventory becomes the CENTERED
## version: the panel is anchored to the center of the screen and the
## slots/icons grow (~2x), so the grid is comfortably finger-sized.

## Issue #179: tools joined the weapons in THIS panel — one unified
## inventory grid: weapons on keys 1-4, tools on keys 5-7. The tool
## LOGIC stays in the ToolInventory autoload; this script only renders
## the shared slots.

var selected_weapon := 0

## Issue #131 (reworked in #143): after the first shot of a turn the
## weapon selection is frozen — but the one-weapon-per-turn constraint is
## a CHARACTER's constraint, not the player's. The lock is tracked per
## character node: a member that already fired keeps its weapon locked
## until the next player turn, while another controlled member may pick
## any weapon freely. TurnController unlocks everyone at the start of a
## fresh player turn.
var _locked_characters: Dictionary = {}


## Issue #143: mark a character as locked to its weapon for the turn.
func lock_for(character: Node) -> void:
	if character != null:
		_locked_characters[character] = true


## Issue #143: true while this character's weapon choice is frozen.
func is_locked_for(character: Node) -> bool:
	return character != null and _locked_characters.has(character)


## Issue #143: start of a fresh player turn — every character unlocked.
func unlock_all() -> void:
	_locked_characters.clear()

var _slots: Array = []
var _tool_slots: Array = []

var _panel: PanelContainer
var _toggle_button: Button
var _mobile_open := false
var _mobile_layout_applied := false

const WEAPONS := ["Shotgun", "Rocket", "Grenade", "Spear"]

## Issue #179: per-tool icon shapes (mirrors the old ToolInventory
## panel): switch = yellow bar pair, teleport = cyan ring, shield =
## blue vertical bar.
const TOOL_ICONS: Array = [
	{"shape": "rect", "size": Vector2(30, 6), "color": Color(0.9, 0.9, 0.4, 1)},
	{"shape": "ring", "radius": 9.0, "color": Color(0.2, 0.7, 0.95, 1)},
	{"shape": "rect", "size": Vector2(16, 22), "color": Color(0.25, 0.4, 0.95, 1)},
]

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

	if DisplayServer.is_touchscreen_available():
		_apply_mobile_layout()

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
		slot.add_child(_make_icon(ICONS[i]))
		_slots.append(slot)
		grid.add_child(slot)

## Issue #179: tool slots in the SAME grid, right after the weapons.
	for i in TOOL_ICONS.size():
		var slot := Button.new()
		slot.toggle_mode = true
		slot.custom_minimum_size = Vector2(60, 44)
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(_on_tool_slot_pressed.bind(i))
		slot.add_child(_make_icon(TOOL_ICONS[i]))
		_tool_slots.append(slot)
		grid.add_child(slot)

	_update_highlight()
	refresh_tools()


## Issue #64: a simple geometrical shape drawn instead of a text name.
## Issue #129: bigger, centered layout for the mobile version.
func _apply_mobile_layout() -> void:
	if _mobile_layout_applied:
		return
	_mobile_layout_applied = true
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	var grid: GridContainer = _panel.get_child(0)
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	for i in _slots.size():
		_slots[i].custom_minimum_size = Vector2(120, 88)
		var icon: ShapeIcon = _slots[i].get_child(0)
		icon.icon_scale = 2.0
		icon.queue_redraw()
	for i in _tool_slots.size():
		_tool_slots[i].custom_minimum_size = Vector2(120, 88)
		var ticon: ShapeIcon = _tool_slots[i].get_child(0)
		ticon.icon_scale = 2.0
		ticon.queue_redraw()


## Issue #179: tool slot click routes through the ToolInventory logic.
func _on_tool_slot_pressed(tool: int) -> void:
	var tools: Node = get_node_or_null("/root/ToolInventory")
	if tools != null:
		tools.use_tool(tool)
	refresh_tools()


func _make_icon(icon_def: Dictionary) -> Control:
	var icon := ShapeIcon.new()
	icon.icon = icon_def
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	return icon


func _process(_delta: float) -> void:
	if _panel == null:
		return
	var in_level := _is_in_level()
	# Issue #125: the layer must stay visible on mobile, otherwise the
	# toggle button itself disappears — only the PANEL is toggled.
	_toggle_button.visible = in_level and DisplayServer.is_touchscreen_available()
	if not in_level:
		visible = false
		_panel.visible = false
		return
	if DisplayServer.is_touchscreen_available():
		visible = true
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
	# Issue #131, reworked in #143: no weapon changes after the first shot
	# of the turn — but only for the character that actually fired. The
	# check uses the currently controlled member, so switching characters
	# restores free selection for the member that has not fired yet.
	if is_locked_for(TurnController.active_member):
		_update_highlight()
		return
	selected_weapon = clampi(index, 0, WEAPONS.size() - 1)
	_update_highlight()
	refresh_tools()


func _update_highlight() -> void:
	for i in _slots.size():
		_slots[i].button_pressed = i == selected_weapon


## Issue #179: keep the shared tool slots in sync (armed highlight and
## once-per-turn graying). Called by ToolInventory on every state change.
func refresh_tools() -> void:
	if _panel == null or _tool_slots.is_empty():
		return
	# Autoload startup order: the ToolInventory singleton may not exist
	# yet while this panel builds its slots — skip until it does.
	var tools: Node = get_node_or_null("/root/ToolInventory")
	if tools == null:
		return
	for i in _tool_slots.size():
		var slot: Button = _tool_slots[i]
		slot.button_pressed = tools.armed_tool == i
		if tools.can_use_now(i):
			slot.modulate = Color.WHITE
		else:
			slot.modulate = Color(1, 1, 1, 0.35)


## Issue #64: minimal icon canvas — draws one shape centered in the slot.
class ShapeIcon extends Control:
	var icon: Dictionary
	var icon_scale := 1.0

	func _draw() -> void:
		var c := size / 2.0
		var col: Color = icon.get("color", Color.WHITE)
		var shape: String = icon.get("shape", "rect")
		if shape == "circle":
			draw_circle(c, icon.get("radius", 8.0) * icon_scale, col)
		elif shape == "ring":
			# Issue #179: outlined circle (teleport tool icon).
			draw_arc(c, icon.get("radius", 8.0) * icon_scale, 0.0, TAU, 32, col, 4.0, true)
		else:
			var s: Vector2 = icon.get("size", Vector2(20, 6)) * icon_scale
			draw_rect(Rect2(c - s / 2.0, s), col)
