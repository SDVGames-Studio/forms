extends Node
## Regression check for issue #257: the spear hitbox follows the spearhead
## along its ENTIRE trajectory during the attack (lunge out and pull back)
## instead of a single instant press-time check.
##
## Checks:
##  1. NEAR: an on-axis target in melee range is hit, exactly ONCE per
##     thrust (the 0.62 s animation must not multi-hit);
##  2. FAR: an on-axis target at 95 px — beyond the old 70 px instant
##     check — IS damaged when the spearhead reaches it;
##  3. OFF-AXIS (#133 kept): a target 35 px to the side is never hit;
##  4. BEHIND: a target behind the wielder is never hit;
##  5. WALK-IN: a target that only enters the path MID-ATTACK (after the
##     press-time moment) is caught by the return sweep;
##  6. SECOND THRUST: a fresh thrust can hit the same target again.
##
## Run headless: godot --headless res://tests/test_issue257.tscn
## Exit code 0 = pass.

const DummyScript := "
extends Node2D
var hits := 0
func take_damage(_amount: int) -> void:
	hits += 1
"


func _make_dummy(parent: Node, pos: Vector2, group: String) -> Node2D:
	var dummy := GDScript.new()
	dummy.source_code = DummyScript
	dummy.reload()
	var node := Node2D.new()
	node.set_script(dummy)
	node.position = pos
	node.add_to_group(group)
	parent.add_child(node)
	return node


func _ready() -> void:
	await get_tree().process_frame
	var failures := 0

	var holder := CharacterBody2D.new()
	# The thrust animation (and the sweep) only ticks when the wielder
	# provides aim_dir (issue #67) — same as real characters.
	var aim_script := GDScript.new()
	aim_script.source_code = "extends CharacterBody2D\nvar view_angle := 0.0\nfunc aim_dir(f: float, d: float) -> Vector2:\n\treturn Vector2(cos(view_angle) * f, -sin(view_angle) * d)\n"
	aim_script.reload()
	holder.set_script(aim_script)
	add_child(holder)
	var weapon := Node2D.new()
	weapon.set_script(load("res://scripts/Weapon.gd"))
	holder.add_child(weapon)
	# Weapon._facing defaults to 1 (aim = +X); make sure it is set.
	weapon.set("_facing", 1.0)

	# 1 + 2: near enemy (50 px) and far teammate (95 px) on the aim axis.
	var near := _make_dummy(holder, Vector2(50, 0), "enemy_team")
	var far := _make_dummy(holder, Vector2(95, 0), "player_team")
	# 3: off-axis (issue #133 cone rule must keep holding).
	var off_axis := _make_dummy(holder, Vector2(60, 35), "enemy_team")
	# 4: behind the wielder.
	var behind := _make_dummy(holder, Vector2(-40, 0), "enemy_team")

	await get_tree().process_frame
	weapon.call("_thrust_spear")
	# Let the whole 0.62 s thrust animate out (and come back).
	for i in 50:
		await get_tree().process_frame

	if near.get("hits") != 1:
		printerr("FAIL: near on-axis target hits=%s, want exactly 1 per thrust" % near.get("hits"))
		failures += 1
	if far.get("hits") != 1:
		printerr("FAIL: far on-axis target (95 px, beyond old 70 px instant check) hits=%s, want 1 — spearhead must damage along its whole path" % far.get("hits"))
		failures += 1
	if off_axis.get("hits") != 0:
		printerr("FAIL: off-axis target hit (spear must attack along its axis, #133)")
		failures += 1
	if behind.get("hits") != 0:
		printerr("FAIL: target behind the wielder was hit")
		failures += 1

	# 5: walk-in — appears on the path only AFTER the thrust started, so a
	# press-time check could never see it; the return sweep must catch it.
	weapon.call("_thrust_spear")
	for i in 12:  # ~0.2 s: lunge done, spear pulling back, tip still ~100 px
		await get_tree().process_frame
	var walk_in := _make_dummy(holder, Vector2(60, 0), "enemy_team")
	for i in 30:
		await get_tree().process_frame
	if walk_in.get("hits") != 1:
		printerr("FAIL: target stepping into the path mid-attack hits=%s, want 1 (return sweep)" % walk_in.get("hits"))
		failures += 1
	if near.get("hits") != 2:
		printerr("FAIL: near target hits=%s after two thrusts, want exactly 2 (once per thrust, no multi-hit)" % near.get("hits"))
		failures += 1

	# 6: a NEW thrust is a fresh attack — the near target can be hit again.
	weapon.call("_thrust_spear")
	for i in 50:
		await get_tree().process_frame
	if near.get("hits") != 3:
		printerr("FAIL: third thrust hits=%s on near target, want exactly 3 (once per thrust)" % near.get("hits"))
		failures += 1

	if failures == 0:
		print("ISSUE257 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE257 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
