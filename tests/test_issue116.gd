extends Node
## Regression check for issue #116: the character must be able to change
## weapon after the first shot of the turn.
##
## Before the fix the shot counter (_shots_used) was shared across all
## weapons while the per-turn limit (_shot_limit) is per weapon: after one
## shotgun shot (1 of 2 used) switching to the rocket (limit 1) left
## _shots_used >= limit, so the switched weapon could never fire and the
## switch felt dead.
##
## Fix: the shot quota is tracked per weapon.
##
## Run headless: godot --headless res://tests/test_issue116.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var level: Node = load("res://Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	# Wait for the first turn to begin.
	for i in 300:
		await get_tree().physics_frame
		if tc.active_team != "":
			break
	var ok: bool = tc.active_team == "player"
	if not ok:
		# Let turns roll until it is the player's turn.
		for i in 600:
			await get_tree().physics_frame
			if tc.active_team == "player":
				ok = true
				break
	var weapon: Node = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if bool(m.get("controlled")):
			weapon = m.get_node_or_null("Weapon")
			break
	if weapon == null:
		print("ISSUE116 no controlled player weapon, ok=false")
		get_tree().quit(1)
		return
	# Ensure shotgun is selected and let the sync apply.
	WeaponInventory.set_selected(0)
	for i in 5:
		await get_tree().physics_frame
	var synced := int(weapon.selected_weapon) == 0
	# First shotgun shot (does NOT hand over the turn: quota is 2).
	weapon._fire()
	for i in 5:
		await get_tree().physics_frame
	var used_shotgun_once := int(weapon._shots_used[0]) == 1
	var turn_kept: bool = tc.active_team == "player"
	# Change weapon to the rocket AFTER the first shot.
	WeaponInventory.set_selected(1)
	for i in 5:
		await get_tree().physics_frame
	var switch_synced := int(weapon.selected_weapon) == 1
	var rocket_quota_fresh := int(weapon._shots_used[1]) == 0
	# Wait out the 3-second between-shots delay, then the rocket must fire.
	for i in 240:
		await get_tree().physics_frame
		if float(weapon._shot_delay_left) == 0.0:
			break
	weapon.npc_fire()
	for i in 5:
		await get_tree().physics_frame
	var rocket_fired := int(weapon._shots_used[1]) == 1
	# Rocket is 1-shot: after it, the turn handover must be triggered.
	await get_tree().create_timer(2.5).timeout
	var handover: bool = tc.active_team == "enemy"
	ok = ok and synced and used_shotgun_once and turn_kept \
			and switch_synced and rocket_quota_fresh and rocket_fired \
			and handover
	print("ISSUE116 synced=", synced, " used_shotgun_once=", used_shotgun_once,
		" turn_kept=", turn_kept, " switch_synced=", switch_synced,
		" rocket_quota_fresh=", rocket_quota_fresh, " rocket_fired=", rocket_fired,
		" handover=", handover, " ok=", ok)
	get_tree().quit(0 if ok else 1)
