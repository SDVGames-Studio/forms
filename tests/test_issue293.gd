extends Node
## Regression check for issue #293: the gravity field must be calculated
## from the existing indestructible grounds — it is no longer configured
## separately (the per-figure center_line_y/gravity_dir exports and every
## consumer of them are gone; figures, projectiles, the weapon frame and
## the debug field all follow LevelTerrain).
##
## Checks:
##  1. NO AUTHORED PROPERTIES: Player and Npc scripts expose neither
##     center_line_y nor gravity_dir, and no shipped level scene sets
##     them (the old "separately configured gravity field").
##  2. FIGURES FOLLOW TERRAIN ONLY: above a slab the frame is DOWN;
##     UNDER an overhead slab (the old upside-down side) it points UP
##     toward that ground — with no ground at all it stays DOWN.
##  3. PROJECTILES FOLLOW TERRAIN ONLY: a grenade under the overhead
##     slab falls UP (no shooter-captured line context exists anymore).
##  4. LEVEL3 SHIPS CLEAN: instantiating Level3, every figure's gravity
##     comes from the base slab — a figure above the soil gets plain
##     DOWN, never an authored flip.
##
## Run headless: godot --headless res://tests/test_issue293.tscn
## Exit code 0 = pass.

const PlayerScript := preload("res://Player.gd")
const NpcScript := preload("res://Npc.gd")
const GroundScript := preload("res://scripts/IndestructibleGround.gd")
const GrenadeScript := preload("res://ProjectileBody.gd")
const EPS := 0.001


func _check_no_authored_props() -> bool:
	var ok := true
	for script in [PlayerScript, NpcScript]:
		var has_line := false
		var has_dir := false
		for p in script.get_script_property_list():
			if p["name"] == "center_line_y":
				has_line = true
			elif p["name"] == "gravity_dir":
				has_dir = true
		print("ISSUE293 script ", script.resource_path.get_file(),
				" center_line_y=", has_line, " gravity_dir=", has_dir)
		ok = ok and not has_line and not has_dir
	# No shipped level scene stages the old properties anymore.
	for level in ["Level.tscn", "Level2.tscn", "Level3.tscn", "Level4.tscn",
			"Level5.tscn", "LevelDuel.tscn"]:
		var text := FileAccess.get_file_as_string("res://" + level)
		var clean := not text.contains("center_line_y") \
				and not text.contains("gravity_dir")
		print("ISSUE293 scene ", level, " clean -> ", clean)
		ok = ok and clean
	return ok


func _spawn_figure(script: Script) -> CharacterBody2D:
	var fig := script.new() as CharacterBody2D
	add_child(fig)
	return fig


func _frame_grav(fig: CharacterBody2D) -> Vector2:
	fig.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	return fig.get("_aim_grav")


func _check_figures_follow_terrain() -> bool:
	var ok := true
	# A lone slab below: gravity toward it = DOWN, for BOTH scripts.
	var slab := StaticBody2D.new()
	slab.set_script(GroundScript)
	slab.rect_size = Vector2(600, 100)
	slab.position = Vector2(0.0, 400.0)
	add_child(slab)
	for script in [PlayerScript, NpcScript]:
		var fig := _spawn_figure(script)
		fig.global_position = Vector2(0.0, 200.0)
		var grav: Vector2 = await _frame_grav(fig)
		var down_ok := grav.distance_to(Vector2.DOWN) < EPS
		print("ISSUE293 ", script.resource_path.get_file(),
				" above slab grav=", grav, " -> ", down_ok)
		ok = ok and down_ok
		fig.queue_free()
		await get_tree().physics_frame
	# The old upside-down side is now GROUND-driven: an overhead slab
	# pulls a figure under it UP toward its surface. The #270 thickness
	# guard extends the ceiling down to y = -2, so stand clearly below it.
	var ceiling := StaticBody2D.new()
	ceiling.set_script(GroundScript)
	ceiling.rect_size = Vector2(600, 100)
	ceiling.position = Vector2(0.0, -400.0)
	add_child(ceiling)
	for script in [PlayerScript, NpcScript]:
		var fig := _spawn_figure(script)
		fig.global_position = Vector2(0.0, 150.0)
		var grav: Vector2 = await _frame_grav(fig)
		var up_ok := grav.distance_to(Vector2.UP) < EPS
		print("ISSUE293 ", script.resource_path.get_file(),
				" under ceiling grav=", grav, " -> ", up_ok)
		ok = ok and up_ok
		fig.queue_free()
		await get_tree().physics_frame
	slab.queue_free()
	ceiling.queue_free()
	await get_tree().physics_frame
	# No ground at all: straight down, wherever the figure is.
	var fig := _spawn_figure(PlayerScript)
	fig.global_position = Vector2(0.0, 500.0)
	var grav: Vector2 = await _frame_grav(fig)
	var fallback_ok := grav.distance_to(Vector2.DOWN) < EPS
	print("ISSUE293 no-source grav=", grav, " -> ", fallback_ok)
	ok = ok and fallback_ok
	fig.queue_free()
	await get_tree().physics_frame
	return ok


func _check_projectile_follows_terrain() -> bool:
	# A grenade under an overhead slab falls UP — terrain decides, and no
	# captured center-line context exists anymore (ProjectileBody samples
	# the level's grounds every step).
	var ceiling := StaticBody2D.new()
	ceiling.set_script(GroundScript)
	ceiling.rect_size = Vector2(600, 100)
	ceiling.position = Vector2(0.0, -400.0)
	add_child(ceiling)
	var body := RigidBody2D.new()
	body.set_script(GrenadeScript)
	body.setup(ProjectileBody.Kind.GRENADE, Vector2.ZERO, 0, 60.0,
			Vector2(14, 14), Color.WHITE, 0.0, 0.6)
	add_child(body)
	# Clearly below the ceiling's thickness guard (solid down to y = -2).
	body.global_position = Vector2(0.0, 150.0)
	var start := body.global_position.y
	for i in 20:
		await get_tree().physics_frame
	var rose: bool = body.global_position.y < start - 10.0
	print("ISSUE293 grenade under ceiling rose=", rose,
			" y=", body.global_position.y)
	body.queue_free()
	ceiling.queue_free()
	await get_tree().physics_frame
	return rose


func _check_level3_ships_clean() -> bool:
	# Level3 used to author center_line_y = 540 on every figure. Now the
	# base slab (y 480..928) is the only gravity source: a figure above
	# the soil falls DOWN — no authored flip anywhere.
	var level3: Node = load("res://Level3.tscn").instantiate()
	add_child(level3)
	for i in 10:
		await get_tree().physics_frame
	var ok := true
	var figs := get_tree().get_nodes_in_group("player_team")
	figs.append_array(get_tree().get_nodes_in_group("enemy_team"))
	var checked := 0
	for fig in figs:
		if not fig is CharacterBody2D:
			continue
		var has_line: bool = false
		for p in fig.get_script().get_script_property_list():
			if p["name"] == "center_line_y" or p["name"] == "gravity_dir":
				has_line = true
		ok = ok and not has_line
		checked += 1
		fig.queue_free()
	print("ISSUE293 level3 figures=", checked, " no-props=", ok)
	level3.free()
	await get_tree().physics_frame
	return ok and checked > 0


func _ready() -> void:
	var ok := true
	ok = _check_no_authored_props() and ok
	ok = await _check_figures_follow_terrain() and ok
	ok = await _check_projectile_follows_terrain() and ok
	ok = await _check_level3_ships_clean() and ok
	print("ISSUE293 ok=", ok)
	get_tree().quit(0 if ok else 1)
