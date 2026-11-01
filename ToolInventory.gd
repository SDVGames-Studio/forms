extends Node
## Issue #170: TOOLS — inventory items that are not weapons: they do not
## deal damage but perform other tasks. Three tools exist, each usable
## ONCE PER TURN (per character):
##  1 Switch   — hand control to the next team member (rework of N/P;
##     issue #215: the N/P keys trigger the Switch tool directly —
##     N next, P previous — with the same guards and quota)
##  2 Teleport — the next left click in the level moves the member there
##  3 Shield   — the member blocks all damage until its next turn begins
##  4 Rock     — issue #227: lob a rock like a grenade; instead of
##     exploding it crumbles into destructible ground around where it
##     rests, clearing every figure and never covering indestructible
##     ground
##
## Issue #179: tools and weapons share ONE HUD panel — the slots are
## rendered by the WeaponInventory autoload (weapons in keys 1-4, tools
## in keys 5-7). This autoload keeps only the tool LOGIC and STATE:
## once-per-turn quota, teleport arming, shield application. Reset once
## per player turn by TurnController.

const TOOL_SWITCH := 0
const TOOL_TELEPORT := 1
const TOOL_SHIELD := 2
const TOOL_ROCK := 3
const TOOLS := ["Switch", "Teleport", "Shield", "Rock"]

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
## Issue #215: direction only affects TOOL_SWITCH — 1 hands control to
## the next member (N), -1 to the previous one (P).
func use_tool(tool: int, direction := 1) -> bool:
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
				if direction < 0:
					TeamController.switch_prev()
				else:
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
		TOOL_ROCK:
			# Issue #227: throw the rock through the member's own Weapon —
			# it owns the aim and the launch arc. The rock body itself
			# handles the ground creation on its fuse.
			done = _throw_rock(member)
	if done and tool != TOOL_TELEPORT:
		_mark_used(member, tool)
		armed_tool = -1
	refresh_slots()
	return done


## Issue #227: hand the rock throw to the member's Weapon node (same aim
## and launch arc as a grenade; see Weapon.throw_rock).
func _throw_rock(member: Node) -> bool:
	var weapon: Node = member.get_node_or_null("Weapon")
	if weapon == null or not weapon.has_method("throw_rock"):
		return false
	weapon.throw_rock()
	return true


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
	# Issue #215: the N/P keys are Switch-tool shortcuts — same guards,
	# same once-per-turn quota as the slot/keys 5-7 use of the tool.
	if event.is_action_pressed("switch_next"):
		get_viewport().set_input_as_handled()
		use_tool(TOOL_SWITCH, 1)
		return
	if event.is_action_pressed("switch_prev"):
		get_viewport().set_input_as_handled()
		use_tool(TOOL_SWITCH, -1)
		return
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
