extends Node
## Regression check for issue #120: smarter computer intelligence.
##
## Checks the two new survival instincts of the NPC AI:
##  1. KITE: a badly hurt NPC backs away from a close target instead of
##     pressing into it (while still shooting from range);
##  2. NO SELF-BLAST: the AI never lobs a grenade that would land inside
##     its own blast radius — at point-blank range it switches to the spear.
##
## Run headless: godot --headless res://tests/test_issue120.tscn
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


func _ready() -> void:
	await get_tree().process_frame

	# 1) Kiting: full health → never retreat; badly hurt + close → retreat.
	var healthy := _make_npc()
	add_child(healthy)
	_check(not healthy._wants_retreat(100.0),
			"full-health NPC must not retreat")
	_check(not healthy._wants_retreat(4000.0),
			"full-health NPC must not retreat at any range")

	var hurt: CharacterBody2D = _make_npc()
	add_child(hurt)
	hurt.set("health", 1)
	_check(hurt._wants_retreat(100.0),
			"badly hurt NPC must retreat from a close target")
	_check(not hurt._wants_retreat(4000.0),
			"badly hurt NPC must still shoot from long range")

	# 2) Grenade self-blast guard.
	var lobber := _make_npc()
	add_child(lobber)
	var target := CharacterBody2D.new()
	add_child(target)
	lobber.set("_target", target)
	target.global_position = lobber.global_position + Vector2(50.0, 0.0)
	_check(lobber._grenade_unsafe(),
			"point-blank grenade must be flagged unsafe")
	target.global_position = lobber.global_position + Vector2(400.0, 0.0)
	_check(not lobber._grenade_unsafe(),
			"long-range grenade must be safe")

	# The _shoot() wrapper must switch to the spear instead of re-throwing
	# an unsafe grenade.
	lobber._weapon = Node2D.new()
	lobber._weapon.set_script(load("res://Weapon.gd"))
	lobber._weapon.set("selected_weapon", 2)
	target.global_position = lobber.global_position + Vector2(50.0, 0.0)
	lobber._shoot()
	_check(int(lobber._weapon.get("selected_weapon")) == 3,
			"unsafe point-blank grenade must be swapped for the spear")

	if failures == 0:
		print("PASS: issue #120 smarter AI instincts")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
