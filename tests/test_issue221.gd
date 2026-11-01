extends Node
## Regression check for issue #221: smarter computer AI.
##
## Checks the new instincts of the NPC AI:
##  1. CLOSE-RANGE SAFETY: inside the self-harm band only the spear or the
##     flat shotgun are picked — never a grenade/rocket at its own feet,
##     even when the target sits above;
##  2. ROCKET: the flat rocket is finally used on open mid/long lanes;
##     the grenade stays for height differences and very long shots;
##  3. TOOLS: a badly hurt AI defends itself — TELEPORT out of point-blank
##     range, SHIELD when the enemy is merely near (the tool spends the
##     turn's action: tool OR weapon, like the player rule of #207);
##  4. SHIELD: blocks all damage until cleared;
##  5. STALL WATCHDOG: standing still with an idle weapon accumulates the
##     skip timer; real movement or a busy weapon resets it;
##  6. SKIP TURN: a lone NPC with no target hands its turn over at once
##     (game over arrives in seconds, not after the 30 s turn timer).
##
## Run headless: godot --headless res://tests/test_issue221.tscn
## Exit code 0 = pass.

const NpcScript := preload("res://Npc.gd")

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


func _make_foe(x: float) -> CharacterBody2D:
	var foe := CharacterBody2D.new()
	foe.add_to_group("player_team")
	add_child(foe)
	foe.global_position = Vector2(x, 0.0)
	return foe


func _ready() -> void:
	await get_tree().process_frame

	# 1+2) Weapon choice by distance / height.
	var chooser := _make_npc()
	add_child(chooser)
	chooser._pick_weapon(60.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == 3,
			"point-blank must pick the melee spear")
	chooser._pick_weapon(150.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == 0,
			"close range must pick the shotgun, not a grenade/rocket")
	chooser._pick_weapon(150.0, 300.0)
	_check(int(chooser._weapon.selected_weapon) == 0,
			"close range keeps the shotgun even over a height difference")
	chooser._pick_weapon(450.0, 10.0)
	_check(int(chooser._weapon.selected_weapon) == 1,
			"flat mid/long lane must pick the rocket")
	chooser._pick_weapon(450.0, 300.0)
	_check(int(chooser._weapon.selected_weapon) == 2,
			"a height difference must pick the ballistic grenade")

	# 3) Tool play — teleport out of point-blank trouble.
	var runner := _make_npc()
	add_child(runner)
	runner.set("health", 20)
	var near_foe := _make_foe(120.0)  # 120 px from runner at (0, 0)
	runner._begin_my_turn()
	_check(bool(runner.get("_tool_used")) == true,
			"a badly hurt AI must spend its tool when threatened")
	_check(not bool(runner.get("shielded")),
			"a point-blank threat must be answered with the teleport, not the shield")
	_check(absf(runner.global_position.x) > 130.0,
			"the hurt AI must teleport away from the point-blank enemy")

	# Tool play — shield when the enemy is merely near.
	var camper := _make_npc()
	add_child(camper)
	camper.global_position = Vector2(2000.0, 0.0)
	camper.set("health", 20)
	var far_foe := _make_foe(2250.0)  # 250 px from camper: near, not deadly
	camper._begin_my_turn()
	_check(bool(camper.get("_tool_used")) == true,
			"a badly hurt AI must spend its tool when the enemy is near")
	_check(bool(camper.get("shielded")),
			"a near (not point-blank) threat must be answered with the shield")
	_check(absf(camper.global_position.x - 2000.0) < 1.0,
			"the shield path must not move the figure")

	# 4) The shield blocks all damage until cleared.
	var health_before: int = camper.get("health")
	camper.take_damage(50)
	_check(int(camper.get("health")) == health_before,
			"a raised shield must block all damage")
	camper.set_shielded(false)
	camper.take_damage(10)
	_check(int(camper.get("health")) == health_before - 10,
			"after the shield is cleared, damage must apply again")

	# 5) Stall watchdog.
	var idler := _make_npc()
	add_child(idler)
	idler.set("_last_pos", idler.global_position)
	idler._update_stall(1.0)
	idler._update_stall(1.0)
	_check(absf(float(idler.get("_turn_stall")) - 2.0) < 0.01,
			"an idle AI with an idle weapon must accumulate the stall timer")
	idler.global_position += Vector2(50.0, 0.0)
	idler._update_stall(1.0)
	_check(float(idler.get("_turn_stall")) == 0.0,
			"real movement must reset the stall timer")
	idler._weapon.set("_shot_delay_left", 1.0)
	idler._update_stall(1.0)
	_check(float(idler.get("_turn_stall")) == 0.0,
			"a busy weapon (between-shots pause) must reset the stall timer")
	idler._weapon.set("_shot_delay_left", 0.0)
	idler._update_stall(2.0)
	idler._update_stall(2.0)
	_check(float(idler.get("_turn_stall")) == 0.0,
			"crossing the stall threshold must end the attempt (and reset)")

	# 6) Skip turn — the whole flow, with a real level group node.
	for figure in [chooser, runner, camper, idler, near_foe, far_foe]:
		figure.queue_free()
	for i in 5:
		await get_tree().physics_frame
	var level := Node.new()
	level.add_to_group("level")
	add_child(level)
	var lone := _make_npc()
	add_child(lone)
	# The roll finishes (~1.5 s), then the lone NPC team's turn starts and
	# must hand over AT ONCE (no opponents) instead of standing through
	# the whole 30 s turn timer.
	var over := false
	for i in 400:
		await get_tree().physics_frame
		if TurnController.game_over:
			over = true
			break
	_check(over,
			"a lone NPC with no target must skip to game over in seconds")
	remove_child(level)
	level.queue_free()

	if failures == 0:
		print("PASS: issue #221 smarter AI")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
