extends Node
## Regression check for issue #717 (Weapon Visual Redesign 3b —
## projectile launch animations & trails, sub-issue of the #680 roadmap).
##
##  1. STYLE DATA: the ProjectileTrail STYLES table carries a rocket
##     entry (smoke trail, sane cadence/size/lifetime), a grenade entry
##     (tumble, hand-pop stretch) and a pellet entry (motion stretch) —
##     and the mine/saw/rock stay style-less (the dormant mine must not
##     grow a visible trail).
##  2. LAUNCH STRETCH: a pellet is born stretched along its velocity and
##     eased back to 1:1 within the style's time; same for the rocket.
##  3. IN-FLIGHT CHARACTER: the rocket's DRAWN body tracks its flight
##     direction (which arcs under gravity) while the rigid body itself
##     never spins — angular velocity stays 0, the flight keeps
##     following gravity alone; the grenade tumbles forward while it
##     moves.
##  4. TRAIL: a rocket gets a ProjectileTrail follower that stamps
##     world-space puffs behind the gameplay layer; when the rocket dies
##     the follower frees itself and the puffs fade out on their own —
##     no node leak.
##
## Run headless: godot --headless res://tests/test_issue717.tscn
## Exit code 0 = pass.

const ProjectileScript := preload("res://scripts/Projectile.gd")
const BodyScript := preload("res://scripts/ProjectileBody.gd")
const TrailScript := preload("res://scripts/ProjectileTrail.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _settle(physics_frames: int) -> void:
	for _i in physics_frames:
		await get_tree().physics_frame
	await get_tree().process_frame


## The first ColorRect child — every projectile script draws exactly one
## visual rect (the saw's Polygon2D blade is a different node type).
func _visual_of(node: Node) -> ColorRect:
	for child in node.get_children():
		if child is ColorRect:
			return child
	return null


## A stamped trail puff (duck-typed: only puffs carry a "radius").
func _is_puff(child: Node) -> bool:
	return child is Node2D and child.get("radius") != null


## Poll until the launch stretch has eased back to 1:1 (the headless
## runner is unthrottled, so a handful of frames is plenty of real
## time for a 0.15–0.2 s tween).
func _await_relaxed(visual: ColorRect, frames: int) -> bool:
	for _i in frames:
		await get_tree().process_frame
		if visual.scale.distance_to(Vector2.ONE) < 0.05:
			return true
	return false


func _make_body(kind: int, velocity: Vector2, level: Node2D) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(BodyScript)
	body.setup(kind, velocity, 20, 60.0, Vector2(22, 8),
			Color(0.9, 0.35, 0.15, 1), 40.0, 1.0)
	level.add_child(body)
	body.global_position = Vector2(200, -300)
	return body


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- 1) Style data sanity -------------------------------------------
	var rocket := TrailScript.STYLES["rocket"] as Dictionary
	var grenade := TrailScript.STYLES["grenade"] as Dictionary
	var pellet := TrailScript.STYLES["pellet"] as Dictionary
	_check(rocket.get("trail", false),
			"the rocket must carry a trail entry")
	_check((rocket.get("interval", 1.0) as float) >= 0.02,
			"trail cadence must stay dense enough to read (got %s)"
			% rocket.get("interval"))
	_check((rocket.get("puff_life", 10.0) as float) <= 0.75,
			"puffs must fade within a second (got %s)"
			% rocket.get("puff_life"))
	_check((rocket.get("puff_alpha", 1.0) as float) <= 0.7,
			"puffs must stay translucent, never obscure gameplay (got %s)"
			% rocket.get("puff_alpha"))
	_check((rocket.get("stretch", Vector2.ONE) as Vector2).x > 1.0,
			"the rocket must launch stretched along its flight")
	_check((grenade.get("tumble", 0.0) as float) > 0.0,
			"the grenade must tumble in flight")
	_check((grenade.get("stretch", Vector2.ONE) as Vector2).x < 1.0,
			"the grenade must pop out of the hand small")
	_check(pellet.get("trail", true) == false,
			"short-lived pellets carry no smoke trail")
	_check((pellet.get("stretch", Vector2.ONE) as Vector2).x > 1.0,
			"pellets must launch stretched along their flight")
	_check(not TrailScript.STYLES.has("mine"),
			"the dormant mine must stay style-less (no trail, no launch pop)")
	for key in ["rocket", "grenade", "pellet"]:
		_check((TrailScript.STYLES[key].get("stretch_time", 1.0) as float)
				<= 0.3,
				"%s launch stretch must be quick (got %s)"
				% [key, TrailScript.STYLES[key].get("stretch_time")])

	# --- 2) Pellet launch stretch --------------------------------------
	var area := Area2D.new()
	area.set_script(ProjectileScript)
	area.setup(ProjectileScript.Type.PELLET, Vector2(900, 0), 6, 60.0,
			Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))
	add_child(area)
	var pv := _visual_of(area)
	_check(pv != null, "the pellet must draw its visual rect")
	if pv != null:
		_check(absf(pv.rotation) < 0.01,
				"a rightward pellet must launch pointing along its flight")
		_check(pv.scale.distance_to(
				TrailScript.launch_stretch("pellet")) < 0.05,
				"the pellet must be BORN stretched along its flight (got %s)"
				% pv.scale)
		var pv_relaxed: bool = await _await_relaxed(pv, 30)
		_check(pv_relaxed,
				"the pellet stretch must ease back to 1:1 (got %s)" % pv.scale)
	area.queue_free()

	# --- 3+4) Rocket body: launch, alignment, trail, no physics leak ----
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	var speed0 := Vector2(500, -300)
	var body := _make_body(BodyScript.Kind.ROCKET, speed0, level)
	var bv := _visual_of(body)
	_check(bv != null, "the rocket must draw its visual rect")
	# The follower is a sibling under the level root.
	var follower: Node = null
	for child in level.get_children():
		if child is TrailScript:
			follower = child
	_check(follower != null, "the rocket must drag a trail follower")
	if bv != null:
		_check(absf(bv.rotation - speed0.angle()) < 0.01,
				"the rocket must launch pointing along its launch vector")
		_check(bv.scale.distance_to(
				TrailScript.launch_stretch("rocket")) < 0.05,
				"the rocket must be BORN stretched along its flight (got %s)"
				% bv.scale)
		var bv_relaxed: bool = await _await_relaxed(bv, 30)
		_check(bv_relaxed,
				"the rocket stretch must ease back to 1:1 (got %s)" % bv.scale)
		await _settle(16)
	# In flight: the DRAWN rocket tracks its (arcing) velocity while the
	# physics body never spins and the flight follows gravity alone.
	if bv != null and is_instance_valid(bv):
		_check(absf(bv.rotation - body.linear_velocity.angle()) < 0.15,
				"the drawn rocket must track its flight direction")
		_check(bv.scale.distance_to(Vector2.ONE) < 0.1,
				"the rocket stretch must ease back to 1:1 (got %s)" % bv.scale)
	_check(absf(body.angular_velocity) < 0.001,
			"the alignment must never spin the physics body")
	_check(body.linear_velocity.x > 460.0,
			"no horizontal force may appear beyond the engine's own default"
			+ " damping (vx got %s)" % body.linear_velocity.x)
	_check(body.linear_velocity.y > speed0.y + 100.0,
			"gravity must keep bending the arc (vy got %s)"
			% body.linear_velocity.y)
	# Puffs: world-space, behind the gameplay layer, several alive.
	var puffs := 0
	for child in level.get_children():
		if _is_puff(child):
			puffs += 1
			_check((child as Node2D).z_index < 0,
					"every puff must draw behind the gameplay layer")
	_check(puffs >= 3, "the trail must stamp puffs along the flight (got %d)"
			% puffs)
	# The stream stays in WORLD space — puffs sit along the flight path,
	# not glued to the moving rocket.
	if puffs > 0 and is_instance_valid(body):
		var farthest := 0.0
		for child in level.get_children():
			if _is_puff(child):
				farthest = maxf(farthest,
						(child as Node2D).global_position.distance_to(
							body.global_position))
		_check(farthest > 10.0,
				"puffs must stay behind in world space (farthest %s px)"
				% farthest)
	# The rocket dies -> the follower frees with it, puffs fade alone.
	body.queue_free()
	await _settle(8)
	if follower != null:
		_check(not is_instance_valid(follower),
				"the follower must free itself with its projectile")
	await _settle(50)  # > puff_life
	var leaked := 0
	for child in level.get_children():
		if _is_puff(child):
			leaked += 1
	_check(leaked == 0, "puffs must fade and free themselves (left %d)"
			% leaked)
	level.queue_free()

	# --- 5) Grenade tumble ----------------------------------------------
	var glevel := Node2D.new()
	glevel.name = "GrenadeLevel"
	add_child(glevel)
	var grenade_body := _make_body(BodyScript.Kind.GRENADE,
			Vector2(400, 0), glevel)
	await get_tree().physics_frame
	var gv := _visual_of(grenade_body)
	var start_rot := 0.0
	if gv != null:
		start_rot = gv.rotation
	await _settle(12)  # ~0.2 s of flight
	if gv != null and is_instance_valid(gv):
		var turned: float = gv.rotation - start_rot
		_check(turned > 0.3,
				"a rightward grenade must tumble forward (turned %.2f rad)"
				% turned)
		_check(turned <= TrailScript.tumble_rate("grenade") * 0.25,
				"the tumble must respect its rate cap (turned %.2f rad)"
				% turned)
		_check(absf(grenade_body.angular_velocity) < 0.001,
				"the tumble must never spin the physics body")
		_check(grenade_body.linear_velocity.x > 370.0,
				"no horizontal force may appear beyond the engine's own"
				+ " default damping (vx got %s)"
				% grenade_body.linear_velocity.x)
	grenade_body.queue_free()
	glevel.queue_free()
	await get_tree().physics_frame

	if failures > 0:
		push_error("issue #717 test: %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("issue #717 test: all checks passed")
	get_tree().quit(0)
