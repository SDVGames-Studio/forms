extends Node
## Regression check for issue #270 (part 2 — figure pose vs gravity):
## on the radial arena (Level5, gravity toward the big disc's centre)
## every figure's BODY children (body visual rect / ShapeVisual body /
## collision shape) are rotated so the figure's bottom faces the ground —
## rotation == gravity.angle() - PI/2 — while the HUD (name label, health
## bar, shield) and the camera keep rotation 0.
## On the flat Level.tscn gravity is straight down, so every body child
## must stay unrotated (0).
##
## Run headless: godot --headless res://tests/test_issue270_pose.tscn
## Exit code 0 = pass.

const Terrain := preload("res://scripts/LevelTerrain.gd")
const Pose := preload("res://scripts/FigurePose.gd")
const EPS := 0.05


func _ready() -> void:
	var ok := await _check_level(preload("res://scenes/levels/Level5.tscn").instantiate())
	ok = (await _check_level(preload("res://scenes/levels/Level.tscn").instantiate())) and ok
	print("ISSUE270POSE ok=", ok)
	get_tree().quit(0 if ok else 1)


func _check_level(level: Node) -> bool:
	add_child(level)
	# Let _ready + GameConfig.apply (deferred) settle and one physics
	# frame run so Player/Npc _physics_process applied the pose.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ok := true
	var figures: Array = []
	figures.append_array(get_tree().get_nodes_in_group("player_team"))
	figures.append_array(get_tree().get_nodes_in_group("enemy_team"))
	print("ISSUE270POSE ", level.name, " figures=", figures.size())
	for fig in figures:
		var figure := fig as Node2D
		if figure == null or not figure.is_inside_tree() or not is_instance_valid(figure):
			continue
		var grav := Vector2.DOWN
		if Terrain.has_sources(figure):
			grav = Terrain.gravity_vector(figure)
		var target := grav.angle() - PI / 2.0
		var bodies := 0
		for child in figure.get_children():
			# Note: Control is not a Node2D in Godot 4 — read `rotation`
			# through get() so both visuals (ColorRect/ShapeVisual Controls)
			# and collision shapes (Node2D) are checked the same way.
			var rot: Variant = child.get("rotation")
			if rot == null:
				continue
			if Pose.is_body_child(child):
				bodies += 1
				if absf(wrapf(float(rot) - target, -PI, PI)) > EPS:
					print("FAIL ", figure.name, " body ", child.name,
							" rot=", rot, " want=", target)
					ok = false
			elif child is Label or child is Camera2D:
				if absf(float(rot)) > EPS:
					print("FAIL ", figure.name, " hud ", child.name,
							" rot=", rot)
					ok = false
		if bodies == 0:
			print("FAIL ", figure.name, " has no body children")
			ok = false
	level.queue_free()
	await get_tree().physics_frame
	return ok
