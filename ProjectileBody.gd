class_name ProjectileBody
extends RigidBody2D
## Physics-driven explosive projectile (issue #114).
##
## Rockets and grenades are now REAL physical objects — rigid bodies with
## their own mass, inertia, gravity and (for the grenade) bounciness —
## instead of kinematically moved areas. The shotgun keeps its old logic
## (Projectile.gd, issue #49): its rework comes later.
##  ROCKET  — mass 1.0, no gravity, explodes on any contact
##  GRENADE — mass 0.6, LEVEL gravity (issue #216: terrain sources or the
##             center-line rule, exactly like the figures), bounces off
##             surfaces, explodes on fuse
##  ROCK    — issue #227: the Rock TOOL. Same mechanism as the grenade
##             (lobbed arc, level gravity, bounce) but it NEVER explodes:
##             on its fuse it crumbles into destructible ground in a disk
##             slightly larger than a grenade blast, keeping clear of every
##             character and never overlapping indestructible ground.
## Visuals are plain rectangles built in code — no assets.

enum Kind { ROCKET, GRENADE, ROCK }

const BOUNCE := {Kind.ROCKET: 0.0, Kind.GRENADE: 0.45, Kind.ROCK: 0.45}

## Issue #227: rock crumble parameters. The created soil disk is a little
## larger than a grenade blast (GRENADE_BLAST = 100 in Weapon.gd); cells of
## a 25 px grid are kept only when their rect stays inside the disk, clears
## every character by 1.3 x the figure shape size (ShapeVisual = 64 px) and
## does not overlap solid terrain — so the fill hugs indestructible ground
## with a common border instead of covering it.
const ROCK_GROUND_RADIUS := 110.0
const ROCK_CELL := 25.0
const ROCK_CHAR_CLEAR := 1.3 * 64.0
## Issue #216: grenade acceleration matches the figures (Stats.GRAVITY).
const Stats := preload("res://scripts/CharacterStats.gd")
const GRAVITY := Stats.GRAVITY
## Issue #216: gravity context captured from the wielder — the center line
## height and the static gravity direction of levels without terrain sources.
var _center_line_y := 0.0
var _shoot_gravity_dir := 1.0

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
	# Layer 4 = projectiles; hit the world, both teams, and walls.
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	mass = _mass
	# Issue #216: engine gravity is always OFF for projectiles — the grenade
	# gets the LEVEL's gravity in _integrate_forces instead (the rocket stays
	# gravity-free and flies straight).
	gravity_scale = 0.0
	if shooter != null:
		_center_line_y = float(shooter.get("center_line_y") or 0.0)
		_shoot_gravity_dir = float(shooter.get("gravity_dir") or 1.0)
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

	get_tree().create_timer(lifetime).timeout.connect(_on_fuse)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Issue #216: the grenade (and the rock, issue #227) obeys the level's
	# gravity — terrain sources first, then the center-line rule, then the
	# static direction — the same ladder the figures use (Player.gd / Npc.gd).
	if kind != Kind.ROCKET:
		state.linear_velocity += _level_gravity() * GRAVITY * state.step


## Unit gravity direction at the grenade's position (issue #216).
func _level_gravity() -> Vector2:
	if LevelTerrain.has_sources(self):
		return LevelTerrain.gravity_vector(self)
	if _center_line_y > 0.0:
		return Vector2.DOWN if global_position.y < _center_line_y else Vector2.UP
	return Vector2.UP if _shoot_gravity_dir < 0.0 else Vector2.DOWN


func _on_body_entered(body: Node2D) -> void:
	# Issue #57: never interact with the character that fired us.
	if body == shooter:
		return
	if kind == Kind.ROCKET:
		_explode()


func _on_fuse() -> void:
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
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
			body.take_damage(damage)
	_spawn_blast_visual()
	queue_free()


## Issue #227: the rock's "explosion" — a disk of destructible ground
## around the resting point. The disk is filled row by row with merged soil
## strips (DestructibleGround chunks). A grid cell is kept only when it
##  - lies inside ROCK_GROUND_RADIUS of the impact point,
##  - clears every character by ROCK_CHAR_CLEAR (1.3 x the figure's shape
##    size) — ground is created AROUND a figure, never on it, and
##  - does not overlap indestructible ground (slab or disc) or existing
##    soil — the fill borders them instead of covering them.
func _create_ground() -> void:
	var parent := get_parent()
	if parent == null:
		return
	# Characters (both teams) to keep clear of.
	var clear: Array[Vector2] = []
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body != null and is_instance_valid(body):
				clear.append(body.global_position)
	# Solid terrain the new soil must never overlap.
	var solids: Array[Rect2] = []
	var discs: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("indestructible_ground"):
		var ground := node as IndestructibleGround
		if ground == null or not is_instance_valid(ground):
			continue
		if ground.radius > 0.0:
			discs.append(Vector3(ground.position.x, ground.position.y, ground.radius))
		else:
			solids.append(Rect2(ground.position - ground.rect_size / 2.0, ground.rect_size))
	for node in get_tree().get_nodes_in_group("destructible_ground"):
		var soil := node as DestructibleGround
		if soil != null and is_instance_valid(soil):
			solids.append(Rect2(soil.position - soil.rect_size / 2.0, soil.rect_size))
	# Fill the disk row by row; consecutive kept cells merge into one strip.
	var steps := int(ceilf(ROCK_GROUND_RADIUS / ROCK_CELL))
	for iy in range(-steps, steps):
		var in_run := false
		var run_start := 0
		for ix in range(-steps, steps + 1):
			var open := ix < steps and _cell_open(ix, iy, clear, solids, discs)
			if open and not in_run:
				in_run = true
				run_start = ix
			elif not open and in_run:
				in_run = false
				_spawn_soil_strip(parent, run_start, iy, ix - run_start)


## True when the disk grid cell (ix, iy) may be filled with new soil.
func _cell_open(ix: int, iy: int, clear: Array[Vector2], solids: Array[Rect2],
			discs: Array[Vector3]) -> bool:
	var rect := Rect2(global_position + Vector2(ix, iy) * ROCK_CELL,
			Vector2(ROCK_CELL, ROCK_CELL))
	var center := rect.get_center()
	if center.distance_to(global_position) > ROCK_GROUND_RADIUS:
		return false
	# 1.3 x shape size of clearance around every character: the new ground
	# may touch the edge of that zone but never reach inside it.
	for pos in clear:
		if _rect_distance(rect, pos) < ROCK_CHAR_CLEAR:
			return false
	# Indestructible slabs and existing soil: overlap is forbidden,
	# bordering is fine (Rect2.intersects ignores exact edge contact).
	for solid in solids:
		if rect.intersects(solid):
			return false
	# Indestructible discs (hills): same rule against the circle.
	for disc in discs:
		if _rect_distance(rect, Vector2(disc.x, disc.y)) < disc.z:
			return false
	return true


## Distance from `point` to the closest point of `rect` (0 when inside).
func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var closest := Vector2(
			clampf(point.x, rect.position.x, rect.end.x),
			clampf(point.y, rect.position.y, rect.end.y))
	return closest.distance_to(point)


## One merged soil strip: `count` grid cells wide starting at column
## `first`, on row `iy`, spawned as a single DestructibleGround chunk.
func _spawn_soil_strip(parent: Node, first: int, iy: int, count: int) -> void:
	var size := Vector2(count * ROCK_CELL, ROCK_CELL)
	if size.x < DestructibleGround.MIN_PIECE or size.y < DestructibleGround.MIN_PIECE:
		return
	var piece := DestructibleGround.new()
	piece.rect_size = size
	piece.position = global_position + Vector2(
			(first + count / 2.0) * ROCK_CELL, (iy + 0.5) * ROCK_CELL)
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
