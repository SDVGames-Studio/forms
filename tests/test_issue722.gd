extends Node
## Regression check for issue #722 (Weapon Visual Redesign 4d —
## jackhammer & circular saw cartoon sprites, sub-issue of the #680
## roadmap).
##
##  1. REGISTRY DATA: the two contact-weapon entries in WeaponVisuals
##     STYLES are textured (own sprite, readable size, waist-hold
##     lift/drop) with their identity colors kept; the jackhammer
##     carries recoil 0 (the drill shake IS the animation) and the saw
##     keeps the part-3 default throw kick (no recoil override); both
##     carry steel-spark contact-feedback palettes, the saw's with a
##     smaller flash size; the slot order (12 entries) is intact.
##  2. FROZEN GAMEPLAY: every constant the #680 constraints freeze —
##     drill times/speed/radius/reach/DPS, saw speeds/mass/spin/
##     suction/cut DPS, shots per turn — is pinned to its pre-#722
##     value.
##  3. HELD WEAPONS: the jackhammer (weapon 5) and the saw (weapon 9)
##     render through the _held_sprite with the registry textures at
##     the registry sizes, and the plain ColorRect path is off for
##     them.
##  4. CONTACT FEEDBACK (part 4d, 3c components): the drill's grind on
##     a met figure and its bore opening ground pop the shared 3c hit
##     star in the jackhammer's steel-spark palette (throttled); the
##     saw throw pops its spark muzzle burst in the saw's palette, and
##     the spinning blade's grind streams throttled stars in the same
##     family (ProjectileBody.SAW_SPARK mirrors the registry).
##
## Run headless: godot --headless res://tests/test_issue722.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const WeaponVisualsScript := preload("res://scripts/WeaponVisuals.gd")
const BodyScript := preload("res://scripts/ProjectileBody.gd")

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


## Stand-in wielder (the #363 recipe): a REAL-SIZE figure whose
## _physics_process keeps the drill velocity while the drill runs and
## clamps to the idle along-gravity component otherwise; aim_dir
## answers the live view angle.
const WielderScript := "
extends CharacterBody2D
var view_angle := 0.0
var steer := 0.0
func aim_dir(f: float, d: float) -> Vector2:
	return Vector2(cos(view_angle) * f, -sin(view_angle) * d)
func current_gravity() -> Vector2:
	return Vector2.DOWN
func walk_command() -> float:
	return 0.0
func _physics_process(delta: float) -> void:
	var weapon := get_node_or_null(\"Weapon\")
	if weapon != null and weapon.has_method(\"is_drilling\") and weapon.is_drilling():
		view_angle = clampf(view_angle + steer * delta, -1.2, 1.2)
	else:
		velocity = Vector2(0.0, velocity.y)
	move_and_slide()
"


## Plain stand-in victim (no physics): records take_damage calls, so
## the ONLY hit stars in the level are the weapon's #722 feedback
## stars.
const NodeVictimScript := "
extends Node2D
var health := 50
var hits := 0
func take_damage(amount: int) -> void:
	health -= amount
	hits += 1
"


## A duck-typed destructible chunk: records apply_blast carves.
const FakeGroundScript := "
extends Node2D
var blasts := 0
func apply_blast(_point: Vector2, _radius: float) -> void:
	blasts += 1
"


## The 3c comic HIT stars currently under a level root (duck-typed:
## only CartoonBlast carries a "mode"; effect helper nodes do not).
func _hit_stars(level: Node2D) -> Array:
	var stars: Array = []
	for child in level.get_children():
		if child.get("mode") != null and child.get("mode") == 1:
			stars.append(child)
	return stars


func _make_wielder(level: Node2D, at: Vector2) -> CharacterBody2D:
	var script := GDScript.new()
	script.source_code = WielderScript
	script.reload()
	var wielder := CharacterBody2D.new()
	wielder.set_script(script)
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.set_script(WeaponScript)
	wielder.add_child(weapon)
	level.add_child(wielder)
	wielder.global_position = at
	return wielder


func _make_victim(level: Node2D, at: Vector2) -> Node2D:
	var script := GDScript.new()
	script.source_code = NodeVictimScript
	script.reload()
	var victim := Node2D.new()
	victim.set_script(script)
	victim.add_to_group("enemy_team")
	level.add_child(victim)
	victim.global_position = at
	return victim


func _make_ground(level: Node2D, at: Vector2) -> Node2D:
	var script := GDScript.new()
	script.source_code = FakeGroundScript
	script.reload()
	var ground := Node2D.new()
	ground.set_script(script)
	ground.add_to_group("destructible_ground")
	level.add_child(ground)
	ground.global_position = at
	return ground


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- 1) Registry data -----------------------------------------------
	var styles: Array = WeaponVisualsScript.STYLES
	_check(styles.size() == 12,
			"the slot order must stay intact — 12 entries (got %s)"
			% styles.size())
	var jack: Dictionary = styles[6]
	var saw: Dictionary = styles[10]
	_check(jack.has("texture") \
				and jack["texture"] == WeaponVisualsScript.JACKHAMMER_TEX,
			"the jackhammer entry must carry the jackhammer sprite")
	_check(saw.has("texture") \
				and saw["texture"] == WeaponVisualsScript.CIRCULAR_SAW_TEX,
			"the circular saw entry must carry the circular saw sprite")
	_check(WeaponVisualsScript.textured(6) \
				and WeaponVisualsScript.textured(10),
			"both contact weapons must render through the sprite path")
	_check(jack["color"] == Color(0.85, 0.85, 0.95, 1),
			"the jackhammer identity color must stay (got %s)" % jack["color"])
	_check(saw["color"] == Color(0.75, 0.78, 0.85, 1),
			"the saw identity color must stay (got %s)" % saw["color"])
	_check((jack["size"] as Vector2) == Vector2(26, 18),
			"the jackhammer size must be 26x18 (got %s)" % jack["size"])
	_check((saw["size"] as Vector2) == Vector2(22, 16),
			"the saw size must be 22x16 (got %s)" % saw["size"])
	for entry in [["jackhammer", jack], ["saw", saw]]:
		var s: Dictionary = entry[1]
		_check((s["size"] as Vector2).x >= 20.0,
				"the %s must stay readable at gameplay scale (got %s)"
				% [entry[0], s["size"]])
		_check((s.get("anchor", 32.0) as float) >= 26.0 \
				and (s.get("anchor", 32.0) as float) <= 34.0,
				"the %s anchor must stay in the #559 band (got %s)"
				% [entry[0], s.get("anchor", 32.0)])
		_check(s.has("lift_keep") and s.has("drop"),
				"the %s must carry the waist-hold tuning" % entry[0])
		var flash: Dictionary = s.get("flash", {})
		_check(flash.has("inner") and flash.has("core"),
				"the %s must carry a 3c feedback palette" % entry[0])
	_check((jack.get("recoil", -1.0) as float) == 0.0,
			"the drill shake IS the jackhammer animation — recoil 0 (got %s)"
			% jack.get("recoil"))
	_check(not saw.has("recoil") \
				and is_equal_approx(WeaponVisualsScript.recoil(10),
						WeaponVisualsScript.DEFAULT_RECOIL),
			"the saw must keep the part-3 default throw kick (got %s)"
			% WeaponVisualsScript.recoil(10))
	_check(WeaponVisualsScript.flash_style(6)["inner"]
				== Color(0.55, 0.65, 0.85, 1),
			"the jackhammer feedback star must read in the steel-spark family")
	_check(WeaponVisualsScript.flash_style(10)["inner"]
				== Color(0.72, 0.78, 0.90, 1),
			"the saw feedback star must read in the steel-spark family")
	_check((WeaponVisualsScript.flash_style(10).get("size", 22.0) as float)
				== 18.0,
			"the saw throw burst must be the small spark size (got %s)"
			% WeaponVisualsScript.flash_style(10).get("size", 22.0))

	# --- 2) Frozen gameplay numbers --------------------------------------
	_check(WeaponScript.JACKHAMMER_MIN_TIME == 1.0
			and WeaponScript.JACKHAMMER_MAX_TIME == 3.0
			and WeaponScript.JACKHAMMER_SPEED == 130.0
			and WeaponScript.JACKHAMMER_RADIUS == 32.0,
			"the drill timing/speed/radius must be frozen by #680")
	_check(WeaponScript.JACKHAMMER_CARVE_STEP == 6.0
			and WeaponScript.JACKHAMMER_STALL_TIME == 0.3
			and WeaponScript.JACKHAMMER_PUSH_DPS == 10.0
			and WeaponScript.JACKHAMMER_REACH == 64.0,
			"the drill carve/push/reach must be frozen by #680")
	_check(WeaponScript.SAW_SPEED == 480.0
			and WeaponScript.SAW_MASS == 0.8,
			"the saw throw physics must be frozen by #680")
	_check(BodyScript.SAW_SPIN_TIME == 3.0
			and BodyScript.SAW_SUCK_RADIUS == 160.0
			and BodyScript.SAW_SUCK_SPEED == 120.0
			and BodyScript.SAW_CUT_RADIUS == 40.0
			and BodyScript.SAW_CUT_DPS == 20.0,
			"the saw spin/suction/grind must be frozen by #680")
	_check(WeaponScript.SHOTS_PER_TURN[5] == 1
			and WeaponScript.SHOTS_PER_TURN[9] == 1,
			"the contact weapons' shots-per-turn budget must stay frozen")
	_check(WeaponScript.DRILL_STAR_INTERVAL == 0.3
			and BodyScript.SAW_STAR_INTERVAL == 0.3,
			"the feedback-star throttles must stay at their tuned values")
	_check(BodyScript.SAW_SPARK["inner"]
				== WeaponVisualsScript.flash_style(10)["inner"]
			and BodyScript.SAW_SPARK["core"]
				== WeaponVisualsScript.flash_style(10)["core"],
			"the thrown saw's grind palette must mirror the registry entry")

	# --- 3) Held weapons --------------------------------------------------
	var level := Node2D.new()
	add_child(level)
	var shooter := Node2D.new() # plain holder: the aim falls back to facing
	level.add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	gun.selected_weapon = 5
	await _settle(2)
	_check(gun._held_style_index() == 6 and gun._held_textured(),
			"the held jackhammer must map to its textured style (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.JACKHAMMER_TEX,
			"the held jackhammer must draw the jackhammer sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held jackhammer sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the jackhammer")
	gun.selected_weapon = 9
	await _settle(2)
	_check(gun._held_style_index() == 10 and gun._held_textured(),
			"the held saw must map to style 10 (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.CIRCULAR_SAW_TEX,
			"the held saw must draw the circular saw sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held saw sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the saw")
	level.queue_free()
	await get_tree().physics_frame

	# --- 4) Contact feedback ----------------------------------------------
	# 4a) The drill grind: a figure met by the drill takes the streamed
	# DPS and a steel-spark star pops where the bit meets them.
	var grind_level := Node2D.new()
	add_child(grind_level)
	var grind_wielder := _make_wielder(grind_level, Vector2(0, 0))
	var grind_gun: Node2D = grind_wielder.get_node("Weapon")
	grind_gun.selected_weapon = 5
	var grind_victim := _make_victim(grind_level, Vector2(60, 0))
	await _settle(2)
	grind_gun._start_jackhammer(1.0)
	await _settle(12)
	_check(grind_victim.get("health") < 50,
			"the drill must keep grinding the met figure (health %s)"
			% grind_victim.get("health"))
	var grind_stars := _hit_stars(grind_level)
	_check(grind_stars.size() >= 1,
			"the drill grind must pop the 3c hit star (got %s)"
			% grind_stars.size())
	if grind_stars.size() >= 1:
		var star := grind_stars[0] as Node2D
		_check((star.get("hit_inner") as Color)
					== WeaponVisualsScript.flash_style(6)["inner"],
				"the grind star must carry the jackhammer palette")
		_check(star.global_position.distance_to(
					grind_victim.global_position) < 35.0,
				"the grind star must sit at the contact point (off %s)"
				% star.global_position.distance_to(
						grind_victim.global_position))
		_check(star.global_position.x < grind_victim.global_position.x,
				"the grind star must sit behind the victim, at the bit")
	grind_level.queue_free()
	await get_tree().physics_frame

	# 4b) The bore: a drill actually opening ground pops the throttled
	# dust star at the fresh bore (no victims — no grind stars mix in).
	var bore_level := Node2D.new()
	add_child(bore_level)
	var bore_wielder := _make_wielder(bore_level, Vector2(0, 0))
	var bore_gun: Node2D = bore_wielder.get_node("Weapon")
	bore_gun.selected_weapon = 5
	var bore_ground := _make_ground(bore_level, Vector2(30, 0))
	await _settle(2)
	bore_gun._start_jackhammer(1.0)
	await _settle(30)
	_check(bore_ground.get("blasts") > 0,
			"the drill must keep carving the destructible ground")
	var bore_stars := _hit_stars(bore_level)
	_check(bore_stars.size() >= 1,
			"the opening bore must pop the 3c dust star (got %s)"
			% bore_stars.size())
	if bore_stars.size() >= 1:
		_check((bore_stars[0].get("hit_inner") as Color)
					== WeaponVisualsScript.flash_style(6)["inner"],
				"the bore star must carry the jackhammer palette")
	bore_level.queue_free()
	await get_tree().physics_frame

	# 4c) The saw: the throw pops the small spark burst in the saw's
	# palette; the spinning blade's grind streams stars in the same
	# family (the suction drags the victim onto the blade).
	var saw_level := Node2D.new()
	add_child(saw_level)
	var saw_shooter := CharacterBody2D.new()
	saw_level.add_child(saw_shooter)
	var saw_gun := Node2D.new()
	saw_gun.set_script(WeaponScript)
	saw_shooter.add_child(saw_gun)
	saw_gun.selected_weapon = 9
	saw_gun._throw_saw(1.0)
	var bursts: Array = []
	for child in saw_level.get_children():
		if child is MuzzleFlash:
			bursts.append(child)
	_check(bursts.size() == 1,
			"the saw throw must pop its muzzle burst (got %s)"
			% bursts.size())
	if bursts.size() == 1:
		_check((bursts[0].get("fill_inner") as Color)
					== WeaponVisualsScript.flash_style(10)["inner"],
				"the throw burst must carry the saw's spark palette")
		_check((bursts[0].get("size") as float) == 18.0,
				"the throw burst must be the small spark size (got %s)"
				% bursts[0].get("size"))
	var saw_body: RigidBody2D = null
	for child in saw_level.get_children():
		if child is RigidBody2D and child.get_script() == BodyScript \
				and child.get("kind") == BodyScript.Kind.SAW:
			saw_body = child
	_check(saw_body != null, "the throw must have spawned the SAW body")
	if saw_body == null:
		_finish()
		return
	saw_body.linear_velocity = Vector2.ZERO
	var saw_victim := _make_victim(saw_level,
			saw_body.global_position + Vector2(80.0, 0.0))
	var spun := false
	for i in 10:
		await get_tree().physics_frame
		if saw_body.is_saw_spinning():
			spun = true
			break
	_check(spun, "a saw at rest must start spinning")
	# Sample every 5 frames for 1.5 s of grinding: a hit star lives only
	# 0.22 s while the grind throttles one per 0.3 s, so a single
	# end-point check could land in the dead gap — sampling catches any
	# live star.
	var saw_star: Node2D = null
	for i in 90:
		await get_tree().physics_frame
		if i % 5 == 0:
			for star in _hit_stars(saw_level):
				if (star.get("hit_inner") as Color) \
						== BodyScript.SAW_SPARK["inner"]:
					saw_star = star
	_check(saw_victim.get("health") < 50,
			"the spinning blade must keep grinding the dragged figure (health %s)"
			% saw_victim.get("health"))
	_check(saw_star != null,
			"the saw grind must pop the 3c hit star in the spark palette")
	if saw_star != null and is_instance_valid(saw_body):
		_check(saw_star.global_position.distance_to(
					saw_body.global_position) < 60.0,
				"the grind star must sit at the blade (off %s)"
				% saw_star.global_position.distance_to(
						saw_body.global_position))
	saw_level.queue_free()

	_finish()


func _finish() -> void:
	if failures == 0:
		print("ISSUE722 ok=true (jackhammer & circular saw: registry, frozen gameplay, held sprites, contact feedback)")
	else:
		print("ISSUE722 ok=false failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
