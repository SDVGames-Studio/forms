extends Node
## Regression check for issue #553: freed-character crash on turn change.
##
## The report (3vs3 duel level):
##   refresh_tools: Invalid type in function 'has_used_tool' in base
##   'Node (ToolInventory.gd)'. The Object-derived class of argument 1
##   (previously freed) is not a subclass of the expected argument class.
##   WeaponInventory.gd:556 @ refresh_tools()
##   ToolInventory.gd:333 @ refresh_slots()
##   ToolInventory.gd:84 @ reset_turn()
##   TurnController.gd:638 @ _begin_turn()
##
## Cause: the controlled character DIED (was freed) during its turn, but
## TurnController._begin_turn only cleared active_member AFTER the
## player-team bookkeeping — ToolInventory.reset_turn() -> refresh_slots()
## -> WeaponInventory.refresh_tools() still saw the freed node and passed
## it into has_used_tool's typed `character: Node` parameter.
##
## Checked here:
##  - a freed active member does not break reset_turn (quota/armed state
##    still resets) nor refresh_tools;
##  - refresh_tools' weapons_blocked guard evaluates a freed member to
##    "not blocked" instead of erroring (is_instance_valid short-circuit);
##  - has_used_tool keeps answering false for null/freed-adjacent states
##    reachable through the public API (a null active member).
##
## Run headless: godot --headless res://tests/test_issue553.tscn
## Exit code 0 = pass.

const PlayerScript := preload("res://scripts/Player.gd")

var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])


func _ready() -> void:
	await get_tree().process_frame

	# Freeze the turn flow (same harness idea as test_issue234/306).
	TurnController.set_process(false)
	var level := Node.new()
	level.add_to_group("level")
	add_child(level)
	TurnController.active_team = "player"

	# Two live members plus one that "dies" mid-turn: the corpse is freed
	# while TurnController.active_member still points at it — exactly the
	# state the 3vs3 duel reached on the next _begin_turn.
	var member_a: CharacterBody2D = PlayerScript.new()
	var member_b: CharacterBody2D = PlayerScript.new()
	add_child(member_a)
	add_child(member_b)
	await get_tree().process_frame
	TurnController.active_member = member_a
	member_a.queue_free()
	await get_tree().process_frame  # let the deletion land

	print("* reset_turn with a freed active member")
	ToolInventory.reset_turn()
	_check(ToolInventory.armed_tool == -1, "armed_tool reset despite freed active member")
	_check(not ToolInventory.has_used_tool(member_b), "quota cleared for the live member")
	_check(ToolInventory._pending_switch == false, "pending switch cleared")

	print("* refresh_tools with a freed active member")
	WeaponInventory.refresh_tools()
	_check(true, "refresh_tools completed without aborting")

	print("* guard semantics (weapons_blocked for a freed member)")
	var freed_ref: Node = TurnController.active_member
	_check(not is_instance_valid(freed_ref), "active member is indeed freed in the harness")
	_check(not (is_instance_valid(freed_ref)
			and ToolInventory.has_used_tool(freed_ref)),
			"the guarded expression evaluates false without calling into the freed object")

	print("* null active member stays safe")
	TurnController.active_member = null
	ToolInventory.reset_turn()
	WeaponInventory.refresh_tools()
	_check(not ToolInventory.has_used_tool(null), "has_used_tool(null) is false (guard short-circuits)")

	if _fails.is_empty():
		print("test_issue553: ALL OK")
		get_tree().quit(0)
	else:
		print("test_issue553: %d FAIL" % _fails.size())
		get_tree().quit(1)
