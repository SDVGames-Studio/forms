class_name Projectile
extends Area2D
## Projectile for the standard weapons (issue #49).
##
## One script covers all ranged weapon types; physics differ per type:
## pellets fly straight and short, the rocket flies fast and explodes on
## impact, the grenade flies in a gravity arc and explodes on a fuse or on
## impact. Visuals are plain rectangles built in code — no assets.

enum Type { PELLET, ROCKET, GRENADE }

var type: int = Type.PELLET
var velocity := Vector2.ZERO
var damage := 10
var blast_radius := 0.0
var lifetime := 2.0
## Issue #57: the character that fired us — we pass through it so a shot
## spawning on top of the shooter never damages (or explodes on) them.
var shooter: Node2D = null
var _size := Vector2(12, 6)
var _color := Color.WHITE

## Owner task 2026-11-11 (godot-sound-work skill): the explosion sound —
## preloaded once, never loaded per blast at runtime.
const EXPLOSION_SOUND := preload("res://assets/audio/explosions/explosion.wav")
## One AudioStreamPlayer per sound category, on the SFX bus. Each
## projectile owns its player so simultaneous blasts never cut each
## other short; it is freed together with the projectile.
var _explosion_player: AudioStreamPlayer
var _exploded := false


func setup(p_type: int, p_velocity: Vector2, p_damage: int, p_lifetime: float, p_size: Vector2, p_color: Color, p_blast_radius: float = 0.0) -> void:
	type = p_type
	velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	_size = p_size
	_color = p_color
	blast_radius = p_blast_radius


func _ready() -> void:
	# Issue #119: register with TurnController so the turn handover waits
	# until every projectile is gone.
	add_to_group("projectiles")
	# Layers 1|2 = world + enemy team; issue #57 adds layer 8 (player team)
	# so shots can also hit the shooter's own teammates — friendly fire.
	# Issue #281: layer 4 (projectiles) so pellets reach the mines — a
	# pellet that hits a mine detonates it instantly via take_damage.
	collision_mask = 1 | 2 | 8 | 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size
	shape.shape = rect
	add_child(shape)

	body_entered.connect(_on_body_entered)

	var visual := ColorRect.new()
	visual.offset_left = -_size.x / 2.0
	visual.offset_top = -_size.y / 2.0
	visual.offset_right = _size.x / 2.0
	visual.offset_bottom = _size.y / 2.0
	visual.color = _color
	add_child(visual)

	# Issue #680 part 3b (#717): the LAUNCH — a pellet leaves the muzzle
	# already turned along its flight and briefly STRETCHED along the
	# velocity (classic motion stretch), easing back to 1:1 over a
	# fraction of a second. Data: ProjectileTrail.STYLES. Visual only —
	# the collision shape, velocity and damage are untouched. The scale
	# is set DIRECTLY at spawn so the very first rendered frame is the
	# stretch peak (a .from() tween can step past it on a slow frame).
	if type == Type.PELLET and velocity.length_squared() > 1.0:
		visual.pivot_offset = _size / 2.0
		visual.rotation = velocity.angle()
		visual.scale = ProjectileTrail.launch_stretch("pellet")
		var tween := visual.create_tween()
		tween.tween_property(visual, "scale", Vector2.ONE,
				ProjectileTrail.launch_stretch_time("pellet"))

	# Issue #368: lighting effect — every shot carries a soft light that
	# travels with it (bigger for the explosive types).
	add_child(ShotLight.create(_color,
		110.0 if type != Type.PELLET else 70.0,
		2.0 if type != Type.PELLET else 1.6))

	get_tree().create_timer(lifetime).timeout.connect(_on_expire)

	# Owner task 2026-11-11: explosion SFX player on the SFX bus
	# (default 0 dB; fixed 1.0 pitch — one blast per projectile).
	_explosion_player = AudioStreamPlayer.new()
	_explosion_player.stream = EXPLOSION_SOUND
	_explosion_player.bus = "SFX"
	add_child(_explosion_player)


func _physics_process(delta: float) -> void:
	if type == Type.GRENADE:
		velocity.y += 1200.0 * delta
	global_position += velocity * delta
	# Issue #274 v2 ("same bug again", 2026-11-26): there is deliberately
	# NO camera-view cull here. The v1 fix kept one but made it camera-
	# aware — and that still freed a pellet the moment it was born or flew
	# outside the CURRENT view: the shared camera starts in the free GLOBAL
	# mode (#617) and the player's pan persists (#212), so figures routinely
	# fire from outside the view (Team2 stages at x ~1880-2060 on Level2
	# while the GLOBAL view ends at x ~576), and a zoomed-in or panned view
	# cuts a pellet's 450 px flight mid-air. Result: shot counted, pellets
	# gone with no hit anywhere — the exact #274 symptom. Projectiles are
	# NOT view objects: they die on their own lifetime fuse (_on_expire),
	# on a body hit (_on_body_entered) or on detonation, wherever the
	# camera happens to look.


func _on_expire() -> void:
	if type == Type.GRENADE:
		_explode()
	else:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Issue #57: never interact with the character that fired us.
	if body == shooter:
		return
	if blast_radius > 0.0:
		_explode()
		return
	if body.has_method("take_damage"):
		# Issue #335: pass the shooter so the victim can tell friend from
		# foe when it reacts with a comics line.
		body.take_damage(damage, shooter)
		# Issue #536: a small hit spark where the bullet LANDS. A pellet
		# that stops on a figure — a teammate standing in the line of fire
		# ~100 px ahead, or an enemy — died completely silently: the shot's
		# sound and muzzle flash played, the bullet vanished with no impact,
		# and it looked like the pistol/shotgun never fired. The spark marks
		# the impact point the same way the muzzle flash marks the launch
		# (the rocket/grenade already show themselves via _explode).
		if get_parent() != null:
			ShotLight.flash(get_parent(), global_position,
					Color(1.0, 0.92, 0.55), 44.0, 2.2, 0.16)
	queue_free()


## Owner task 2026-11-11 (godot-sound-work skill): play the explosion
## sound. Fixed 1.0 pitch — blasts are one-per-projectile, so the
## rapid-fire pitch variation the skill allows does not apply.
func _play_explosion_sound() -> void:
	if _explosion_player == null or _explosion_player.stream == null:
		return
	# Issue #686 (same re-homing ProjectileBody._play_blast_sound got
	# in #475): the detonation is deferred, so the sound can start one
	# step before the body's queue_free() — re-home the player to the
	# level first or the sound is cut to a single frame.
	if get_parent() != null:
		_explosion_player.reparent(get_parent())
		_explosion_player.finished.connect(_explosion_player.queue_free)
	_explosion_player.play()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	# Issue #686: contact detonation fires inside the physics callback
	# (body_entered, while the space is still flushing queries); carving
	# ground there adds collision shapes mid-flush, which Godot rejects
	# with "Can't change this state while flushing queries". The real
	# detonation runs one deferred step later, outside the flush.
	_explode_now.call_deferred()


func _explode_now() -> void:
	# Owner task 2026-11-11: the explosion sound plays from the real
	# blast entry path — ground carving, area damage and chain reactions
	# all happen below while the sound runs.
	_play_explosion_sound()
	# Issue #190: explosions carve destructible terrain in the blast radius.
	for ground in get_tree().get_nodes_in_group("destructible_ground"):
		ground.apply_blast(global_position, blast_radius)
	# Area damage to everything with health inside the blast radius.
	var targets: Array = []
	targets.append_array(get_tree().get_nodes_in_group("player_team"))
	targets.append_array(get_tree().get_nodes_in_group("enemy_team"))
	for node in targets:
		var body := node as Node2D
		if body and body.has_method("take_damage") \
				and body.global_position.distance_to(global_position) <= blast_radius:
			# Issue #335: pass the shooter (comics lines, friend vs foe).
			body.take_damage(damage, shooter)
	# Issue #281: the blast also destroys mines within the radius — each
	# has 1 HP and detonates instantly when damaged.
	for node in get_tree().get_nodes_in_group("mines"):
		var mine := node as ProjectileBody
		if mine != null and is_instance_valid(mine) \
				and mine.global_position.distance_to(global_position) <= blast_radius:
			mine.take_damage(damage)
	# Issue #364: level items share the 1-HP destructible rule — the
	# blast detonates them too (chain reactions included).
	for node in get_tree().get_nodes_in_group("level_items"):
		var item := node as LevelItem
		if item != null and is_instance_valid(item) \
				and item.global_position.distance_to(global_position) <= blast_radius:
			item.take_damage(damage)
	# Issue #368: the explosion flashes a big fading light.
	if blast_radius > 0.0 and get_parent() != null:
		ShotLight.flash(get_parent(), global_position,
			Color(1.0, 0.8, 0.4), blast_radius * 1.6, 3.0, 0.4)
		# Issue #718 (roadmap part 3c): the cartoon fireball layered on
		# top of the glow — bold outlines and flat vivid fills in the
		# weapon-art language, peak radius below the blast radius so the
		# gameplay information around the blast stays readable.
		CartoonBlast.pop(get_parent(), global_position, blast_radius)
	queue_free()
