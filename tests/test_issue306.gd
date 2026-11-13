extends Node
## Regression check for issue #306: rework switch.
##
## The Switch tool is no longer an instant N/P shortcut — the tool must
## be CHOSEN first (slot/key 5 arms it), only then do the N/P keys
## change the character, and the use is spent when the change is
## COMMITTED by an action: another switch, a move, an aim or a shot.
##
## Asserts:
##  - N without the Switch tool armed changes nothing (the free #215
##    shortcut is gone);
##  - arming via use_tool(TOOL_SWITCH) does not switch and does not
##    spend; arming twice disarms again (toggle);
##  - N while armed changes the character, budget still untouched;
##  - a move/aim action (notify_member_action) pays ONE use, disarms
##    the tool and marks the member that handed control away (#207) —
##    the newly controlled member may still act;
##  - the #104 move/aim lock refuses a further N;
##  - a second switch commits the FIRST change (one use per change),
##    the following move commits the second;
##  - with the team budget exhausted the tool can no longer be armed.
##
## Run headless: godot --headless res://tests/test_issue306.tscn
## Exit code 0 = pass.

const SWITCH := 0

var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])


func _controlled() -> Node:
	for m in get_tree().get_nodes_in_group("player_team"):
		if is_instance_valid(m) and m.get("controlled") == true:
			return m
	return null


func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _ready() -> void:
	await get_tree().process_frame

	var level: Node = load("res://scenes/levels/Level.tscn").instantiate()
	add_child(level)
	var waited := 0.0
	while TurnController.active_team != "player" and waited < 20.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		if TurnController.active_team == "enemy":
			TurnController._end_turn()
			for i in 5:
				await get_tree().physics_frame
			waited = 0.0
	_check(TurnController.active_team == "player", "reached a player turn")

	var n_ev := _key_event(KEY_N)
	var inv: CanvasLayer = WeaponInventory
	var tools: Node = ToolInventory
	var first := _controlled()
	_check(first != null, "a member is controlled at the start")

	# 1) N without the Switch tool chosen — nothing happens.
	tools._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(_controlled() == first, "N without the armed Switch tool does nothing")

	# 2) Arming the tool neither switches nor spends.
	_check(tools.use_tool(SWITCH), "use_tool(TOOL_SWITCH) arms the tool")
	_check(tools.armed_tool == SWITCH, "the Switch tool is armed")
	_check(_controlled() == first, "arming does not change the character")
	_check(inv.tool_uses_left("player", SWITCH) == 5,
		"arming spends no use")
	_check(tools.use_tool(SWITCH), "second use_tool call disarms again")
	_check(tools.armed_tool == -1, "the Switch tool toggles back off")
	tools.use_tool(SWITCH)
	_check(tools.armed_tool == SWITCH, "the Switch tool is armed again")

	# 3) N while armed changes the character — the use is NOT spent yet.
	tools._unhandled_input(n_ev)
	await get_tree().physics_frame
	var second := _controlled()
	_check(second != first and second != null, "N switches while the tool is armed")
	_check(inv.tool_uses_left("player", SWITCH) == 5,
		"the character change alone spends nothing yet")

	# 4) A move/aim action commits the change: one use spent, tool
	# disarmed, the member that handed control away pays (#207).
	TurnController.notify_member_action()
	_check(inv.tool_uses_left("player", SWITCH) == 4,
		"a move after the change spends one Switch use")
	_check(tools.armed_tool == -1, "the commit disarms the Switch tool")
	_check(tools.has_used_tool(first), "the handing member used its tool (#207)")
	_check(not tools.has_used_tool(second),
		"the newly controlled member may still act")

	# 5) The #104 move/aim lock refuses a further switch.
	tools.use_tool(SWITCH)
	tools._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(_controlled() == second,
		"N after a move/aim action is refused (switch lock)")

	# 6) Fresh turn: a switch chain pays one use per committed change.
	TurnController._begin_turn("player")
	_check(inv.tool_uses_left("player", SWITCH) == 4,
			"a fresh turn does not refund the team budget (#305)")
	var keeper := _controlled()
	tools.use_tool(SWITCH)
	tools._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(_controlled() != keeper, "N works on a fresh turn")
	_check(inv.tool_uses_left("player", SWITCH) == 4,
		"the first change of the chain is still unpaid")
	tools._unhandled_input(n_ev)
	await get_tree().physics_frame
	var chained := _controlled()
	_check(chained != keeper and chained != null,
			"a second N switches again")
	_check(inv.tool_uses_left("player", SWITCH) == 3,
		"the second switch commits the first change (one use paid)")
	TurnController.notify_member_action()
	_check(inv.tool_uses_left("player", SWITCH) == 2,
		"the move commits the second change (one use paid)")

	# 7) An exhausted budget blocks arming the tool at all.
	TurnController._begin_turn("player")
	while inv.tool_uses_left("player", SWITCH) > 0:
		inv.spend_tool("player", SWITCH)
	_check(not tools.use_tool(SWITCH),
		"use_tool refuses to arm with no Switch uses left")
	_check(tools.armed_tool == -1, "the tool stays unarmed")
	tools._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(tools.armed_tool == -1 and not tools.has_used_tool(_controlled()),
		"N with an exhausted budget changes nothing")

	level.queue_free()
	if _fails.is_empty():
		print("ISSUE306 OK: switch is a chosen tool with a committed use")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("ISSUE306 FAIL: " + f)
		get_tree().quit(1)
