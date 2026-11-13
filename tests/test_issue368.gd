extends Node
## Regression check for issue #368: weapon shots emit light.
##  - ShotLight.create builds a PointLight2D with the shared radial
##    gradient texture and an additive glow sprite, scaled to the
##    requested radius; fade() fades the energy out and frees the node;
##    flicker > 0 wobbles the energy.
##  - Every weapon projectile (pellet, rocket, grenade) carries a
##    ShotLight child; a muzzle flash light appears where it spawned.
##  - The railgun beam carries a light that fades with the beam.
##  - An explosion flashes a big fading light that frees itself.
##
## Run headless: godot --headless res://tests/test_issue368.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE368 %s — %s" % ["ok" if ok else "FAIL", what])


## Issue #368: does `node` (or any descendant) hold a ShotLight?
func _has_shot_light(node: Node) -> bool:
	for child in node.get_children():
		if child is ShotLight or _has_shot_light(child):
			return true
	return false


func _ready() -> void:
	# 1) The light node itself.
	var light := ShotLight.create(Color(1.0, 0.8, 0.4), 100.0, 2.0)
	add_child(light)
	_check("ShotLight is a PointLight2D", light is PointLight2D)
	_check("light has the radial gradient texture",
		light.texture is GradientTexture2D)
	_check("light scale matches the radius (256 px texture)",
		is_equal_approx(light.texture_scale, 100.0 / 128.0))
	var glow: Sprite2D = light.get_node_or_null("Glow")
	var glow_ok := glow != null and glow.material is CanvasItemMaterial \
		and (glow.material as CanvasItemMaterial).blend_mode \
		== CanvasItemMaterial.BLEND_MODE_ADD
	_check("light carries an additive glow sprite", glow_ok)
	var other := ShotLight.create(Color(0.2, 0.9, 0.4), 60.0, 1.0)
	add_child(other)
	_check("the radial texture is shared between lights",
		other.texture == light.texture)
	other.queue_free()

	# 2) fade() lowers the energy and frees the node; flicker wobbles it.
	var lowest := light.energy
	light.fade(0.15)
	for i in 30:
		await get_tree().process_frame
		if is_instance_valid(light):
			lowest = minf(lowest, light.energy)
	_check("fade() lowers the energy", lowest < 2.0)
	for i in 60:
		await get_tree().process_frame
		if not is_instance_valid(light):
			break
	_check("fade() frees the light when done", not is_instance_valid(light))
	var flick := ShotLight.create(Color(1.0, 0.5, 0.2), 100.0, 2.0, true, 0.3)
	add_child(flick)
	var wobbled := false
	for i in 30:
		await get_tree().process_frame
		if is_instance_valid(flick) and not is_equal_approx(flick.energy, 2.0):
			wobbled = true
	_check("flicker wobbles the energy", wobbled)
	flick.queue_free()

	# 3) Shots in a minimal wielder tree (the same structure Weapon uses:
	# level root -> figure -> weapon) — pellets, rocket, grenade.
	var root := Node2D.new()
	add_child(root)
	var holder := Node2D.new()
	root.add_child(holder)
	var weapon: Node2D = WeaponScript.new()
	holder.add_child(weapon)

	var pellet: Area2D = weapon._spawn_projectile(0, Vector2(900, 0), 6,
		0.35, Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))
	_check("the pellet carries a shot light", _has_shot_light(pellet))
	_check("a muzzle flash appeared at the spawn point", _has_shot_light(root))
	pellet.queue_free()

	var rocket: RigidBody2D = weapon._spawn_body(0, Vector2(200, 0), 35, 3.0,
		Vector2(22, 8), Color(0.9, 0.35, 0.15, 1), 90.0, 1.0)
	_check("the rocket carries an exhaust light", _has_shot_light(rocket))
	var grenade: RigidBody2D = weapon._spawn_body(1, Vector2(100, -300), 40, 3.0,
		Vector2(14, 14), Color(0.3, 0.7, 0.3, 1), 100.0, 0.6)
	_check("the grenade carries a glow light", _has_shot_light(grenade))

	# 4) The explosion flashes a big fading light under the level root.
	rocket._explode()
	_check("the explosion flashes a fading light", _has_shot_light(root))
	var boom: Node = null
	for child in root.get_children():
		if child is ShotLight:
			boom = child
	if boom != null:
		_check("the explosion flash starts bright", boom.energy > 1.0)
	for i in 90:
		await get_tree().process_frame
	_check("the explosion flash frees itself", boom == null
		or not is_instance_valid(boom))

	# 5) The railgun beam carries a light that fades with the beam.
	await get_tree().physics_frame
	weapon._fire_railgun(0.5)
	var beam_lit := false
	for child in root.get_children():
		if child is Line2D and _has_shot_light(child):
			beam_lit = true
	_check("the railgun beam carries a muzzle light", beam_lit)
	for i in 30:
		await get_tree().process_frame
	root.queue_free()
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE368 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE368 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
