extends Node
## Regression check for issue #719 (Weapon Visual Redesign 4a — grenade
## & mine cartoon sprites, sub-issue of the #680 roadmap).
##
##  1. REGISTRY DATA: the grenade and mine entries in WeaponVisuals
##     STYLES are textured (own sprite, readable size, waist-hold
##     anchor/lift/drop, small throw recoil) with their identity colors
##     kept; the PROJECTILE_SPRITES table covers exactly the two lobbed
##     kinds; the slot order (12 entries) is intact.
##  2. FROZEN GAMEPLAY: every grenade/mine constant the #680 constraints
##     freeze — speeds, damage, blast, fuse, mass, bounce, trigger,
##     rest speed, shots per turn — is pinned to its pre-#719 value.
##  3. HELD WEAPONS: the grenade (weapon 2) and the mine (weapon 4)
##     render through the _held_sprite with the registry textures at
##     the registry sizes, and the plain ColorRect path is off for them.
##  4. THROWN GRENADE: the rigid body draws the cartoon sprite as a
##     child of its visual rect (rect fill transparent); the physics
##     shape/mass/bounce stay 14 px / 0.6 / 0.45; the #717 launch pop
##     and tumble carry onto the sprite while the physics body never
##     spins.
##  5. PLACED MINE: same sprite wiring (18 px, MINE texture); the
##     dormant mine paints full colors (stealthy dark), the armed fuse
##     blink flashes the sprite red through modulate, and the
##     detonation still frees the body.
##  6. LANDING DUST: a grenade touching ground pops a soft Puff in the
##     level, drawn behind the gameplay layer.
##
## Run headless: godot --headless res://tests/test_issue719.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const WeaponVisualsScript := preload("res://scripts/WeaponVisuals.gd")
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


## A shooter whose aim_dir answers the test's live aim vector, with a
## commandable walk signal (issue #700: 0.0 = planted) and stance
## gravity, answering the Character accessors Weapon reads.
class AimShooter:
	extends CharacterBody2D
	var aim := Vector2(1, 0)
	var grav := Vector2.DOWN
	var walk := 0.0
	func aim_dir(_facing: float, _grav: float = 1.0) -> Vector2:
		return aim
	func current_gravity() -> Vector2:
		return grav
	func walk_command() -> float:
		return walk


func _make_weapon() -> Node2D:
	var shooter := AimShooter.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _make_body(kind: int, velocity: Vector2, level: Node2D,
		size: Vector2, mass: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(BodyScript)
	body.setup(kind, velocity, 40, 60.0, size,
			Color(0.3, 0.7, 0.3, 1), 100.0, mass)
	level.add_child(body)
	body.global_position = Vector2(200, -300)
	return body


## The cartoon Sprite2D of a body: a child of its visual ColorRect.
func _sprite_of(body: Node) -> Sprite2D:
	for child in body.get_children():
		if child is ColorRect:
			for sub in child.get_children():
				if sub is Sprite2D:
					return sub
	return null


## The physics CollisionShape2D of a body.
func _shape_of(body: Node) -> CollisionShape2D:
	for child in body.get_children():
		if child is CollisionShape2D:
			return child
	return null


## A stamped dust puff (duck-typed: only puffs carry a "radius").
func _is_puff(child: Node) -> bool:
	return child is Node2D and child.get("radius") != null


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- 1) Registry data -------------------------------------------------
	var styles: Array = WeaponVisualsScript.STYLES
	_check(styles.size() == 12,
			"the slot order must stay intact — 12 entries (got %s)"
			% styles.size())
	var grenade_style: Dictionary = styles[2]
	var mine_style: Dictionary = styles[5]
	_check(grenade_style.has("texture") \
				and grenade_style["texture"] == WeaponVisualsScript.GRENADE_TEX,
			"the grenade entry must carry the grenade sprite")
	_check(mine_style.has("texture") \
				and mine_style["texture"] == WeaponVisualsScript.MINE_TEX,
			"the mine entry must carry the mine sprite")
	_check(WeaponVisualsScript.textured(2) and WeaponVisualsScript.textured(5),
			"grenade and mine must render through the sprite path")
	_check(grenade_style["color"] == Color(0.3, 0.7, 0.3, 1),
			"the grenade identity color must stay (got %s)"
			% grenade_style["color"])
	_check(mine_style["color"] == Color(0.22, 0.24, 0.3, 1),
			"the mine identity color must stay (got %s)" % mine_style["color"])
	for entry in [["grenade", grenade_style, Vector2(16, 16)],
			["mine", mine_style, Vector2(18, 18)]]:
		var s: Dictionary = entry[1]
		var want_size: Vector2 = entry[2]
		_check((s["size"] as Vector2) == want_size,
				"the %s style size must be %s (got %s)"
				% [entry[0], want_size, s["size"]])
		_check((s["size"] as Vector2).x >= 14.0 and (s["size"] as Vector2).y >= 14.0,
				"the %s must stay readable at gameplay scale (got %s)"
				% [entry[0], s["size"]])
		_check((s.get("anchor", 0.0) as float) >= 26.0 \
				and (s.get("anchor", 0.0) as float) <= 34.0,
				"the %s anchor must stay in the #559 band (got %s)"
				% [entry[0], s.get("anchor")])
		_check(s.has("lift_keep") and s.has("drop"),
				"the %s must carry the waist-hold tuning" % entry[0])
		_check((s.get("recoil", 0.0) as float) >= 3.0 \
				and (s.get("recoil", 0.0) as float) <= 8.0,
				"the %s throw recoil must stay small (got %s)"
				% [entry[0], s.get("recoil")])
	var proj_grenade: Dictionary = WeaponVisualsScript.projectile_sprite("grenade")
	var proj_mine: Dictionary = WeaponVisualsScript.projectile_sprite("mine")
	_check(not proj_grenade.is_empty() \
				and proj_grenade["texture"] == WeaponVisualsScript.GRENADE_TEX \
				and (proj_grenade["size"] as Vector2) == Vector2(16, 16),
			"the thrown grenade must have a registry projectile sprite")
	_check(not proj_mine.is_empty() \
				and proj_mine["texture"] == WeaponVisualsScript.MINE_TEX \
				and (proj_mine["size"] as Vector2) == Vector2(18, 18),
			"the placed mine must have a registry projectile sprite")
	for other in ["saw", "rock", "rocket", ""]:
		_check(WeaponVisualsScript.projectile_sprite(other).is_empty(),
				"%s must keep its code-drawn projectile visual" % other)
	_check(not TrailScript.STYLES.has("mine"),
			"the dormant mine must stay trail-less (#717)")

	# --- 2) Frozen gameplay numbers ---------------------------------------
	_check(WeaponScript.GRENADE_SPEED == 550.0
			and WeaponScript.GRENADE_DAMAGE == 40
			and WeaponScript.GRENADE_BLAST == 100.0
			and WeaponScript.GRENADE_FUSE == 3.0
			and WeaponScript.GRENADE_MASS == 0.6,
			"the grenade gameplay numbers must be frozen by #680")
	_check(WeaponScript.MINE_SPEED == 480.0
			and WeaponScript.MINE_DAMAGE == 40
			and WeaponScript.MINE_BLAST == 100.0
			and WeaponScript.MINE_MASS == 0.8,
			"the mine gameplay numbers must be frozen by #680")
	_check(WeaponScript.SHOTS_PER_TURN[2] == 1
			and WeaponScript.SHOTS_PER_TURN[4] == 1,
			"the grenade and mine keep one shot per turn")
	_check(BodyScript.MINE_TRIGGER == 1.2 * 64.0
			and BodyScript.MINE_FUSE == 2.0
			and BodyScript.MINE_REST_SPEED == 30.0,
			"the mine trigger/fuse/rest numbers must be frozen")
	_check((BodyScript.BOUNCE[BodyScript.Kind.GRENADE] as float) == 0.45,
			"the grenade bounce must stay 0.45")
	_check((BodyScript.BOUNCE[BodyScript.Kind.MINE] as float) == 0.2,
			"the mine bounce must stay 0.2")

	# --- 3) Held weapons ----------------------------------------------------
	var gun := _make_weapon()
	gun.selected_weapon = 2
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(gun._held_style_index() == 2 and gun._held_textured(),
			"the held grenade must map to its textured style (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.GRENADE_TEX,
			"the held grenade must draw the grenade sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held grenade sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the grenade")
	gun.selected_weapon = 4
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(gun._held_style_index() == 5,
			"the held mine must map to style 5 (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.MINE_TEX,
			"the held mine must draw the mine sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held mine sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the mine")
	gun.get_parent().queue_free()
	await get_tree().physics_frame

	# --- 4) Thrown grenade body --------------------------------------------
	var glevel := Node2D.new()
	glevel.name = "GrenadeLevel"
	add_child(glevel)
	var grenade_body := _make_body(BodyScript.Kind.GRENADE,
			Vector2(400, 0), glevel, Vector2(14, 14), 0.6)
	await get_tree().physics_frame
	var gspr := _sprite_of(grenade_body)
	_check(gspr != null, "the thrown grenade must draw its cartoon sprite")
	if gspr != null:
		_check(gspr.texture == WeaponVisualsScript.GRENADE_TEX,
				"the thrown grenade sprite must be the registry texture")
		_check(gspr.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
				"the thrown grenade must draw at 16 px (got %s)" % gspr.scale)
		_check(gspr.global_position.distance_to(
					grenade_body.global_position) < 0.1,
				"the sprite must sit centred on the body (off %s)"
				% gspr.global_position.distance_to(
					grenade_body.global_position))
		# #717's launch pop carries onto the sprite through the rect.
		_check(gspr.global_scale.x < 0.2,
				"the grenade must pop out of the hand small (got %s)"
				% gspr.global_scale)
		await get_tree().create_timer(0.4).timeout
		_check(gspr.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
				"the launch pop must ease back to 1:1 (got %s)" % gspr.scale)
	var grect: ColorRect = null
	for child in grenade_body.get_children():
		if child is ColorRect:
			grect = child
	_check(grect != null and is_equal_approx(grect.color.a, 0.0),
			"the grenade's rect fill must be transparent (sprite is the body)")
	var gshape := _shape_of(grenade_body)
	_check(gshape != null and (gshape.shape as RectangleShape2D).size
				== Vector2(14, 14),
			"the grenade physics shape must stay 14x14 (got %s)"
			% [gshape.shape.size if gshape != null else null])
	_check(is_equal_approx(grenade_body.mass, 0.6),
			"the grenade mass must stay 0.6 (got %s)" % grenade_body.mass)
	_check(is_equal_approx(
				grenade_body.physics_material_override.bounce, 0.45),
			"the grenade bounce must stay 0.45 (got %s)"
			% grenade_body.physics_material_override.bounce)
	# Tumble: the DRAWN sprite spins forward, the physics body never does.
	var start_rot := 0.0
	if gspr != null:
		start_rot = gspr.global_rotation
	await get_tree().create_timer(0.25).timeout
	if gspr != null and is_instance_valid(gspr):
		# Wrap-safe across the +/-PI seam: the continuous tumble keeps
		# growing, but global_rotation wraps inside (-PI, PI].
		var turned: float = wrapf(gspr.global_rotation - start_rot,
				-PI, PI)
		_check(turned > 0.3,
				"a rightward grenade must tumble forward (turned %.2f rad)"
				% turned)
		_check(turned <= TrailScript.tumble_rate("grenade") * 0.3,
				"the tumble must respect its rate cap (turned %.2f rad)"
				% turned)
	_check(absf(grenade_body.angular_velocity) < 0.001,
			"the tumble must never spin the physics body")
	_check(grenade_body.linear_velocity.x > 370.0,
			"no horizontal force may appear beyond the engine's own default"
			+ " damping (vx got %s)" % grenade_body.linear_velocity.x)
	grenade_body.queue_free()
	glevel.queue_free()
	await get_tree().physics_frame

	# --- 5) Placed mine body ------------------------------------------------
	var mlevel := Node2D.new()
	mlevel.name = "MineLevel"
	add_child(mlevel)
	var mine_body := _make_body(BodyScript.Kind.MINE,
			Vector2(0, 0), mlevel, Vector2(14, 14), 0.8)
	await get_tree().physics_frame
	var mspr := _sprite_of(mine_body)
	_check(mspr != null, "the placed mine must draw its cartoon sprite")
	if mspr != null:
		_check(mspr.texture == WeaponVisualsScript.MINE_TEX,
				"the placed mine sprite must be the registry texture")
		_check(mspr.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
				"the placed mine must draw at 18 px (got %s)" % mspr.scale)
		_check(mspr.modulate == Color.WHITE,
				"the dormant mine must paint full colors (got %s)"
				% mspr.modulate)
	var mshape := _shape_of(mine_body)
	_check(mshape != null and (mshape.shape as RectangleShape2D).size
				== Vector2(14, 14),
			"the mine physics shape must stay 14x14 (got %s)"
			% [mshape.shape.size if mshape != null else null])
	# Arm the fuse: a figure steps into the trigger radius.
	var victim := CharacterBody2D.new()
	victim.add_to_group("player_team")
	mlevel.add_child(victim)
	victim.global_position = mine_body.global_position + Vector2(40, 0)
	await get_tree().create_timer(0.5).timeout
	_check(mine_body._armed,
			"the mine must arm when a figure steps into the trigger radius")
	# The armed fuse blinks the SPRITE red through modulate.
	var saw_red := false
	var saw_white := false
	if mspr != null and is_instance_valid(mspr):
		for i in 40:
			await get_tree().physics_frame
			if not is_instance_valid(mspr):
				break
			var m: Color = mspr.modulate
			if m.r > 0.9 and m.g < 0.3:
				saw_red = true
			if m == Color.WHITE:
				saw_white = true
	_check(saw_red and saw_white,
			"the armed mine must blink its sprite red and back (red=%s white=%s)"
			% [saw_red, saw_white])
	# The detonation still runs its full course and frees the body.
	await get_tree().create_timer(2.5).timeout
	_check(not is_instance_valid(mine_body),
			"the armed mine must detonate and free itself after the fuse")
	victim.queue_free()
	mlevel.queue_free()
	await get_tree().physics_frame

	# --- 6) Landing dust ----------------------------------------------------
	var dlevel := Node2D.new()
	dlevel.name = "DustLevel"
	add_child(dlevel)
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(400, 20)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	dlevel.add_child(floor_body)
	floor_body.global_position = Vector2(0, 100)
	var drop_grenade := _make_body(BodyScript.Kind.GRENADE,
			Vector2(30, 80), dlevel, Vector2(14, 14), 0.6)
	drop_grenade.global_position = Vector2(0, 20)
	var puffs := 0
	for i in 150:
		await get_tree().physics_frame
		if not is_instance_valid(drop_grenade):
			break
		for child in dlevel.get_children():
			if _is_puff(child):
				puffs += 1
				_check((child as Node2D).z_index < 0,
						"the dust puff must draw behind the gameplay layer")
	_check(puffs > 0,
			"a landing grenade must pop a dust puff (got %d)" % puffs)
	if is_instance_valid(drop_grenade):
		drop_grenade.queue_free()
	dlevel.queue_free()
	await get_tree().physics_frame

	if failures > 0:
		push_error("issue #719 test: %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("issue #719 test: all checks passed")
	get_tree().quit(0)
