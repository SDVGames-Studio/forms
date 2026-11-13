extends Node
## Regression check for issue #305: per-team use budgets — every team
## starts a round with 5 uses of each weapon and 5 uses of each tool,
## the SPEAR is infinite, each shot/tool use spends one use, a spent
## item can no longer be fired/armed, and the inventory HUD shows the
## remaining count in each slot's bottom-right corner (spear: ∞).
##
## Tools act on the ACTIVE member, weapons fire from any member — the
## tool checks run on the controlled member, the shot checks on another
## member of the same team (tool OR weapon per character per turn, #207).
##
## Run headless: godot --headless res://tests/test_issue305.tscn
## Exit code 0 = pass.

## Issue #359 added the RAILGUN as the seventh weapon — the list and
## the starting budgets below track the live WeaponInventory.WEAPONS
## (railgun starts at ONE use, issue #359; everything else at five,
## spear infinite). Kept in sync by hand for issue #364's run: the
## railgun PR left this local copy at six weapons and check 1 red.
## Issue #526 added the PISTOL as the eighth weapon (standard 5 uses).
const WEAPONS := ["Shotgun", "Rocket", "Grenade", "Spear", "Mine", "Jackhammer", "Railgun", "Pistol"]
const SPEAR := 3
const RAILGUN := 6
const RAILGUN_START := 1

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE305 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var level: Node = load("res://scenes/levels/Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	var inv: Node = get_node("/root/WeaponInventory")
	var tools: Node = get_node("/root/ToolInventory")
	# Wait for the player's turn to begin (an enemy team may move first).
	for i in 3600:
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			break
	if tc.active_team != "player":
		print("ISSUE305 no player turn — ok=false")
		get_tree().quit(1)
		return

	# 1) Fresh budgets: 5 uses of every weapon and tool, spear infinite.
	for w in WEAPONS.size():
		var want := -1 if w == SPEAR else (RAILGUN_START if w == RAILGUN else 5)
		_check("weapon %s starts at %d" % [WEAPONS[w], want],
			inv.weapon_uses_left("player", w) == want)
	for t in tools.TOOLS.size():
		_check("tool %s starts at 5" % tools.TOOLS[t],
			inv.tool_uses_left("player", t) == 5)

	# 2) Tool budget: arming the teleport spends nothing (the CLICK would
	# spend); using the shield spends one use of the team's budget.
	tools.reset_turn()
	_check("teleport arms while budget remains",
		tools.use_tool(tools.TOOL_TELEPORT) and tools.armed_tool == tools.TOOL_TELEPORT)
	_check("teleport arming spends nothing",
		inv.tool_uses_left("player", tools.TOOL_TELEPORT) == 5)
	_check("teleport toggles back off",
		tools.use_tool(tools.TOOL_TELEPORT) and tools.armed_tool == -1)
	_check("shield spends a tool use (5 -> 4)",
		tools.use_tool(tools.TOOL_SHIELD)
			and inv.tool_uses_left("player", tools.TOOL_SHIELD) == 4)

	# 3) Weapon budget: one real shot (from another member of the team —
	# the active member used a tool this turn, #207) spends one use.
	var actor: Node2D = null
	var shooter: Node2D = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if bool(m.get("controlled")):
			actor = m
		elif shooter == null:
			shooter = m
	if actor == null or shooter == null:
		print("ISSUE305 need two player members — ok=false")
		get_tree().quit(1)
		return
	var weapon: Node = shooter.get_node("Weapon")
	weapon.selected_weapon = 0  # shotgun (2 shots/turn — one shot keeps the turn)
	weapon._fire(1.0)
	_check("shotgun use spent (5 -> 4)",
		inv.weapon_uses_left("player", 0) == 4)

	# 4) A spent weapon cannot fire anymore — the gate in Weapon._fire.
	while inv.weapon_uses_left("player", 0) > 0:
		inv.spend_weapon("player", 0)
	_check("shotgun budget exhausted", inv.weapon_uses_left("player", 0) == 0)
	_check("can_spend_weapon(shotgun) is false",
		not inv.can_spend_weapon("player", 0))
	var shots: Array = weapon.get("_shots_used")
	weapon._fire(1.0)
	_check("spent weapon no longer fires (shot count unchanged)",
		weapon.get("_shots_used")[0] == shots[0])

	# 5) The spear is infinite — spend never drains it.
	_check("can_spend_weapon(spear) is always true",
		inv.can_spend_weapon("player", SPEAR))
	for i in 10:
		inv.spend_weapon("player", SPEAR)
	_check("spear stays at -1 after spends",
		inv.weapon_uses_left("player", SPEAR) == -1)

	# 6) A spent tool can no longer be armed.
	while inv.tool_uses_left("player", tools.TOOL_TELEPORT) > 0:
		inv.spend_tool("player", tools.TOOL_TELEPORT)
	_check("spent teleport can no longer be armed",
		not tools.use_tool(tools.TOOL_TELEPORT)
			and tools.armed_tool == -1)

	# 7) The HUD counters: bottom-right label of every slot, spear ∞.
	var counts: Array = inv.get("_slot_counts")
	var tcounts: Array = inv.get("_tool_slot_counts")
	_check("weapon slot counters exist", counts.size() == WEAPONS.size())
	_check("tool slot counters exist", tcounts.size() == tools.TOOLS.size())
	_check("shotgun slot shows 0", str(counts[0].text) == "0")
	_check("spear slot shows infinity", str(counts[SPEAR].text) in ["∞", "oo"])
	_check("shield slot shows 4", str(tcounts[tools.TOOL_SHIELD].text) == "4")

	# 8) The enemy team has its OWN ledger (player shots never drain it).
	_check("enemy shotgun untouched", inv.weapon_uses_left("enemy", 0) == 5)

	# 9) A fresh round resets every budget.
	inv.reset_uses()
	_check("reset_uses restores 5/5", inv.weapon_uses_left("player", 0) == 5
		and inv.tool_uses_left("player", tools.TOOL_SHIELD) == 5)

	if _fails.is_empty():
		print("ISSUE305 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE305 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
