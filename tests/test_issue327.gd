extends Node
## Regression check for issue #327: a weapon/tool with no uses left can
## never be taken IN-HANDS. Reworked with issue #316: the panel
## selection KEEPS a weapon whose budget just hit 0 for the rest of its
## turn (the wielding character keeps it in hands — an activated last
## jackhammer must not morph into the spear mid-drill); only when the
## next player turn begins (unlock_all) does the panel advance to the
## next weapon with uses left. The per-frame hand sync still resolves
## the selection against the team budget for everyone else (spent ->
## spear in the hand), a spent weapon cannot be re-selected, and an
## armed rock leaves the hand when its budget runs dry.
##
## Run headless: godot --headless res://tests/test_issue327.tscn
## Exit code 0 = pass.

const SPEAR := 3

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE327 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var level: Node = load("res://Level3.tscn").instantiate()
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
		print("ISSUE327 no player turn — ok=false")
		get_tree().quit(1)
		return

	var member: Node = tc.active_member
	var weapon: Node = member.get_node("Weapon")

	# 1) While the budget remains, the held weapon follows the panel.
	inv.set_selected(0)
	_check("panel selects the shotgun", inv.selected_weapon == 0)
	_check("held_weapon_for returns it while budget remains",
		inv.held_weapon_for("player") == 0)
	for i in 10:
		await get_tree().physics_frame
	_check("controlled member holds the shotgun",
		weapon.selected_weapon == 0 and weapon._held_style_index() == 0)

	# 2) The last use of the SELECTED weapon: the PANEL KEEPS pointing at
	# it for the rest of the turn (#316 rework — no more instant demote
	# to the spear), while the hand sync still never takes the spent
	# weapon in-hands for an UNLOCKED member (spear fallback).
	while inv.weapon_uses_left("player", 0) > 0:
		inv.spend_weapon("player", 0)
	_check("shotgun budget exhausted", inv.weapon_uses_left("player", 0) == 0)
	_check("panel KEEPS the spent selection for the rest of the turn",
		inv.selected_weapon == 0)
	_check("held_weapon_for falls back to the spear",
		inv.held_weapon_for("player") == SPEAR)
	for i in 10:
		await get_tree().physics_frame
	_check("the unlocked member never holds the spent weapon — spear held",
		weapon.selected_weapon == SPEAR and weapon._held_style_index() == SPEAR)

	# 2b) Issue #316: a member LOCKED to its weapon (it already fired this
	# turn — Weapon._fire locks on the first shot) KEEPS the spent weapon
	# in hands, and the NEXT player turn (unlock_all) advances the panel
	# to the next weapon the team can still pay for — the owner's
	# algorithm: use the last jackhammer, budget drops to zero, turn
	# ends, THEN the character changes to the next non-zero weapon.
	inv.set_selected(5)  # jackhammer (budget intact)
	for i in 10:
		await get_tree().physics_frame
	_check("jackhammer taken in hands", weapon.selected_weapon == 5)
	inv.lock_for(member)  # what Weapon._fire does on the first shot
	while inv.weapon_uses_left("player", 5) > 0:
		inv.spend_weapon("player", 5)  # …and the shot spends the last use
	for i in 10:
		await get_tree().physics_frame
	_check("locked member keeps the spent jackhammer in hands",
		weapon.selected_weapon == 5 and weapon._held_style_index() == 6)
	inv.unlock_all()  # the start of the next player turn
	_check("panel advances off the spent jackhammer to the next payable weapon",
		inv.selected_weapon == 1)  # shotgun is spent, so next is the rocket
	for i in 10:
		await get_tree().physics_frame
	_check("hand follows the advanced selection — rocket held",
		weapon.selected_weapon == 1 and weapon._held_style_index() == 1)

	# 3) A spent weapon cannot be re-taken either (#305 gate, re-asserted).
	inv.set_selected(0)
	_check("re-selecting the spent weapon changes nothing",
		inv.selected_weapon == 1)

	# 4) The rock tool: arming takes it in hand; the budget hitting 0
	# takes it back out of the hand.
	tools.reset_turn()
	_check("rock arms while budget remains",
		tools.use_tool(tools.TOOL_ROCK) and tools.armed_tool == tools.TOOL_ROCK)
	_check("rock is in hands", weapon._rock_armed())
	while inv.tool_uses_left("player", tools.TOOL_ROCK) > 0:
		inv.spend_tool("player", tools.TOOL_ROCK)
	_check("rock budget exhausted",
		inv.tool_uses_left("player", tools.TOOL_ROCK) == 0)
	_check("armed rock leaves the hand when budget hits 0",
		tools.armed_tool == -1 and not weapon._rock_armed())

	# 5) An ENEMY spend never demotes the player's panel selection.
	inv.reset_uses()
	inv.set_selected(2)  # grenade
	while inv.weapon_uses_left("enemy", 2) > 0:
		inv.spend_weapon("enemy", 2)
	_check("enemy spend leaves the player selection alone",
		inv.selected_weapon == 2)
	_check("player grenade still takeable in-hands",
		inv.held_weapon_for("player") == 2)

	# 6) A fresh round makes every weapon takeable again.
	inv.reset_uses()
	inv.set_selected(1)
	_check("after reset any weapon is takeable again",
		inv.held_weapon_for("player") == 1)

	if _fails.is_empty():
		print("ISSUE327 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE327 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
