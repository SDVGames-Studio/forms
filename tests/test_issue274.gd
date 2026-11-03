extends Node
## Regression check for issue #274: the shotgun's pellets vanished on
## their first physics frame. The out-of-bounds check compared the
## projectile's WORLD position against get_viewport_rect(), which is in
## CANVAS (screen) coordinates anchored at the world origin — so any
## figure outside the first screen of the map (the reworked levels put
## figures at x up to ~2600, y up to ~2100) fired pellets that died
## instantly: the shot was counted, no bullet became visible.
##
## Run headless: godot --headless res://tests/test_issue274.tscn
## Exit code 0 = pass.

const ProjectileScript := preload("res://Projectile.gd")


func _ready() -> void:
	var ok := true
	# A real figure spot from the reworked Level2 — far outside the
	# 1152x648 rect at the world origin. Center the camera view on it
	# (canvas transform maps world -> canvas space, no camera node needed).
	var world := Vector2(1768, 400)
	get_viewport().set_canvas_transform(
		Transform2D(0.0, Vector2(576, 324) - world))

	# --- Pellet on screen (world position, camera view centered on it). ---
	var pellet := Area2D.new()
	pellet.set_script(ProjectileScript)
	pellet.setup(ProjectileScript.Type.PELLET, Vector2(900, 0), 6, 0.35,
		Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))
	add_child(pellet)
	pellet.global_position = world
	# Two physics frames: the first tick runs the (previously fatal) bounds
	# check, the second confirms the pellet is still alive after it.
	for _i in 2:
		await get_tree().physics_frame
	var alive_when_viewed: bool = is_instance_valid(pellet)
	print("ISSUE274 alive_when_viewed=", alive_when_viewed)
	ok = ok and alive_when_viewed

	# --- Pellet far beyond the view margin must still be culled. ---
	var stray := Area2D.new()
	stray.set_script(ProjectileScript)
	stray.setup(ProjectileScript.Type.PELLET, Vector2.ZERO, 6, 0.35,
		Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))
	add_child(stray)
	stray.global_position = world + Vector2(5000, 5000)
	for _i in 2:
		await get_tree().physics_frame
	var culled_when_offscreen: bool = not is_instance_valid(stray)
	print("ISSUE274 culled_when_offscreen=", culled_when_offscreen)
	ok = ok and culled_when_offscreen

	print("ISSUE274 ok=", ok)
	get_tree().quit(0 if ok else 1)
