extends Node
## Regression check for issue #721 (Weapon Visual Redesign 4c — spear,
## baseball bat & entrenching shovel cartoon sprites, sub-issue of the
## #680 roadmap).
##
##  1. REGISTRY DATA: the three melee entries in WeaponVisuals STYLES
##     are textured (own sprite, readable size, waist-hold
##     lift/drop, ZERO recoil — the lunge/swing IS the animation) with
##     their identity colors kept and 3c hit-star palettes; the spear's
##     size.x stays EXACTLY 40 — the sweep hitbox reads
##     HELD_STYLES[3]["size"].x — and the spear keeps the #559 default
##     anchor (SPEAR_TIP_BASE's hitbox contract); the slot order (12
##     entries) is intact.
##  2. FROZEN GAMEPLAY: every melee constant the #680 constraints
##     freeze — ranges, damage, tip base, lateral tolerance, shots per
##     turn — is pinned to its pre-#721 value.
##  3. HELD WEAPONS: the spear (weapon 3), the bat (weapon 8) and the
##     shovel (weapon 10) render through the _held_sprite with the
##     registry textures at the registry sizes, and the plain
##     ColorRect path is off for them.
##  4. MELEE HIT FEEDBACK (part 4c): a strike that damages a figure
##     pops the shared 3c comic hit star (CartoonBlast, HIT mode) at
##     the contact point in the weapon's own palette — for the spear
##     thrust, the bat swing and the shovel swing; a shovel swing into
##     bare air (no figures, no destructible ground) stays silent; a
##     dig that DOES open ground pops exactly one earthy star.
##
## Run headless: godot --headless res://tests/test_issue721.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const WeaponVisualsScript := preload("res://scripts/WeaponVisuals.gd")

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


## A damage-taking figure for the melee corridors: integer health,
## take_damage like Character, no visuals of its own (so the ONLY hit
## star in the level is the weapon's #721 strike star).
class Victim:
	extends CharacterBody2D
	var health := 50
	func take_damage(amount: int, _attacker: Node = null) -> void:
		health -= amount


## A duck-typed destructible chunk: records the dig carve.
class FakeGround:
	extends Node2D
	var dug := false
	func apply_dig(_point: Vector2, _half_w: float, _half_h: float,
			_up: Vector2) -> void:
		dug = true


func _make_level() -> Node2D:
	var level := Node2D.new()
	add_child(level)
	return level


func _make_gun(level: Node2D) -> Node2D:
	var shooter := AimShooter.new()
	level.add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


## The 3c comic HIT stars currently under the level root (duck-typed:
## only CartoonBlast carries a "mode"; the bat's knockback helper node
## and other effects do not).
func _hit_stars(level: Node2D) -> Array:
	var stars: Array = []
	for child in level.get_children():
		if child.get("mode") != null and child.get("mode") == 1:
			stars.append(child)
	return stars


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- 1) Registry data ---------------------------------------------------
	var styles: Array = WeaponVisualsScript.STYLES
	_check(styles.size() == 12,
			"the slot order must stay intact — 12 entries (got %s)"
			% styles.size())
	var spear: Dictionary = styles[3]
	var bat: Dictionary = styles[9]
	var shovel: Dictionary = styles[11]
	_check(spear.has("texture") \
				and spear["texture"] == WeaponVisualsScript.SPEAR_TEX,
			"the spear entry must carry the spear sprite")
	_check(bat.has("texture") \
				and bat["texture"] == WeaponVisualsScript.BASEBALL_BAT_TEX,
			"the bat entry must carry the baseball bat sprite")
	_check(shovel.has("texture") \
				and shovel["texture"] == WeaponVisualsScript.SHOVEL_TEX,
			"the shovel entry must carry the entrenching shovel sprite")
	_check(WeaponVisualsScript.textured(3) \
				and WeaponVisualsScript.textured(9) \
				and WeaponVisualsScript.textured(11),
			"the three melee weapons must render through the sprite path")
	_check(spear["color"] == Color(0.8, 0.8, 0.9, 1),
			"the spear identity color must stay (got %s)" % spear["color"])
	_check(bat["color"] == Color(0.85, 0.6, 0.3, 1),
			"the bat identity color must stay (got %s)" % bat["color"])
	_check(shovel["color"] == Color(0.55, 0.42, 0.28, 1),
			"the shovel identity color must stay (got %s)" % shovel["color"])
	_check((spear["size"] as Vector2) == Vector2(40, 8),
			"the spear size must stay 40x8 — size.x feeds the sweep hitbox"
			+ " (got %s)" % spear["size"])
	_check((spear["size"] as Vector2).x == 40.0,
			"the spear size.x is the frozen #257 hitbox contract (got %s)"
			% (spear["size"] as Vector2).x)
	_check(not spear.has("anchor") \
				or is_equal_approx((spear.get("anchor") as float), 32.0),
			"the spear must keep the #559 default anchor — SPEAR_TIP_BASE"
			+ " ties the hitbox to it (got %s)" % spear.get("anchor"))
	for entry in [["spear", spear, Vector2(40, 8)],
			["bat", bat, Vector2(32, 10)],
			["shovel", shovel, Vector2(26, 12)]]:
		var s: Dictionary = entry[1]
		var want: Vector2 = entry[2]
		_check((s["size"] as Vector2) == want,
				"the %s style size must be %s (got %s)"
				% [entry[0], want, s["size"]])
		_check((s["size"] as Vector2).x >= 20.0,
				"the %s must stay readable at gameplay scale (got %s)"
				% [entry[0], s["size"]])
		_check((s.get("anchor", 32.0) as float) >= 26.0 \
				and (s.get("anchor", 32.0) as float) <= 34.0,
				"the %s anchor must stay in the #559 band (got %s)"
				% [entry[0], s.get("anchor", 32.0)])
		_check(s.has("lift_keep") and s.has("drop"),
				"the %s must carry the waist-hold tuning" % entry[0])
		_check((s.get("recoil", -1.0) as float) == 0.0,
				"the %s lunge/swing IS the animation — recoil 0 (got %s)"
				% [entry[0], s.get("recoil")])
		var flash: Dictionary = s.get("flash", {})
		_check(flash.has("inner") and flash.has("core"),
				"the %s must carry a 3c hit-star palette" % entry[0])
	# The melee palettes are the registry's flash data — pop_hit reads
	# "inner"/"core" from exactly this route.
	_check(WeaponVisualsScript.flash_style(3)["inner"]
				== Color(0.55, 0.68, 0.95, 1),
			"the spear hit star must read in the steel family")
	_check(WeaponVisualsScript.flash_style(9)["inner"]
				== Color(1.0, 0.55, 0.15, 1),
			"the bat hit star must read in the warm wood family")
	_check(WeaponVisualsScript.flash_style(11)["inner"]
				== Color(0.72, 0.45, 0.2, 1),
			"the shovel hit star must read in the earthy family")

	# --- 2) Frozen gameplay numbers -----------------------------------------
	_check(WeaponScript.SPEAR_RANGE == 70.0
			and WeaponScript.SPEAR_DAMAGE == 25
			and WeaponScript.SPEAR_TIP_BASE == 26.0,
			"the spear gameplay numbers must be frozen by #680")
	_check(WeaponScript.BAT_RANGE == 90.0
			and WeaponScript.BAT_DAMAGE == 30
			and WeaponScript.BAT_LATERAL == 24.0,
			"the bat gameplay numbers must be frozen by #680")
	_check(WeaponScript.SHOVEL_RANGE == 55.0
			and WeaponScript.SHOVEL_DAMAGE == 5,
			"the shovel gameplay numbers must be frozen by #680")
	_check(WeaponScript.SHOTS_PER_TURN[3] == 2
			and WeaponScript.SHOTS_PER_TURN[8] == 1
			and WeaponScript.SHOTS_PER_TURN[10] == 5,
			"the melee shots-per-turn budget must stay frozen")

	# --- 3) Held weapons ------------------------------------------------------
	var level := _make_level()
	var gun := _make_gun(level)
	gun.selected_weapon = 3
	await _settle(2)
	_check(gun._held_style_index() == 3 and gun._held_textured(),
			"the held spear must map to its textured style (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.SPEAR_TEX,
			"the held spear must draw the spear sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held spear sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the spear")
	gun.selected_weapon = 8
	await _settle(2)
	_check(gun._held_style_index() == 9 and gun._held_textured(),
			"the held bat must map to style 9 (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.BASEBALL_BAT_TEX,
			"the held bat must draw the baseball bat sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held bat sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the bat")
	gun.selected_weapon = 10
	await _settle(2)
	_check(gun._held_style_index() == 11 and gun._held_textured(),
			"the held shovel must map to style 11 (got %s)"
			% gun._held_style_index())
	_check(gun._held_sprite.texture == WeaponVisualsScript.SHOVEL_TEX,
			"the held shovel must draw the entrenching shovel sprite")
	_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
			"the held shovel sprite must draw at the registry size (got %s)"
			% gun._held_sprite.scale)
	_check(not gun._held.visible,
			"the plain ColorRect path must be off for the shovel")

	# --- 4) Melee hit feedback ------------------------------------------------
	# Spear: the thrust sweep damages the figure and pops the steel
	# star AT the contact point (the victim's own warm star would come
	# from Character.take_damage; the test victim has none).
	var spear_victim := Victim.new()
	spear_victim.add_to_group("player_team")
	level.add_child(spear_victim)
	spear_victim.global_position = gun.global_position + Vector2(40, 0)
	gun.selected_weapon = 3
	await _settle(2)
	gun._thrust_spear()
	await _settle(4)
	_check(spear_victim.health == 50 - WeaponScript.SPEAR_DAMAGE,
			"the spear sweep must damage the figure once (health %s)"
			% spear_victim.health)
	var stars := _hit_stars(level)
	_check(stars.size() == 1,
			"the spear strike must pop exactly one hit star (got %s)"
			% stars.size())
	if stars.size() == 1:
		_check((stars[0] as Node2D).global_position.distance_to(
					spear_victim.global_position) < 1.0,
				"the spear star must sit at the contact point (off %s)"
				% (stars[0] as Node2D).global_position.distance_to(
					spear_victim.global_position))
		_check((stars[0].get("hit_inner") as Color)
					== WeaponVisualsScript.flash_style(3)["inner"],
				"the spear star must carry the spear palette")
	await get_tree().create_timer(0.7).timeout
	spear_victim.queue_free()

	# Bat: the corridor hit pops the warm star where the barrel met the
	# victim, and the knockback record still launches (the effect node
	# is not a star).
	var bat_victim := Victim.new()
	bat_victim.add_to_group("enemy_team")
	level.add_child(bat_victim)
	bat_victim.global_position = gun.global_position + Vector2(45, 0)
	gun.selected_weapon = 8
	await _settle(2)
	gun._swing_bat(1.0)
	await _settle(3)
	_check(bat_victim.health == 50 - WeaponScript.BAT_DAMAGE,
			"the bat swing must damage the figure (health %s)"
			% bat_victim.health)
	stars = _hit_stars(level)
	_check(stars.size() == 1,
			"the bat strike must pop exactly one hit star (got %s)"
			% stars.size())
	if stars.size() == 1:
		_check((stars[0].get("hit_inner") as Color)
					== WeaponVisualsScript.flash_style(9)["inner"],
				"the bat star must carry the bat palette")
	bat_victim.queue_free()
	# The bat star lives 0.22 s — let it die before the silent-swing
	# phase counts stars in this level.
	await get_tree().create_timer(0.35).timeout

	# Shovel into bare air: no figures, no destructible ground — the
	# strike star stays silent (the dig pop only fires on a real carve).
	gun.selected_weapon = 10
	await _settle(2)
	gun._swing_shovel()
	await _settle(3)
	stars = _hit_stars(level)
	_check(stars.is_empty(),
			"a shovel swing into bare air must pop nothing (got %s)"
			% stars.size())

	# Shovel with a victim AND ground: on a FRESH gun/level (the dig
	# runs once per stance — the bare-air swing above already spent this
	# gun's carve), so the strike star pops at the contact point and the
	# carve pops its own earthy star exactly once.
	var level2 := _make_level()
	var gun2 := _make_gun(level2)
	gun2.selected_weapon = 10
	await _settle(2)
	var dig_victim := Victim.new()
	dig_victim.add_to_group("player_team")
	level2.add_child(dig_victim)
	dig_victim.global_position = gun2.global_position + Vector2(40, 0)
	var ground := FakeGround.new()
	ground.add_to_group("destructible_ground")
	level2.add_child(ground)
	gun2._swing_shovel()
	await _settle(3)
	_check(dig_victim.health == 50 - WeaponScript.SHOVEL_DAMAGE,
			"the shovel swing must damage the figure (health %s)"
			% dig_victim.health)
	_check(ground.dug, "the shovel swing must still carve the ground")
	stars = _hit_stars(level2)
	_check(stars.size() == 2,
			"the strike and the carve must pop exactly two stars (got %s)"
			% stars.size())
	if stars.size() == 2:
		var palettes := [(stars[0].get("hit_inner") as Color),
			(stars[1].get("hit_inner") as Color)]
		_check(WeaponVisualsScript.flash_style(11)["inner"] in palettes,
				"the shovel stars must carry the shovel palette")
	dig_victim.queue_free()
	ground.queue_free()
	gun2.get_parent().queue_free()
	level2.queue_free()
	gun.get_parent().queue_free()
	level.queue_free()
	await _settle(2)

	if failures > 0:
		push_error("issue #721 test: %d check(s) failed" % failures)
		get_tree().quit(1)
		return
	print("issue #721 test: all checks passed")
	get_tree().quit(0)
