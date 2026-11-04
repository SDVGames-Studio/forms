extends Node
## Regression check for issue #290: "debug gravity vector field".
## A settings switch ("Gravity Field", next to the debug mode) shows the
## level's gravity field as arrows on a world-space grid whose cell is
## two character widths (2 x 64 = 128 px) wide. The sampled gravity must
## match the figures' own contract: an authored central line beats
## terrain surface gravity (down above the line, up below it), otherwise
## gravity bends toward the nearest indestructible surface.
##
## Checks (Level3 authors a central line at y = 540 AND an indestructible
## base slab; Level has a disc hill but no central line):
##  1. With the switch on, the level's camera hosts exactly ONE
##     GravityFieldDebug overlay (group "gravity_field_debug").
##  2. The grid cell equals two character widths (128 px).
##  3. Level3: above the central line gravity points DOWN, below it UP —
##     the authored line beats the terrain slab.
##  4. Level (terrain-only): near the disc hill gravity points toward the
##     disc centre — radially, including from the side (bent field).
##  5. A second overlay instance removes itself (dedup).
##  6. With the switch off no overlay is created at all.
##
## Run headless: godot --headless res://tests/test_issue290.tscn
## Exit code 0 = pass.

const FieldScript := preload("res://scripts/GravityFieldDebug.gd")
const Stats := preload("res://scripts/CharacterStats.gd")

const CENTER_LINE_Y := 540.0
const HILL_POS := Vector2(120.0, 620.0)
const HILL_RADIUS := 224.0


func _ready() -> void:
	var ok := true
	GameConfig.debug_gravity_field = true

	# --- Level3: central line + terrain slab. ---
	var level3: Node = load("res://Level3.tscn").instantiate()
	add_child(level3)
	for i in 30:
		await get_tree().physics_frame
	var field := _overlay()
	var cam := _camera()
	var overlay_ok: bool = field != null and cam != null \
			and field.get_parent() == cam
	print("ISSUE290 overlay=", field != null, " on_camera=", overlay_ok)
	ok = ok and overlay_ok

	# --- 2. Grid cell = two character widths. ---
	var cell_ok: bool = field != null \
			and is_equal_approx(FieldScript.CELL, 2.0 * Stats.BODY_SIZE)
	print("ISSUE290 cell=", FieldScript.CELL if field != null else -1.0,
			" expected=", 2.0 * Stats.BODY_SIZE, " ok=", cell_ok)
	ok = ok and cell_ok

	# --- 3. The central line beats the terrain slab. ---
	if field != null:
		field._sample_center_line()
	var above: Vector2 = field._gravity_at(Vector2(400.0, 200.0)) \
			if field != null else Vector2.ZERO
	var below: Vector2 = field._gravity_at(Vector2(400.0, 800.0)) \
			if field != null else Vector2.ZERO
	var line_ok: bool = above.dot(Vector2.DOWN) > 0.99 \
			and below.dot(Vector2.UP) > 0.99
	print("ISSUE290 line_above=", above, " line_below=", below, " ok=", line_ok)
	ok = ok and line_ok

	level3.free()
	await get_tree().physics_frame

	# --- 4. Terrain-only gravity bends toward the nearest surface. ---
	var level1: Node = load("res://Level.tscn").instantiate()
	add_child(level1)
	for i in 30:
		await get_tree().physics_frame
	field = _overlay()
	var terrain_ok := false
	if field != null:
		field._sample_center_line()
		# Straight above the disc: toward its centre = DOWN.
		var top: Vector2 = field._gravity_at(HILL_POS + Vector2(0.0,
				-(HILL_RADIUS + 100.0)))
		# Left of the disc: toward its centre = RIGHT (bent, not global).
		var side: Vector2 = field._gravity_at(HILL_POS + Vector2(
				-(HILL_RADIUS + 100.0), 0.0))
		terrain_ok = top.dot(Vector2.DOWN) > 0.99 \
				and side.dot(Vector2.RIGHT) > 0.99
		print("ISSUE290 terrain_top=", top, " terrain_side=", side,
				" ok=", terrain_ok)
	else:
		print("ISSUE290 terrain overlay missing")
	ok = ok and terrain_ok

	# --- 5. A duplicate overlay frees itself. ---
	var dup := FieldScript.new()
	add_child(dup)
	await get_tree().physics_frame
	var dedup_ok: bool = (not is_instance_valid(dup)
			or dup.is_queued_for_deletion()) \
			and get_tree().get_nodes_in_group("gravity_field_debug").size() == 1
	print("ISSUE290 dedup=", dedup_ok)
	ok = ok and dedup_ok

	GameConfig.debug_gravity_field = false
	level1.free()
	await get_tree().physics_frame

	# --- 6. Switch off: no overlay is created. ---
	var level2: Node = load("res://Level2.tscn").instantiate()
	add_child(level2)
	for i in 30:
		await get_tree().physics_frame
	var off_ok: bool = get_tree().get_nodes_in_group(
			"gravity_field_debug").is_empty() and _camera() != null
	print("ISSUE290 off_no_overlay=", off_ok)
	ok = ok and off_ok

	print("ISSUE290 ok=", ok)
	get_tree().quit(0 if ok else 1)


func _overlay() -> Node:
	var node := get_tree().get_first_node_in_group("gravity_field_debug")
	return node if node != null and is_instance_valid(node) else null


func _camera() -> Node:
	for cam in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(cam) and cam.get_tree() != null:
			return cam
	return null
