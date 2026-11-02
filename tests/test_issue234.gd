extends Node
## Regression check for issue #234: the rock tool rework.
##
## The rock is no longer thrown instantly on activation — the character
## TAKES IT IN HAND (held visual) and throws it with the grenade's aiming
## mechanics (hold-F charge, view aiming, power-scaled arc). Checked here:
##   - activating the tool arms it: the ACTIVE member's held style becomes
##     the rock, a teammate stays on its weapon; no quota spent yet;
##   - activating again puts the rock back (toggle, still no quota);
##   - the throw itself uses the grenade launch formula scaled by the
##     charge power — and ONLY the throw spends the quota;
##   - picking a weapon or switching members puts an armed rock back;
##   - a leftover armed rock never leaks to an NPC during the enemy turn;
##   - after the throw the member may not fire (tool-or-weapon rule) and
##     cannot arm the rock again this turn.
##
## Run headless: godot --headless res://tests/test_issue234.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://Weapon.gd")

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	# Freeze the turn flow (same harness idea as test_issue207): the state
	# below is what TurnController sets during a real player turn.
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
	weapon_a.selected_weapon = 2  # grenade: same charge mechanic as the rock
	member_a.add_child(weapon_a)
	var weapon_b: Node2D = load("res://Weapon.gd").new()
	weapon_b.selected_weapon = 2
	member_b.add_child(weapon_b)
	TurnController.active_member = member_a

	# --- Arm: rock in hands, quota unspent, teammate unaffected.
	WeaponInventory.unlock_all()
	ToolInventory.reset_turn()
	if not ToolInventory.use_tool(ToolInventory.TOOL_ROCK):
		failures.append("rock tool must arm on a fresh turn")
	if ToolInventory.armed_tool != ToolInventory.TOOL_ROCK:
		failures.append("rock tool did not arm")
	if ToolInventory.has_used_tool(member_a):
		failures.append("arming the rock must not spend the quota")
	if weapon_a._held_style_index() != 4:
		failures.append("the active member must HOLD the rock (style 4)")
	if weapon_b._held_style_index() == 4:
		failures.append("a teammate must not hold the armed rock")
	if WeaponScript.HELD_STYLES[4]["color"] != Color(0.55, 0.5, 0.45, 1):
		failures.append("held rock visual must be the gray boulder")

	# --- Toggle: pressing the rock slot again puts it back.
	if not ToolInventory.use_tool(ToolInventory.TOOL_ROCK):
		failures.append("disarming use_tool call must report success")
	if ToolInventory.armed_tool != -1 or weapon_a._held_style_index() != 2:
		failures.append("toggling the rock off must restore the weapon")
	if ToolInventory.has_used_tool(member_a):
		failures.append("toggling the rock off must not spend the quota")

	# --- Pick a weapon while armed: rock goes back.
	ToolInventory.use_tool(ToolInventory.TOOL_ROCK)
	WeaponInventory.set_selected(0)
	if ToolInventory.armed_tool != -1:
		failures.append("selecting a weapon must disarm the rock")

	# --- The throw: grenade mechanics, power-scaled, quota spent ONCE.
	ToolInventory.use_tool(ToolInventory.TOOL_ROCK)
	var rocks_before := _rock_count()
	weapon_a.throw_rock(0.5)
	await get_tree().physics_frame
	if _rock_count() != rocks_before + 1:
		failures.append("throw_rock must spawn exactly one rock body")
	if not ToolInventory.has_used_tool(member_a):
		failures.append("the throw must spend the tool quota")
	if ToolInventory.armed_tool != -1:
		failures.append("the throw must clear the armed state")
	# Grenade formula at power 0.5: speed factor lerpf(0.4, 1.0, 0.5) = 0.7.
	var factor := lerpf(WeaponScript.MIN_SHOT_POWER, 1.0, 0.5)
	var expected := (Vector2(WeaponScript.GRENADE_SPEED, -320.0) * factor).rotated(0.0)
	var rock := _last_rock()
	if rock == null or rock.kind != 2:  # Kind.ROCK
		failures.append("the spawned body must be a ROCK projectile")
	elif rock.launch_velocity.distance_to(expected) > 0.5:
		failures.append("rock velocity must follow the grenade power formula")

	# --- After the throw: no firing, no re-arm this turn.
	weapon_a._fire()
	if weapon_a._shots_used[2] != 0:
		failures.append("a member that threw the rock must not fire weapons")
	if ToolInventory.use_tool(ToolInventory.TOOL_ROCK) \
			or ToolInventory.can_use_now(ToolInventory.TOOL_ROCK):
		failures.append("the rock must be once per member per turn")

	# --- Leftover armed rock never leaks into the enemy turn.
	ToolInventory.reset_turn()
	TurnController.active_team = "enemy"
	TurnController.active_member = member_b
	ToolInventory.armed_tool = ToolInventory.TOOL_ROCK  # simulate a leftover
	if weapon_b._rock_armed() or weapon_b._held_style_index() == 4:
		failures.append("an NPC must never inherit an armed rock")
	ToolInventory.armed_tool = -1

	# --- Fresh turn: the rock is available again.
	TurnController.active_team = "player"
	TurnController.active_member = member_a
	ToolInventory.reset_turn()
	WeaponInventory.unlock_all()
	if not ToolInventory.use_tool(ToolInventory.TOOL_ROCK):
		failures.append("a fresh turn must restore the rock tool")

	# Leave the singleton state clean for other tests.
	ToolInventory.armed_tool = -1
	TurnController.active_member = null
	TurnController.active_team = ""
	TurnController.set_process(true)
	level.queue_free()
	member_a.queue_free()
	member_b.queue_free()

	for failure in failures:
		print("ISSUE234 FAIL ", failure)
	print("ISSUE234 ok=", failures.is_empty())
	get_tree().quit(0 if failures.is_empty() else 1)


func _rock_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("projectiles"):
		if node.get("kind") != null and node.get("kind") == 2:
			count += 1
	return count


func _last_rock() -> Node:
	var found: Array = []
	for node in get_tree().get_nodes_in_group("projectiles"):
		if node.get("kind") != null and node.get("kind") == 2:
			found.append(node)
	return found.back() if not found.is_empty() else null
