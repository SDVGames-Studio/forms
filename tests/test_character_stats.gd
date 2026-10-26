extends Node
## Tests for the shared CharacterStats (issue #108, tests for issue #111):
## player and enemy figures must be the SAME class of character — identical
## health, movement and view parameters, sourced from
## scripts/CharacterStats.gd so they can never drift apart.
##
## Run headless: godot --headless res://tests/test_character_stats.tscn
## Exit code 0 = pass.

const Stats := preload("res://scripts/CharacterStats.gd")

func _ready() -> void:
	var ok := true
	ok = _check_constants() and ok
	ok = _same_as_stats("Player.gd", load("res://Player.gd")) and ok
	ok = _same_as_stats("Npc.gd", load("res://Npc.gd")) and ok
	ok = await _check_player() and ok
	ok = await _check_npc() and ok
	print("ISSUE111 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


func _check_constants() -> bool:
	var ok: bool = Stats.MAX_HEALTH == 100 and Stats.SPEED > 0.0 \
		and Stats.JUMP_VELOCITY < 0.0 and Stats.GRAVITY > 0.0 \
		and Stats.BAR_WIDTH > 0.0 and Stats.BAR_HEIGHT > 0.0
	print("ISSUE111 constants: ok=", ok)
	return ok


func _stats_of(scr: Script) -> Dictionary:
	return {
		"MAX_HEALTH": scr.get_script_constant_map().get("MAX_HEALTH"),
		"SPEED": scr.get_script_constant_map().get("SPEED"),
		"JUMP_VELOCITY": scr.get_script_constant_map().get("JUMP_VELOCITY"),
		"GRAVITY": scr.get_script_constant_map().get("GRAVITY"),
		"VIEW_SPEED": scr.get_script_constant_map().get("VIEW_SPEED")
			if scr.get_script_constant_map().has("VIEW_SPEED")
			else scr.get_script_constant_map().get("AIM_SPEED"),
		"VIEW_MAX": scr.get_script_constant_map().get("VIEW_MAX"),
		"BAR_WIDTH": scr.get_script_constant_map().get("BAR_WIDTH"),
		"BAR_HEIGHT": scr.get_script_constant_map().get("BAR_HEIGHT"),
	}


func _same_as_stats(name: String, scr: Script) -> bool:
	var m := _stats_of(scr)
	var ok := true
	for key in m:
		var stats_inst: Object = Stats.new()
		var expected = stats_inst.get(key)
		if m[key] != expected:
			push_error("%s.%s = %s, expected %s" % [name, key, m[key], expected])
			ok = false
	print("ISSUE111 ", name, " matches CharacterStats: ok=", ok)
	return ok


func _check_player() -> bool:
	var player := CharacterBody2D.new()
	player.set_script(load("res://Player.gd"))
	add_child(player)
	await get_tree().process_frame
	var ok: bool = int(player.health) == Stats.MAX_HEALTH
	player.take_damage(30)
	ok = ok and int(player.health) == Stats.MAX_HEALTH - 30
	print("ISSUE111 player health 100 -> ", player.health, ": ok=", ok)
	player.queue_free()
	return ok


func _check_npc() -> bool:
	var npc := CharacterBody2D.new()
	npc.set_script(load("res://Npc.gd"))
	add_child(npc)
	await get_tree().process_frame
	var ok: bool = int(npc.health) == Stats.MAX_HEALTH
	npc.take_damage(Stats.MAX_HEALTH)
	ok = ok and int(npc.health) == 0 and npc.get("_dead") == true
	print("ISSUE111 npc lethal damage -> dead: ok=", ok)
	npc.queue_free()
	return ok
