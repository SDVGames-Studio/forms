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
##  7. SHOVEL SELECTED (rework — the entrenching shovel is a DISTINCT
##     tool with the same need): aiming down/up saturates at ∓PI/2
##     and aim_dir() points along gravity;
##  8. SHOVEL DIG UNDER THE FEET: with the shovel aimed straight down,
##     a swing carves the bore straight UNDER the wielder — the probe
##     below the feet is open ground, the probe past the bore survives.
##
## Run headless: godot --headless res://tests/test_issue682.tscn
## Exit code 0 = pass.

const CharacterScript := preload("res://scripts/Character.gd")
const WeaponScript := preload("res://scripts/Weapon.gd")

## Weapon slot order (WeaponInventory.WEAPONS): 5 = jackhammer,
## 10 = entrenching shovel (#656).
const SLOT_SHOTGUN := 0
const SLOT_JACKHAMMER := 5
const SLOT_SHOVEL := 10

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


## A slab of destructible ground (the test_issue656 stub pattern).
func _make_chunk(at: Vector2, size: Vector2) -> Node:
	var chunk: Node2D = load("res://scripts/DestructibleGround.gd").new()
	chunk.rect_size = size
	chunk.position = at
	add_child(chunk)
	return chunk


## True when some surviving destructible piece still covers the point
## (rectangle pieces only — the dig spawns no polygon/ring pieces).
func _covered(point: Vector2) -> bool:
	for ground in get_tree().get_nodes_in_group("destructible_ground"):
		var piece := ground as Node2D
		if piece == null or not is_instance_valid(piece):
			continue
		if not (piece.get("ring_outer") > 0.0) \
				and piece.get("polygon") != null \
				and piece.get("polygon").size() < 3:
			var rect := Rect2(piece.position - piece.rect_size / 2.0,
					piece.rect_size)
			if rect.has_point(point):
				return true
	return false


func _settle() -> void:
	for i in 4:
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

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

	# 7. Issue #682 rework: the entrenching shovel is a DISTINCT tool —
	# selected, it must get the SAME widened clamp so its bore opens
	# under the wielder, not diagonally ahead.
	var shoveler := _make_figure()
	shoveler.get_node("Weapon").set("selected_weapon", SLOT_SHOVEL)
	shoveler.aim(-10.0)
	_check(absf(shoveler.view_angle + PI / 2.0) < 0.0001,
			"shovel aim must saturate at -PI/2 (got %f)" % shoveler.view_angle)
	var shovel_down: Vector2 = shoveler.aim_dir(1.0, 1.0)
	_check(shovel_down.dot(Vector2.DOWN) > 0.9999,
			"straight-down shovel aim_dir must point along gravity (got %s)"
				% str(shovel_down))
	shoveler.aim(20.0)
	_check(absf(shoveler.view_angle - PI / 2.0) < 0.0001,
			"shovel aim must saturate at +PI/2 (got %f)" % shoveler.view_angle)
	shoveler.queue_free()

	# 8. THE DIG UNDER THE FEET: with the shovel aimed straight down, a
	# swing carves the bore straight under the wielder (anchor = feet +
	# aim * 12, radii 32) — the probe at (0, 36) inside the bore is open
	# ground, the probe at (0, 70) past it survives.
	var digger2 := _make_figure()
	digger2.global_position = Vector2.ZERO
	digger2.get_node("Weapon").set("selected_weapon", SLOT_SHOVEL)
	digger2.aim(-10.0)
	_make_chunk(Vector2(0, 60), Vector2(240, 160))
	await _settle()
	digger2.get_node("Weapon").call("_swing_shovel")
	await _settle()
	_check(not _covered(Vector2(0, 36)),
			"the point straight under the feet must be dug open")
	_check(_covered(Vector2(0, 70)),
			"the point past the straight-down bore must survive")
	digger2.queue_free()

	if failures == 0:
		print("PASS: issue #682 jackhammer and shovel dig under the character")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
