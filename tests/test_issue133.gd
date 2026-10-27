extends Node
## Regression check for issue #133: the spear strikes strictly along its
## axis — only a target sitting on the aim ray (small lateral offset) is
## hit; a target inside the old wide 60° cone but off the axis is missed.
##
## Run headless: godot --headless res://tests/test_issue133.tscn
## Exit code 0 = pass.

const DummyScript := "
extends Node2D
var hits := 0
func take_damage(_amount: int) -> void:
	hits += 1
"


func _ready() -> void:
	await get_tree().process_frame
	var failures := 0

	var holder := CharacterBody2D.new()
	add_child(holder)
	var weapon := Node2D.new()
	weapon.set_script(load("res://Weapon.gd"))
	holder.add_child(weapon)
	# Weapon._facing defaults to 1 (aim = +X); make sure it is set.
	weapon.set("_facing", 1.0)

	var dummy := GDScript.new()
	dummy.source_code = DummyScript
	dummy.reload()

	var on_axis := Node2D.new()
	on_axis.set_script(dummy)
	on_axis.position = Vector2(50, 0)
	on_axis.add_to_group("player_team")
	holder.add_child(on_axis)

	var off_axis := Node2D.new()
	off_axis.set_script(dummy)
	off_axis.position = Vector2(40, 35)  # inside old 60° cone, off the axis
	off_axis.add_to_group("enemy_team")
	holder.add_child(off_axis)

	await get_tree().process_frame
	weapon.call("_thrust_spear")
	await get_tree().process_frame

	if on_axis.get("hits") != 1:
		printerr("FAIL: target on the spear axis was not hit")
		failures += 1
	if off_axis.get("hits") != 0:
		printerr("FAIL: off-axis target was hit (spear must attack along its axis)")
		failures += 1

	# Behind the wielder (negative forward projection) must never be hit.
	var behind := Node2D.new()
	behind.set_script(dummy)
	behind.position = Vector2(-30, 0)
	behind.add_to_group("enemy_team")
	holder.add_child(behind)
	await get_tree().process_frame
	weapon.call("_thrust_spear")
	await get_tree().process_frame
	if behind.get("hits") != 0:
		printerr("FAIL: target behind the wielder was hit")
		failures += 1

	if failures == 0:
		print("ISSUE133 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE133 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
