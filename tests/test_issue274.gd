extends Node
## Regression check for issue #274 (v1 + v2): the shotgun's pellets
## vanished on their first physics frame with no hit anywhere.
##
## v1 (fixed in PR #276): the out-of-bounds check compared the pellet's
## WORLD position against get_viewport_rect(), which is in CANVAS (screen)
## coordinates anchored at the world origin — any figure beyond the first
## screen of the map fired pellets that died instantly.
##
## v2 ("same bug again", 2026-11-26): the v1 fix kept a camera-view cull,
## and it still freed a pellet the moment it was born or flew outside the
## CURRENT view — the shared camera starts in the free GLOBAL mode and the
## player's pan persists, so figures routinely fire from outside the view
## (Team2 on Level2 stages at x ~1880-2060 while a GLOBAL view at the
## origin ends at x ~576). The cull is gone entirely: a pellet flies its
## whole lifetime fuse no matter where the camera looks.
##
## Run headless: godot --headless res://tests/test_issue274.tscn
## Exit code 0 = pass.

const ProjectileScript := preload("res://scripts/Projectile.gd")


func _spawn_pellet(world: Vector2, velocity: Vector2,
		lifetime: float) -> Area2D:
	var pellet := Area2D.new()
	pellet.set_script(ProjectileScript)
	pellet.setup(ProjectileScript.Type.PELLET, velocity, 6, lifetime,
		Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))
	add_child(pellet)
	pellet.global_position = world
	return pellet


func _settle(physics_frames: int) -> void:
	for _i in physics_frames:
		await get_tree().physics_frame
	await get_tree().process_frame


func _ready() -> void:
	var ok := true
	# The camera view is the default origin screen: world x/y in
	# [-576, 576] at zoom 1 (canvas transform maps world -> canvas, no
	# camera node needed).
	get_viewport().set_canvas_transform(Transform2D(0.0, Vector2(576, 576)))

	# --- v1 case: a pellet ON screen must survive its first frames. ---
	var world := Vector2(200, 300)
	var viewed := _spawn_pellet(world, Vector2(900, 0), 0.5)
	await _settle(2)
	var alive_when_viewed: bool = is_instance_valid(viewed)
	print("ISSUE274 alive_when_viewed=", alive_when_viewed)
	ok = ok and alive_when_viewed
	viewed.queue_free()
	await _settle(2)

	# --- v2 case: a pellet born FAR outside the camera view (the
	# off-view shooter / panned / zoomed view) must STILL fly — the view
	# never decides a projectile's death. Before the v2 fix it was freed
	# on its very first physics frame.
	var offworld := Vector2(1880, 300)
	var offview := _spawn_pellet(offworld, Vector2(900, 0), 0.5)
	await _settle(6)
	var alive_when_offview: bool = is_instance_valid(offview)
	print("ISSUE274 alive_when_offview=", alive_when_offview)
	ok = ok and alive_when_offview
	var flown: bool = is_instance_valid(offview) \
			and offview.global_position.x > 1900.0
	print("ISSUE274 offview_pellet_flying=", flown)
	ok = ok and flown

	# --- No leak: the pellet still dies on its own lifetime fuse. ---
	await _settle(40)  # ~0.66 s at 60 Hz physics, fuse is 0.5 s
	var expired_on_fuse: bool = not is_instance_valid(offview)
	print("ISSUE274 expired_on_fuse=", expired_on_fuse)
	ok = ok and expired_on_fuse

	# --- A pellet that hits a body still dies on impact (the view cull
	# was not the only death path — this pins the intended one). ---
	var blocker := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 57.6
	shape.shape = capsule
	blocker.add_child(shape)
	blocker.position = Vector2(1880, 0)
	add_child(blocker)
	await _settle(2)
	var striker := _spawn_pellet(Vector2(1600, 0), Vector2(900, 0), 5.0)
	var hit := [false]
	striker.body_entered.connect(
		func(_body: Node2D) -> void: hit[0] = true)
	await _settle(30)
	print("ISSUE274 striker_valid=", is_instance_valid(striker),
			" hit=", hit[0])
	var died_on_impact: bool = not is_instance_valid(striker) and hit[0]
	print("ISSUE274 died_on_impact=", died_on_impact)
	ok = ok and died_on_impact
	blocker.queue_free()

	print("ISSUE274 ok=", ok)
	get_tree().quit(0 if ok else 1)
