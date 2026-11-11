class_name ProjectileBody
extends RigidBody2D
## Physics-driven explosive projectile (issue #114).
##
## Rockets and grenades are now REAL physical objects — rigid bodies with
## their own mass, inertia, gravity and (for the grenade) bounciness —
## instead of kinematically moved areas. The shotgun keeps its old logic
## (Projectile.gd, issue #49): its rework comes later.
##  ROCKET  — mass 1.0, level gravity (issue #245: the rocket has
##             weight and arcs under the level's gravity, keeping the
##             launch speed the character gave it), explodes on any contact
##  GRENADE — mass 0.6, LEVEL gravity (issue #216: terrain sources or the
##             center-line rule, exactly like the figures), bounces off
##             surfaces, explodes on fuse
##  ROCK    — issue #227: the Rock TOOL. Same mechanism as the grenade
##             (lobbed arc, level gravity, bounce) but it NEVER explodes:
##             on its fuse it crumbles into destructible ground in a disk
##             slightly larger than a grenade blast, keeping clear of every
##             character and never overlapping indestructible ground.
##  MINE    — issue #246: thrown like a grenade, but has NO fuse: it lies
##             dormant (even across turns — it leaves the "projectiles"
##             group once it comes to rest, so the turn handover never
##             waits for it) until some character steps within
##             MINE_TRIGGER (1.2 of the figure width — doubled in issue
##             #262). Then it arms, beeps/blinks for MINE_FUSE seconds
##             and explodes. Issue #312: the moment it arms, the mine is a
##             live turn effect again — it re-joins the "projectiles"
##             group, so the turn handover waits until it has exploded
##             before the next turn begins.
## Visuals are plain rectangles built in code — no assets.

enum Kind { ROCKET, GRENADE, ROCK, MINE }

const BOUNCE := {Kind.ROCKET: 0.0, Kind.GRENADE: 0.45, Kind.ROCK: 0.45, Kind.MINE: 0.2}

## Issue #246: mine parameters. The proximity trigger is 1.2 of a
## character's width (the figure visual is 64 px, like ShapeVisual and
## ROCK_CHAR_CLEAR above) — doubled from the original 0.6 in issue #262;
## once triggered the mine counts MINE_FUSE
## seconds before it explodes. A mine is only "a projectile" while it
## flies: once it slows below MINE_REST_SPEED it is settled — a dormant
## hazard that stays until it explodes, across any number of turns.
const MINE_TRIGGER := 1.2 * 64.0  # issue #262: doubled from 0.6 * 64.0
const MINE_FUSE := 2.0
const MINE_REST_SPEED := 30.0
## Safety net: if a thrown mine never comes to rest (endless slide), it
## still leaves the "projectiles" group after this many seconds so the
## post-shot turn handover can never get stuck waiting for it.
const MINE_SETTLE_WATCHDOG := 4.0
## Issue #281: the mine is destructible — it has exactly ONE hit point,
## so any weapon that damages it destroys it. A damaged mine skips its
## fuse entirely and detonates the instant it is hit.
const MINE_HP := 1

## Issue #227: rock crumble parameters. The created soil disk is a little
## larger than a grenade blast (GRENADE_BLAST = 100 in Weapon.gd); it
## clears every character by 1.3 x the figure shape size (ShapeVisual =
## 64 px) and never overlaps solid terrain — the fill hugs indestructible
## ground with a common border instead of covering it.
const ROCK_GROUND_RADIUS := 110.0
## Issue #324: precision of the crumble disk. The disk is filled with
## horizontal CHORD strips — each row spans the circle's exact half-width
## at the row's centre — so the outline follows the arc. The old 25 px
## cell grid kept whole cells by their centre and left a chunky staircase
## that erred by up to ~18 px per axis; rows of 10 px keep every strip
## corner within ~5 px of the true circle.
## Issue #480: rows halved to 4 px — the 10 px staircase read as a rough
## outline at play zoom; 4 px keeps corners within ~2 px, matching the
## 2 px crispness standard the craters set in issue #299.
const ROCK_ROW := 4.0
const ROCK_CHAR_CLEAR := 1.3 * 64.0
## Issue #216: grenade acceleration matches the figures (Stats.GRAVITY).
const Stats := preload("res://scripts/CharacterStats.gd")
const GRAVITY := Stats.GRAVITY

## Issue #475 (godot-sound-work skill): the blast/crumble sounds —
## preloaded once, never loaded per blast at runtime. The rocket keeps
## its current silent blast (not part of the issue's scope).
const GRENADE_SOUND := preload("res://assets/audio/explosions/grenade.wav")
const MINE_SOUND := preload("res://assets/audio/explosions/mine.wav")
const ROCK_SOUND := preload("res://assets/audio/tools/rock_crumble.wav")
## One AudioStreamPlayer per projectile, on the SFX bus (the kind is
## known at _ready, so the stream is picked once there) — each blast
## owns its player so simultaneous explosions never cut each other short.
var _blast_player: AudioStreamPlayer
## Issue #293: no gravity context is captured from the wielder anymore —
## gravity is sampled every step from the level's indestructible grounds
## (the same terrain rule the figures follow).

var kind: int = Kind.ROCKET
## Launch velocity applied once the body enters the tree.
var launch_velocity := Vector2.ZERO
var damage := 30
var blast_radius := 0.0
var lifetime := 3.0
## Issue #57: the character that fired us — we pass through it.
var shooter: Node2D = null
var _size := Vector2(16, 8)
var _color := Color.WHITE
var _mass := 1.0
var _exploded := false
## Issue #246: mine state — flying → settled (dormant) → armed (fuse) →
## boom. _visual is kept so the armed fuse can blink the body red.
var _settled := false
var _armed := false
var _fuse_left := 0.0
## Issue #281: current mine health (MINE_HP while intact).
var _hp := 0
var _visual: ColorRect = null
## Issue #368: the armed mine's red warning light (null while dormant).
var _mine_light: ShotLight = null


func setup(p_kind: int, p_velocity: Vector2, p_damage: int, p_lifetime: float,
		p_size: Vector2, p_color: Color, p_blast_radius: float = 0.0,
		p_mass: float = 1.0) -> void:
	kind = p_kind
	launch_velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	_size = p_size
	_color = p_color
	blast_radius = p_blast_radius
	_mass = p_mass


func _ready() -> void:
	# Issue #119: register with TurnController so the turn handover waits
	# until every projectile has exploded/been freed.
	add_to_group("projectiles")
	# Layer 4 = projectiles; hit the world, both teams, and walls. Issue
	# #281: the ROCKET also sees layer-4 mines so a direct hit detonates
	# on contact instead of flying through them.
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	if kind == Kind.ROCKET:
		collision_mask |= 4
	mass = _mass
	# Issue #216: engine gravity is always OFF for projectiles — every
	# kind gets the LEVEL's gravity in _integrate_forces instead
	# (issue #245: the rocket too — it has weight now).
	gravity_scale = 0.0
	var mat := PhysicsMaterial.new()
	mat.bounce = BOUNCE[kind]
	physics_material_override = mat
	linear_velocity = launch_velocity
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size
	shape.shape = rect
	add_child(shape)

	var visual := ColorRect.new()
	visual.offset_left = -_size.x / 2.0
	visual.offset_top = -_size.y / 2.0
	visual.offset_right = _size.x / 2.0
	visual.offset_bottom = _size.y / 2.0
	visual.color = _color
	add_child(visual)
	_visual = visual

	# Issue #368: lighting effect — the rocket's exhaust flickers bright
	# orange, the grenade glows green; the thrown mine stays dark until
	# its fuse arms (see _physics_process), the rock is a plain clod.
	match kind:
		Kind.ROCKET:
			add_child(ShotLight.create(
				Color(1.0, 0.55, 0.2), 150.0, 2.4, true, 0.3))
		Kind.GRENADE:
			add_child(ShotLight.create(
				Color(0.4, 0.9, 0.4), 90.0, 1.6))

	# Issue #246: the mine has NO fuse timer — it only explodes after a
	# character stepped near it. While it flies it counts as a live
	# projectile (turn handover waits, issue #119); the watchdog makes sure
	# it leaves that group even if it never comes to rest.
	if kind == Kind.MINE:
		# Issue #281: mines are damageable targets — explosions and pellets
		# find them through the "mines" group.
		_hp = MINE_HP
		add_to_group("mines")
		get_tree().create_timer(MINE_SETTLE_WATCHDOG).timeout.connect(_on_mine_watchdog)
	else:
		get_tree().create_timer(lifetime).timeout.connect(_on_fuse)

	# Issue #475: blast SFX player on the SFX bus (default 0 dB; fixed
	# 1.0 pitch — blasts are one-per-projectile, so the rapid-fire pitch
	# variation the sound skill allows does not apply).
	_blast_player = AudioStreamPlayer.new()
	match kind:
		Kind.GRENADE:
			_blast_player.stream = GRENADE_SOUND
		Kind.MINE:
			_blast_player.stream = MINE_SOUND
		Kind.ROCK:
			_blast_player.stream = ROCK_SOUND
	_blast_player.bus = "SFX"
	add_child(_blast_player)


func _physics_process(delta: float) -> void:
	# Issue #246: the mine's state machine. Everything else is physics
	# handled by the engine plus the level gravity in _integrate_forces.
	if kind != Kind.MINE:
		return
	if not _settled:
		if linear_velocity.length() < MINE_REST_SPEED:
			_settle()
		return
	if not _armed:
		# Dormant: arm the fuse the moment ANY character (either team,
		# including the thrower) steps into the trigger radius.
		for group in ["player_team", "enemy_team"]:
			for node in get_tree().get_nodes_in_group(group):
				var body := node as Node2D
				if body != null and is_instance_valid(body) \
						and body.global_position.distance_to(global_position) \
						<= MINE_TRIGGER:
					_armed = true
					_fuse_left = MINE_FUSE
					# Issue #312: an armed mine is a pending turn effect — re-join
					# the "projectiles" group so the turn handover waits for the
					# explosion before the next turn begins (it left the group
					# when it settled, issue #246).
					add_to_group("projectiles")
					# Issue #368: the armed fuse emits a red warning light.
					_mine_light = ShotLight.create(
						Color(1.0, 0.2, 0.1), 80.0, 1.2)
					add_child(_mine_light)
					return
	else:
		# Armed: blink red while the fuse counts down, then explode.
		_fuse_left -= delta
		if _visual != null:
				_visual.color = Color(1.0, 0.15, 0.1, 1) \
					if fmod(_fuse_left, 0.25) < 0.125 else _color
		if _mine_light != null and is_instance_valid(_mine_light):
				_mine_light.energy = 2.2 \
					if fmod(_fuse_left, 0.25) < 0.125 else 0.5
		if _fuse_left <= 0.0:
				_explode()


## Issue #246: the mine came to rest — it stops being a live projectile
## the turn handover waits for (issue #119) and lies dormant until someone
## steps on it, however many turns that takes. Arming reverses this:
## the triggered mine re-joins "projectiles" (issue #312) until it
## explodes.
func _settle() -> void:
	_settled = true
	remove_from_group("projectiles")


## Issue #246: settle watchdog — a mine that never slows down (endless
## slide) still leaves the "projectiles" group so a turn never waits on it.
func _on_mine_watchdog() -> void:
	if kind == Kind.MINE and not _settled and not _exploded:
		_settle()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Issue #216: the grenade (and the rock, issue #227) obeys the level's
	# gravity — terrain sources first, then the center-line rule, then the
	# static direction — the same ladder the figures use (Player.gd / Npc.gd).
	# Issue #245: the rocket has weight too — it keeps the launch speed the
	# character gave it (set in _ready) while this gravity bends its path.
	state.linear_velocity += _level_gravity() * GRAVITY * state.step


## Unit gravity direction at the grenade's position (issue #216).
## Issue #293: the level's indestructible grounds are the ONLY gravity
## source — the same terrain rule the figures follow; the wielder's old
## central-line/gravity_dir context is gone. Straight down without any
## gravity source.
func _level_gravity() -> Vector2:
	if LevelTerrain.has_sources(self):
		return LevelTerrain.gravity_vector(self)
	return Vector2.DOWN


func _on_body_entered(body: Node2D) -> void:
	# Issue #57: never interact with the character that fired us.
	if body == shooter:
		return
	# Issue #246: the mine ignores contact — it only wakes through its
	# proximity trigger in _physics_process.
	if kind == Kind.ROCKET:
		_explode()


func _on_fuse() -> void:
	_explode()


## Issue #281: the mine is destructible — MINE_HP (1) means a single hit
## from ANY weapon destroys it, and a damaged mine explodes IMMEDIATELY:
## no fuse, no arming delay.
func take_damage(amount: int) -> void:
	if kind != Kind.MINE or _exploded or amount <= 0:
		return
	_hp -= amount
	if _hp <= 0:
		_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	# Issue #475: every detonation/crumble is audible from here — the
	# sound starts before the ground carving, damage and chain reactions
	# below run while it plays.
	_play_blast_sound()
	# Issue #227: the rock never explodes — its "fuse moment" crumbles it
	# into destructible ground instead (no damage, no blast).
	if kind == Kind.ROCK:
		_create_ground()
		_spawn_blast_visual(Color(0.45, 0.32, 0.2), Color(0.55, 0.42, 0.28))
		queue_free()
		return
	# Issue #190 (rework #225): rockets and grenades carve destructible
	# terrain in the blast radius. The carve used to live only in the legacy
	# Projectile, so physics projectiles detonated on soil without
	# destroying any ground.
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
			# Issue #335: pass the shooter so the victim can tell friend
			# from foe when it reacts with a comics line.
			body.take_damage(damage, shooter)
	# Issue #281: the blast also hits other mines — each has 1 HP, so any
	# damage inside the radius detonates it instantly (chain reactions
	# included). Self is guarded by take_damage's _exploded check.
	for node in get_tree().get_nodes_in_group("mines"):
		var mine := node as ProjectileBody
		if mine == null or mine == self or not is_instance_valid(mine):
			continue
		if mine.global_position.distance_to(global_position) <= blast_radius:
			mine.take_damage(damage)
	# Issue #364: level items share the 1-HP destructible rule — the
	# blast detonates them too (chain reactions included).
	for node in get_tree().get_nodes_in_group("level_items"):
		var item := node as LevelItem
		if item == null or not is_instance_valid(item):
			continue
		if item.global_position.distance_to(global_position) <= blast_radius:
			item.take_damage(damage)
	# Issue #368: the explosion flashes a big fading light.
	if get_parent() != null:
		ShotLight.flash(get_parent(), global_position,
			Color(1.0, 0.8, 0.4), maxf(blast_radius, 60.0) * 1.6, 3.0, 0.4)
	_spawn_blast_visual()
	queue_free()


## Issue #475 (godot-sound-work skill): play this projectile's blast
## sound. The body itself is queue_free()d at the end of _explode(), so
## the player is re-homed to the level FIRST — otherwise it would be
## freed with the body and the sound would be cut to a single frame.
## Afterwards the player frees itself when the stream finishes.
func _play_blast_sound() -> void:
	if _blast_player == null or _blast_player.stream == null:
		return
	if get_parent() != null:
		_blast_player.reparent(get_parent())
		_blast_player.finished.connect(_blast_player.queue_free)
	_blast_player.play()

## Issue #227: the rock's "explosion" — a disk of destructible ground
## around the resting point. Issue #324 rework: the disk is filled row by
## row with CHORD strips — each row spans the circle's true half-width at
## the row's centre, minus the x-ranges the exclusions bite out of that
## row. A strip therefore always
##  - lies inside ROCK_GROUND_RADIUS of the impact point (at the row's
##    centre a strip ends exactly ON the circle),
##  - clears every character by ROCK_CHAR_CLEAR (1.3 x the figure's shape
##    size) — ground is created AROUND a figure, never on it, and
##  - never overlaps indestructible ground (slab or disc) or existing
##    soil — it borders them instead of covering them.
## Issue #480: polygon and ring-sector soil is banned by its ACTUAL
## outline, clipped per row — the old AABB ban covered empty air beside
## the dome/trapezoid hills and left an unfilled rectangle inside the
## disk wherever it touched a hill's bounding box.
func _create_ground() -> void:
	var parent := get_parent()
	if parent == null:
		return
	# All exclusions are collected in the IMPACT POINT's local space
	# (row bands and chords below are relative to global_position).
	var origin := global_position
	# Characters (both teams): a clearance circle to keep out of.
	var circles: Array[Vector3] = []
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body != null and is_instance_valid(body):
				circles.append(Vector3(body.global_position.x - origin.x,
						body.global_position.y - origin.y, ROCK_CHAR_CLEAR))
	# Solid terrain the new soil must never overlap: indestructible
	# ground stays axis-exact (slab rects / clearance discs), while
	# existing destructible soil contributes its true OUTLINE polygon
	# (issue #480 — the AABB of a dome or trapezoid hill is a rectangle
	# of thin air beside the hill; banning it punched a rectangular hole
	# into the disk).
	var solids: Array[Rect2] = []
	var discs: Array[Vector3] = []
	var soils: Array[PackedVector2Array] = []
	for node in get_tree().get_nodes_in_group("indestructible_ground"):
		var ground := node as IndestructibleGround
		if ground == null or not is_instance_valid(ground):
			continue
		if ground.radius > 0.0:
			discs.append(Vector3(ground.position.x - origin.x,
						ground.position.y - origin.y, ground.radius))
		else:
			solids.append(Rect2(ground.position - ground.rect_size / 2.0
						- origin, ground.rect_size))
	for node in get_tree().get_nodes_in_group("destructible_ground"):
		var soil := node as DestructibleGround
		if soil == null or not is_instance_valid(soil):
			continue
		var outline := PackedVector2Array()
		for p in soil.local_outline():
			outline.append(p + soil.position - origin)
		soils.append(outline)
	# Row by row: the true chord of the disk minus the x-intervals the
	# exclusions ban from that row — one exact strip per remaining span.
	var rows := int(ceilf(ROCK_GROUND_RADIUS / ROCK_ROW))
	for iy in range(-rows, rows):
		var y0 := iy * ROCK_ROW
		var y1 := y0 + ROCK_ROW
		var cy := y0 + ROCK_ROW / 2.0
		var half := sqrt(maxf(0.0,
				ROCK_GROUND_RADIUS * ROCK_GROUND_RADIUS - cy * cy))
		if half <= 0.0:
			continue
		# X-intervals this row must not touch.
		var bans: Array = []
		for solid in solids:
			# Bordering is fine (strict test, like Rect2.intersects): a
			# slab sharing only the row's edge bans nothing.
			if solid.position.y < y1 and solid.end.y > y0:
				bans.append([solid.position.x, solid.end.x])
		for circle in circles:
			_ban_from_circle(circle, y0, y1, bans)
		for disc in discs:
			_ban_from_circle(disc, y0, y1, bans)
		for outline in soils:
			var span := _band_x_span(outline, y0, y1)
			if not is_nan(span.x) and not is_nan(span.y):
				bans.append([span.x, span.y])
		# Sweep the bans left to right and spawn the gaps that remain.
		bans.sort_custom(func(a, b): return a[0] < b[0])
		var cursor := -half
		for ban in bans:
			if ban[0] > cursor:
				_spawn_soil_strip(parent, cursor, minf(ban[0], half), y0)
			cursor = maxf(cursor, ban[1])
			if cursor >= half:
				break
		if cursor < half:
			_spawn_soil_strip(parent, cursor, half, y0)


## Add to `bans` the x-interval a keep-out circle bites out of the row band
## [y0, y1] (nothing when the circle never crosses the band). A strip
## outside the interval keeps at least the circle's radius of distance to
## its centre, so bordering the interval is safe.
func _ban_from_circle(circle: Vector3, y0: float, y1: float,
			bans: Array) -> void:
	var dy := clampf(circle.y, y0, y1) - circle.y
	var under := circle.z * circle.z - dy * dy
	if under <= 0.0:
		return
	var half := sqrt(under)
	bans.append([circle.x - half, circle.x + half])


## Issue #480: x-span [min, max] of a soil outline's slice through the
## horizontal band [y0, y1] — the polygon clipped top and bottom, then
## projected on x (the authored hills are convex, so their slice is one
## interval; a concave outline could only err towards banning MORE,
## which stays safe — soil never overlaps soil). Returns NAN when the
## outline never crosses the band.
func _band_x_span(pts: PackedVector2Array, y0: float,
		y1: float) -> Vector2:
	var slice := _clip_y(_clip_y(pts, y0, true), y1, false)
	if slice.size() < 3:
		return Vector2(NAN, NAN)
	var lo := slice[0].x
	var hi := slice[0].x
	for p in slice:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return Vector2(lo, hi)


## Sutherland–Hodgman clip of the polygon against one horizontal
## half-plane: keep the part with y >= t (`keep_above`) or y <= t.
func _clip_y(pts: PackedVector2Array, t: float,
		keep_above: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var cur := pts[i]
		var nxt := pts[(i + 1) % n]
		var cur_in := (cur.y >= t) if keep_above else (cur.y <= t)
		var nxt_in := (nxt.y >= t) if keep_above else (nxt.y <= t)
		if cur_in:
			out.append(cur)
		if cur_in != nxt_in:
			var f := (t - cur.y) / (nxt.y - cur.y)
			out.append(Vector2(cur.x + (nxt.x - cur.x) * f, t))
	return out


## One exact soil strip on the row starting at `y0`: x from `x0` to `x1`,
## spawned as a single DestructibleGround chunk (issue #324: strips span
## the true chord instead of merged 25 px cells).
func _spawn_soil_strip(parent: Node, x0: float, x1: float, y0: float) -> void:
	var size := Vector2(x1 - x0, ROCK_ROW)
	if size.x < DestructibleGround.MIN_PIECE or size.y < DestructibleGround.MIN_PIECE:
		return
	var piece := DestructibleGround.new()
	piece.rect_size = size
	piece.position = global_position + Vector2(
			(x0 + x1) / 2.0, y0 + ROCK_ROW / 2.0)
	parent.add_child(piece)


## Issue #150: brief expanding ring showing the blast radius at the
## moment of explosion. Drawn in code — no assets. Issue #227: the ring
## colors are parametric so the rock crumble can flash brown.
func _spawn_blast_visual(ring_color := Color(1.0, 0.8, 0.3),
		fill_color := Color(1.0, 0.6, 0.2)) -> void:
	if blast_radius <= 0.0:
		return
	var ring := BlastRing.new()
	ring.radius = blast_radius
	ring.ring_color = ring_color
	ring.fill_color = fill_color
	ring.position = global_position
	ring.z_index = 50
	# Issue #244: the fading ring is a live explosion EFFECT — the turn
	# handover waits until it is done before the next turn begins.
	ring.add_to_group("turn_effects")
	get_parent().add_child(ring)


class BlastRing:
	extends Node2D

	const LIFETIME := 0.4

	var radius := 100.0
	var ring_color := Color(1.0, 0.8, 0.3)
	var fill_color := Color(1.0, 0.6, 0.2)
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := _age / LIFETIME
		var alpha := 1.0 - t
		var r := radius * (0.6 + 0.4 * t)
		# Filled flash fading out fast.
		draw_circle(Vector2.ZERO, r, Color(fill_color, 0.35 * alpha))
		# Bright expanding outline.
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48,
				Color(ring_color, alpha), 3.0, true)
