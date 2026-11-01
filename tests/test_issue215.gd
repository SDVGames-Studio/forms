extends Node
## Regression check for issue #215: the p/n keys don't work.
##
## The #170 tools rework removed direct N/P switching but left the
## switch_next/switch_prev input actions orphaned — pressing N or P did
## nothing. #215 wires them back as Switch-tool shortcuts.
##
## Asserts:
##  - TeamController.switch_next/switch_prev walk the team in both
##    directions with wrap-around (fabricated 3-member team);
##  - in the real Level scene an N key press hands control to the next
##    member and TurnController.active_member follows it (#183);
##  - a P key press hands control back to the previous member;
##  - the #170 economy still applies to the keys: a second use by the
##    same character this turn is refused, and after a move/aim action
##    (switch lock, #104) the keys stop switching too.
##
## Run headless: godot --headless res://tests/test_issue215.tscn
## Exit code 0 = pass.

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
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

	# --- Part A: TeamController direction + wrap (no level needed).
	var trio: Array = []
	for i in 3:
		var p: CharacterBody2D = load("res://Player.gd").new()
		p.name = "Trio%d" % i
		if i == 0:
			p.controlled = true
		add_child(p)
		trio.append(p)
	await get_tree().process_frame

	TeamController.switch_next()
	_check(_controlled() == trio[1], "switch_next goes to the next member")
	TeamController.switch_next()
	_check(_controlled() == trio[2], "switch_next reaches the last member")
	TeamController.switch_next()
	_check(_controlled() == trio[0], "switch_next wraps around")
	TeamController.switch_prev()
	_check(_controlled() == trio[2], "switch_prev wraps backwards")

	for p in trio:
		p.queue_free()
	await get_tree().process_frame

	# --- Part B: the N/P keys in the real Level scene.
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame
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

	# The input actions must resolve (input map is loaded from the project).
	var n_ev := _key_event(KEY_N)
	var p_ev := _key_event(KEY_P)
	_check(n_ev.is_action_pressed("switch_next"), "N resolves to switch_next")
	_check(p_ev.is_action_pressed("switch_prev"), "P resolves to switch_prev")

	var first := _controlled()
	_check(first != null, "a member is controlled before switching")

	# N: control hands over to another member, active_member follows (#183).
	ToolInventory._unhandled_input(n_ev)
	await get_tree().physics_frame
	var second := _controlled()
	_check(second != first and second != null and is_instance_valid(second),
			"N hands control to the next member")
	_check(TurnController.active_member == second,
			"TurnController.active_member follows the N switch")

	# P: control hands back to the previous member.
	ToolInventory._unhandled_input(p_ev)
	await get_tree().physics_frame
	_check(_controlled() == first, "P hands control back to the previous member")

	# The first member already spent its Switch tool this turn — the N key
	# (same quota as the slot, #170) must now be refused.
	ToolInventory._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(_controlled() == first,
			"second Switch use by the same member this turn is refused")

	# Fresh turn quota: N works again, then the #104 move/aim lock stops it.
	ToolInventory.reset_turn()
	ToolInventory._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(_controlled() != first, "N works again on a fresh turn quota")
	TurnController.notify_member_action()
	ToolInventory._unhandled_input(n_ev)
	await get_tree().physics_frame
	_check(_controlled() != first,
			"N after a move/aim action is refused (switch lock)")

	if _failures.is_empty():
		print("ISSUE215 OK: p/n keys switch team members again")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("ISSUE215 FAIL: " + f)
		get_tree().quit(1)
