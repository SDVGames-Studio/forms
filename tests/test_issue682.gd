extends Node
## Regression check for issue #682: "Entrenching shovel doesn't dig
## under the character" — the jackhammer must be aimable STRAIGHT DOWN
## so the wielder can entrench itself (dig a shaft under its feet).
##
## The pre-#682 arsenal-wide aim clamp (Stats.VIEW_MAX = 1.2 rad ≈ 69°)
## kept every weapon's aim above the vertical — the jackhammer could
## never point into the floor beneath the character, so it always slid
## diagonally at ≤ 69° instead of digging down.
##
##  1. JACKHAMMER SELECTED: aiming down saturates at -PI/2 (straight
##     down along the gravity frame) and aim_dir() points ALONG
##     gravity — the drill direction that carves under the feet;
##  2. JACKHAMMER SELECTED, UP: aiming up saturates at +PI/2 — the
##     vertical dig works both ways (the drill follows the aim, #316);
##  3. OTHER WEAPONS UNAFFECTED: with the shotgun selected the clamp
##     is still the arsenal-wide ±VIEW_MAX (1.2 rad);
##  4. NO WEAPON NODE: a bare figure (no Weapon child) still clamps at
##     ±VIEW_MAX;
##  5. DRILL STEERING: with a drill RUNNING (is_drilling()) the clamp
##     stays widened even mid-drill — the W/S keys can steer a running
##     drill down to the vertical;
##  6. LIVE DRILL, DOWN: _start_jackhammer at a straight-down aim
##     produces a drill direction that points along gravity, so the
##     carve point lands directly under the wielder.
##
## Run headless: godot --headless res://tests/test_issue682.tscn
## Exit code 0 = pass.

const CharacterScript := preload("res://scripts/Character.gd")
const WeaponScript := preload("res://scripts/Weapon.gd")

## Weapon slot order (WeaponInventory.WEAPONS): 5 = jackhammer.
const SLOT_SHOTGUN := 0
const SLOT_JACKHAMMER := 5

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A minimal figure with a Weapon child, mirroring
## GameConfig._build_figure_body (capsule body + Weapon node).
func _make_figure() -> CharacterBody2D:
	var figure := CharacterBody2D.new()
	figure.set_script(CharacterScript)
	add_child(figure)
	figure.global_position = Vector2.ZERO
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.set_script(WeaponScript)
	figure.add_child(weapon)
	return figure


func _ready() -> void:
	var view_max: float = CharacterScript.VIEW_MAX

	# 1. Jackhammer selected — aiming down must reach the vertical.
	var digger := _make_figure()
	digger.get_node("Weapon").set("selected_weapon", SLOT_JACKHAMMER)
	digger.aim(-10.0)
	_check(absf(digger.view_angle + PI / 2.0) < 0.0001,
			"jackhammer aim must saturate at -PI/2 (got %f)" % digger.view_angle)
	var down: Vector2 = digger.aim_dir(1.0, 1.0)
	_check(down.dot(Vector2.DOWN) > 0.9999,
			"straight-down aim_dir must point along gravity (got %s)" % str(down))
	digger.queue_free()

	# 2. Jackhammer selected — aiming up saturates at +PI/2.
	var up_digger := _make_figure()
	up_digger.get_node("Weapon").set("selected_weapon", SLOT_JACKHAMMER)
	up_digger.aim(10.0)
	_check(absf(up_digger.view_angle - PI / 2.0) < 0.0001,
			"jackhammer aim must saturate at +PI/2 (got %f)" % up_digger.view_angle)
	up_digger.queue_free()

	# 3. Other weapons keep the arsenal-wide clamp.
	var shooter := _make_figure()
	shooter.get_node("Weapon").set("selected_weapon", SLOT_SHOTGUN)
	shooter.aim(-10.0)
	_check(absf(shooter.view_angle + view_max) < 0.0001,
			"shotgun aim must still clamp at -VIEW_MAX (got %f)" % shooter.view_angle)
	shooter.queue_free()

	# 4. A bare figure with no Weapon node keeps the clamp too.
	var bare := CharacterBody2D.new()
	bare.set_script(CharacterScript)
	add_child(bare)
	bare.aim(-10.0)
	_check(absf(bare.view_angle + view_max) < 0.0001,
			"bare figure aim must clamp at -VIEW_MAX (got %f)" % bare.view_angle)
	bare.queue_free()

	# 5. A RUNNING drill keeps the widened clamp (mid-drill steering).
	var driller := _make_figure()
	driller.get_node("Weapon").set("selected_weapon", SLOT_SHOTGUN)
	driller.get_node("Weapon").set("_drill_left", 1.0)
	driller.aim(-10.0)
	_check(absf(driller.view_angle + PI / 2.0) < 0.0001,
			"a running drill must steer down to -PI/2 (got %f)" % driller.view_angle)
	driller.queue_free()

	# 6. A drill STARTED at the vertical points along gravity — the
	# carve point (center + dir * 12) lands straight under the wielder.
	var starter := _make_figure()
	starter.get_node("Weapon").set("selected_weapon", SLOT_JACKHAMMER)
	starter.aim(-10.0)
	starter.get_node("Weapon").call("_start_jackhammer", 0.5)
	var drill_dir: Vector2 = starter.get_node("Weapon").get("_drill_dir")
	_check(drill_dir.dot(Vector2.DOWN) > 0.9999,
			"the started drill must run along gravity (got %s)" % str(drill_dir))
	starter.get_node("Weapon").call("_end_jackhammer")
	starter.queue_free()

	if failures == 0:
		print("PASS: issue #682 jackhammer digs under the character")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
