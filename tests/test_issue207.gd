extends Node
## Regression check for issue #207: a character can use a tool OR a
## weapon in a turn, never both.
##
## Asserts both directions of the exclusivity, per character:
##   - using a tool (Shield) blocks weapon SELECTION and FIRING for that
##     character until the next player turn;
##   - firing a weapon blocks tool use (use_tool refuses, can_use_now is
##     false, an armed teleport disarms instead of teleporting);
##   - the constraint is PER CHARACTER: a teammate that did not fire and
##     did not use a tool still has both;
##   - a fresh player turn (unlock_all + reset_turn) restores both.
##
## Run headless: godot --headless res://tests/test_issue207.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# Freeze the turn flow: the state below is exactly what TurnController
	# sets during a real player turn, and _process must not run its timer
	# over it (there is no real level to play here).
	TurnController.set_process(false)
	var level := Node.new()
	level.add_to_group("level")
	add_child(level)
	TurnController.active_team = "player"
	var member_a: CharacterBody2D = load("res://Player.gd").new()
	var member_b: CharacterBody2D = load("res://Player.gd").new()
	add_child(member_a)
	add_child(member_b)
	await get_tree().process_frame

	var weapon_a: Node2D = load("res://Weapon.gd").new()
	weapon_a.selected_weapon = 3  # spear: no projectile, safe in a bare scene
	member_a.add_child(weapon_a)
	var weapon_b: Node2D = load("res://Weapon.gd").new()
	weapon_b.selected_weapon = 3
	member_b.add_child(weapon_b)

	# Fresh turn.
	WeaponInventory.unlock_all()
	ToolInventory.reset_turn()

	# --- Tool used -> weapon blocked (for THAT character).
	TurnController.active_member = member_a
	if not ToolInventory.use_tool(ToolInventory.TOOL_SHIELD):
		failures.append("shield tool must be usable on a fresh turn")
	if not member_a.shielded:
		failures.append("shield tool did not shield the member")
	WeaponInventory.selected_weapon = 0
	WeaponInventory.set_selected(2)
	if WeaponInventory.selected_weapon != 0:
		failures.append("weapon selection must be refused after a tool use")
	weapon_a._fire()
	if weapon_a._shots_used[3] != 0 or WeaponInventory.is_locked_for(member_a):
		failures.append("a character that used a tool must not be able to fire")

	# --- Per character: the teammate keeps both.
	TurnController.active_member = member_b
	WeaponInventory.selected_weapon = 0
	WeaponInventory.set_selected(2)
	if WeaponInventory.selected_weapon != 2:
		failures.append("a fresh character could not pick its weapon after a teammate used a tool")
	weapon_b._fire()
	if weapon_b._shots_used[3] != 1 or not WeaponInventory.is_locked_for(member_b):
		failures.append("the fresh teammate must still be able to fire")

	# --- Weapon used -> tool blocked (for THAT character).
	if ToolInventory.use_tool(ToolInventory.TOOL_SHIELD):
		failures.append("use_tool must refuse after the character fired")
	if member_b.shielded:
		failures.append("no shield may appear after firing")
	if ToolInventory.can_use_now(ToolInventory.TOOL_SHIELD):
		failures.append("can_use_now must be false after firing")
	# The tool user did NOT fire: its remaining tools stay available
	# (only the already spent Shield is gone — e.g. teleport still arms).
	TurnController.active_member = member_a
	if not ToolInventory.can_use_now(ToolInventory.TOOL_TELEPORT):
		failures.append("a character that used a tool but did not fire must keep tool access")
	TurnController.active_member = member_b

	# --- Fresh player turn restores both directions.
	WeaponInventory.unlock_all()
	ToolInventory.reset_turn()
	TurnController.active_member = member_b
	WeaponInventory.selected_weapon = 0
	WeaponInventory.set_selected(1)
	if WeaponInventory.selected_weapon != 1:
		failures.append("a fresh turn must restore weapon selection")
	if not ToolInventory.can_use_now(ToolInventory.TOOL_SHIELD):
		failures.append("a fresh turn must restore tool use")

	# Leave the singleton state clean for other tests.
	TurnController.active_member = null
	TurnController.active_team = ""
	TurnController.set_process(true)
	level.queue_free()
	member_a.queue_free()
	member_b.queue_free()

	if failures.is_empty():
		print("TEST_ISSUE207 PASS")
	else:
		for failure in failures:
			print("TEST_ISSUE207 FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
