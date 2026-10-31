extends Node
## Issue #170: TOOLS — inventory items that are not weapons: they do not
## deal damage but perform other tasks. Three tools exist, each usable
## ONCE PER TURN (per character):
##  1 Switch   — hand control to the next team member (rework of N/P)
##  2 Teleport — the next left click in the level moves the member there
##  3 Shield   — the member blocks all damage until its next turn begins
##
## Issue #179: tools and weapons share ONE HUD panel — the slots are
## rendered by the WeaponInventory autoload (weapons in keys 1-4, tools
## in keys 5-7). This autoload keeps only the tool LOGIC and STATE:
## once-per-turn quota, teleport arming, shield application. Reset once
## per player turn by TurnController.

const TOOL_SWITCH := 0
const TOOL_TELEPORT := 1
const TOOL_SHIELD := 2
const TOOLS := ["Switch", "Teleport", "Shield"]

## Tool armed for the next click (only teleport uses this).
var armed_tool := -1

var _used: Dictionary = {}


## TurnController, start of a fresh player turn: full tool quota back.
func reset_turn() -> void:
	_used.clear()
	armed_tool = -1
	refresh_slots()


func _can_use(character: Node, tool: int) -> bool:
	return character != null and not _used.get(character, []).has(tool)


func _mark_used(character: Node, tool: int) -> void:
	if not _used.has(character):
		_used[character] = []
	_used[character].append(tool)


func is_switch_locked_by_move() -> bool:
	return TurnController.is_switch_locked()


## Issue #207: true when this character already spent a tool this turn —
## it may not fire a weapon either (tool OR weapon per character per
## turn, never both).
func has_used_tool(character: Node) -> bool:
	return character != null and not _used.get(character, []).is_empty()


## Use a tool with the currently controlled member. Returns true on success.
func use_tool(tool: int) -> bool:
	if not _is_in_level():
		return false
	if not TurnController.is_player_team(TurnController.active_team) or _switching_or_over():
		refresh_slots()
		return false
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		return false
	# Issue #207: this character already FIRED this turn — its tools are
	# locked for the rest of the turn (tool or weapon, never both).
	if WeaponInventory.is_locked_for(member):
		refresh_slots()
		return false
	if not _can_use(member, tool):
		refresh_slots()
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
	refresh_slots()
	return done


func _switching_or_over() -> bool:
	return TurnController.game_over or TurnController.get("_switching") == true


func _is_in_level() -> bool:
	return get_tree().get_first_node_in_group("level") != null


## Issue #179: let the WeaponInventory panel ask whether tool use is
## currently possible (used to gray out the shared tool slots).
func can_use_now(tool: int) -> bool:
	if not _is_in_level():
		return false
	if not TurnController.is_player_team(TurnController.active_team) or _switching_or_over():
		return false
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		return false
	# Issue #207: a character that fired this turn cannot use tools.
	if WeaponInventory.is_locked_for(member):
		return false
	return _can_use(member, tool)


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
			# Issue #207: no teleporting away after firing — a character that
			# used its weapon this turn can't use a tool too. Disarm instead.
			if WeaponInventory.is_locked_for(member):
				armed_tool = -1
				refresh_slots()
				get_viewport().set_input_as_handled()
				return
			var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
			member.global_position = world
			member.velocity = Vector2.ZERO
			_mark_used(member, TOOL_TELEPORT)
			armed_tool = -1
			refresh_slots()
			get_viewport().set_input_as_handled()


## Issue #179: ask the unified panel to redraw tool slot states.
func refresh_slots() -> void:
	if WeaponInventory != null and WeaponInventory.has_method("refresh_tools"):
		WeaponInventory.refresh_tools()
