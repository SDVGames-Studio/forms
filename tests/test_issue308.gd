extends Node
## Regression check for issue #308: the computer must see an enemy team
## character at ANY point of the level.
##
## The old fire gate `distance <= ATTACK_RANGE` (500 px) left far figures
## untouchable — the AI could only walk at them and, when the way was
## blocked, burned its turn standing still. Now the gate is aim +
## cooldown only: _pick_weapon resolves EVERY distance (the ballistic
## grenade is the far band), so a distant enemy is engaged at once.
##
##  1. WEAPON BAND: a 2200 px flat shot picks the ballistic grenade —
##     the far band that reaches across a whole level;
##  2. LEVEL-WIDE SIGHT: with its turn forced active and a foe FAR
##     beyond the old 500 px cap, the NPC actually FIRES (a live
##     projectile appears) instead of standing still.
##
## Run headless: godot --headless res://tests/test_issue308.tscn
## Exit code 0 = pass.

const NpcScript := preload("res://Npc.gd")
const BodyScript := preload("res://ProjectileBody.gd")

## Weapon slot order (Weapon.gd): 0 shotgun, 1 rocket, 2 grenade, 3 spear.
const WEAPON_SLOT_GRENADE := 2

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _make_npc() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.set_script(NpcScript)
	return body


func _ready() -> void:
	await get_tree().process_frame

	# 1) The far band of the weapon chooser is the ballistic grenade.
	var chooser := _make_npc()
	add_child(chooser)
	chooser._pick_weapon(2200.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == WEAPON_SLOT_GRENADE,
			"a level-wide flat shot must pick the ballistic grenade")

	# 2) Level-wide sight: a foe far beyond the old 500 px cap must be
	# engaged during the NPC's turn, not stared at.
	var foe := CharacterBody2D.new()
	foe.add_to_group("player_team")
	add_child(foe)
	foe.global_position = Vector2(2200.0, 0.0)

	var shooter := _make_npc()
	add_child(shooter)
	shooter.global_position = Vector2.ZERO
	shooter.set("_cooldown_left", 0.0)

	TurnController.game_over = false
	TurnController.active_team = TurnController.team_id_of(shooter)
	TurnController.active_member = shooter

	var fired := false
	var grenade := false
	for i in 300:
		await get_tree().physics_frame
		for node in get_tree().get_nodes_in_group("projectiles"):
			if is_instance_valid(node):
				fired = true
				grenade = int(node.kind) == BodyScript.Kind.GRENADE
				break
		if fired:
			break

	TurnController.active_member = null
	TurnController.active_team = ""

	_check(fired,
			"an NPC whose enemy stands far away must OPEN FIRE (level-wide sight)")
	_check(grenade,
			"the far shot must be the ballistic grenade lob")

	if failures == 0:
		print("PASS: issue #308 level-wide AI sight")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
