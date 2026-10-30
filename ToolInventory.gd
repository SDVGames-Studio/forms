extends CanvasLayer
## Issue #170: TOOLS — inventory items that are not weapons: they do not
## deal damage but perform other tasks. Three tools exist, each usable
## ONCE PER TURN (per character):
##  1 Switch   — hand control to the next team member (rework of N/P)
##  2 Teleport — the next left click in the level moves the member there
##  3 Shield   — the member blocks all damage until its next turn begins
##
## Tools live in their own HUD panel in the BOTTOM-LEFT corner (weapons
## stay in the WeaponInventory panel on the right). Keys 5-7 or a click
## on a slot uses a tool. Reset once per player turn by TurnController.

const TOOL_SWITCH := 0
const TOOL_TELEPORT := 1
const TOOL_SHIELD := 2
const TOOLS := ["Switch", "Teleport", "Shield"]

## Icon shapes per tool (plain geometry, no assets — same style as the
## WeaponInventory icons): switch = two arrows (bar pair), teleport =
## cyan ring, shield = blue vertical bar.
const ICONS: Array = [
	{"shape": "rect", "size": Vector2(30, 6), "color": Color(0.9, 0.9, 0.4, 1)},
	{"shape": "circle", "radius": 9.0, "color": Color(0.2, 0.7, 0.95, 1)},
	{"shape": "rect", "size": Vector2(16, 22), "color": Color(0.25, 0.4, 0.95, 1)},
]

## Tool armed for the next click (only teleport uses this).
var armed_tool := -1

var _used: Dictionary = {}
var _slots: Array = []
var _panel: PanelContainer


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 12.0
	_panel.offset_bottom = -12.0
	add_child(_panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("h_separation", 8)
	_panel.add_child(box)
	for i in TOOLS.size():
		var slot := Button.new()
		slot.toggle_mode = true
		slot.custom_minimum_size = Vector2(60, 44)
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(use_tool.bind(i))
		slot.add_child(_make_icon(i))
		_slots.append(slot)
		box.add_child(slot)
	_update_highlight()


func _make_icon(index: int) -> Control:
	var icon := ShapeIcon.new()
	icon.icon = ICONS[index]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	return icon


## TurnController, start of a fresh player turn: full tool quota back.
func reset_turn() -> void:
	_used.clear()
	armed_tool = -1
	_update_highlight()


func _can_use(character: Node, tool: int) -> bool:
	return character != null and not _used.get(character, []).has(tool)


func _mark_used(character: Node, tool: int) -> void:
	if not _used.has(character):
		_used[character] = []
	_used[character].append(tool)


func is_switch_locked_by_move() -> bool:
	return TurnController.is_switch_locked()


## Use a tool with the currently controlled member. Returns true on success.
func use_tool(tool: int) -> bool:
	if _panel == null:
		return false
	if not _is_in_level():
		return false
	if not TurnController.is_player_team(TurnController.active_team) or _switching_or_over():
		_update_highlight()
		return false
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		return false
	if not _can_use(member, tool):
		_update_highlight()
		return false
	var done := false
	match tool:
		TOOL_SWITCH:
			# Same guard as the old N/P: no switching after moving/aiming.
			if not TurnController.is_switch_locked():
				TeamController.switch_next()
				done = true
		TOOL_TELEPORT:
			# Arm the teleport: the next left click picks the destination.
			armed_tool = TOOL_TELEPORT if armed_tool != TOOL_TELEPORT else -1
			done = true
		TOOL_SHIELD:
			if member.has_method("set_shielded"):
				member.set_shielded(true)
				done = true
	if done and tool != TOOL_TELEPORT:
		_mark_used(member, tool)
		armed_tool = -1
	_update_highlight()
	return done


func _switching_or_over() -> bool:
	return TurnController.game_over or TurnController.get("_switching") == true


func _process(_delta: float) -> void:
	# Issue #174: the tools panel is in-game HUD — keep it hidden outside
	# level scenes (same gating as the WeaponInventory panel).
	if _panel != null:
		_panel.visible = _is_in_level()


func _is_in_level() -> bool:
	return get_tree().get_first_node_in_group("level") != null


func _unhandled_input(event: InputEvent) -> void:
	for i in TOOLS.size():
		if event.is_action_pressed("tool_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			use_tool(i)
			return
	# Armed teleport: the next left click inside a level is the destination.
	if armed_tool == TOOL_TELEPORT and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var member: Node = TurnController.active_member
		if member != null and is_instance_valid(member) and member is Node2D:
			var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
			member.global_position = world
			member.velocity = Vector2.ZERO
			_mark_used(member, TOOL_TELEPORT)
			armed_tool = -1
			_update_highlight()
			get_viewport().set_input_as_handled()


func _update_highlight() -> void:
	for i in _slots.size():
		_slots[i].button_pressed = armed_tool == i
		_slots[i].disabled = false
		var member: Node = TurnController.active_member
		if member != null and not _can_use(member, i):
			_slots[i].modulate = Color(1, 1, 1, 0.35)
		else:
			_slots[i].modulate = Color.WHITE


## Issue #170: minimal icon canvas (same style as the weapon icons).
class ShapeIcon extends Control:
	var icon: Dictionary
	var icon_scale := 1.0

	func _draw() -> void:
		var c := size / 2.0
		var col: Color = icon.get("color", Color.WHITE)
		if icon.get("shape", "rect") == "circle":
			draw_arc(c, icon.get("radius", 8.0) * icon_scale, 0.0, TAU, 32, col, 4.0, true)
			draw_arc(c, icon.get("radius", 8.0) * icon_scale - 4.0, 0.0, TAU, 32, col, 2.0, true)
		else:
			var s: Vector2 = icon.get("size", Vector2(20, 6)) * icon_scale
			draw_rect(Rect2(c - s / 2.0, s), col)
