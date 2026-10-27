extends Node
## Regression check for issue #119: the turn must not end until every
## projectile has exploded — a shot starts a short handover delay, and the
## handover additionally waits until no projectile node is alive, so a
## grenade with a 3 s fuse always lands before the next turn starts.
##
## Run headless: godot --headless res://tests/test_issue119.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var level: Node = load("res://Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	# Wait for the first turn to begin (player's if possible).
	for i in 300:
		await get_tree().physics_frame
		if tc.active_team != "":
			break
	for i in 600:
		await get_tree().physics_frame
		if tc.active_team == "player":
			break
	var weapon: Node = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if bool(m.get("controlled")):
			weapon = m.get_node_or_null("Weapon")
			break
	if weapon == null:
		print("ISSUE119 no controlled player weapon, ok=false")
		get_tree().quit(1)
		return
	# Select the grenade (index 2) and fire it — its fuse is 3 s.
	WeaponInventory.set_selected(2)
	for i in 5:
		await get_tree().physics_frame
	weapon.npc_fire()
	await get_tree().physics_frame
	var fired: bool = int(weapon._shots_used[2]) == 1
	# Immediately after the shot the turn must still be in handover.
	var switching: bool = bool(tc._switching)
	var projectile_alive: bool = tc._live_projectiles() > 0
	# The old code handed over after 1.5 s — shorter than the 3 s fuse.
	# Wait 2 s: the turn must STILL not have passed while a grenade flies.
	await get_tree().create_timer(2.0).timeout
	var still_old_turn: bool = tc.active_team == "player" and bool(tc._switching)
	var still_alive: bool = tc._live_projectiles() > 0
	# After the grenade explodes the handover must complete on its own.
	for i in 600:
		await get_tree().physics_frame
		if tc.active_team != "" and tc.active_team != "player" \
				and not tc._switching:
			break
	var handed_over: bool = tc.active_team != "" and tc.active_team != "player"
	var no_leftovers: bool = tc._live_projectiles() == 0
	var ok: bool = fired and switching and projectile_alive and still_old_turn \
			and still_alive and handed_over and no_leftovers
	print("ISSUE119 fired=", fired, " switching=", switching,
		" projectile_alive=", projectile_alive,
		" still_old_turn=", still_old_turn, " still_alive=", still_alive,
		" handed_over=", handed_over, " no_leftovers=", no_leftovers,
		" ok=", ok)
	get_tree().quit(0 if ok else 1)
