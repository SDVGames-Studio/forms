class_name SpawnRegime
extends RefCounted
## Spawn regimes (issue #523).
##
## Chosen in the level configuration menu before the level starts
## (GameConfig.spawn_regime) and applied once per level right after
## GameConfig.apply — the configuration has trimmed and dressed the
## staged figures by then, so the regime moves the LIVE set:
##
## - REGIME_GROUPED  — teams spawn together: one random anchor per team
##   (teams kept apart when the level allows it), teammates placed on
##   free spots around the anchor.
## - REGIME_RANDOM   — every figure spawns on its own random spot.
## - REGIME_DESIGNER — spawn points defined in the level by the level
##   designer: Marker2D nodes in the "spawn_points" group, filled in
##   name order by the figure plan (hero, teammates, then enemies).
##   Issue #626: when the markers run out the remaining figures spawn
##   RANDOMLY on sampled standing spots instead of keeping their
##   authored staging positions (the classic "buried mob" source).
##   Levels without markers keep the figures' authored positions —
##   the hand-placed staging IS the designer's spawn set.
## - REGIME_CHOOSE   — "choose after the start" (issue #547): the
##   level starts, the game pauses, and the player clicks every
##   FIRST-team figure onto a surface spot of their choosing (the
##   spot is validated exactly like the sampler's — floor under
##   local gravity + clearance), then the game runs. Computer and
##   hot-seat teams keep their authored positions. Rework (owner
##   2026-11-26, "before I place character it shouldn't exist on the
##   ground" / "computer didn't place any character at all"): the
##   whole staged cast enters the phase HIDDEN — a figure exists on
##   the ground only once it is placed, the player's by their clicks
##   and everyone else's by the script (the chooser reveals the
##   other teams' figures on their authored spawn spots, one per
##   beat, before the game begins). Rework (owner
##   2026-11-20, "this regime doesn't work"): the figures are placed
##   by hand whether the first team plays as a human or as the
##   computer — since the #617 rework v2 defaults EVERY team to the
##   computer, the old "computer-played hero team → designer
##   regime" fallback silently swallowed the regime in the default
##   setup: the figures just spawned and the first turn began.
##
## The random regimes find spots in ANY level with an algorithm that
## never assumes flat ground: candidate points are sampled on a grid
## across the level's terrain extent, the LOCAL gravity is read at each
## (LevelTerrain.gravity_at — gravity follows the nearest indestructible
## surface, so Level4's arcs and underside floors are covered), a short
## raycast along gravity finds the floor under the candidate, and the
## standing spot just above the surface is validated with a clearance
## circle so a figure never spawns embedded in terrain. Not enough
## valid spots for every figure → the regime keeps the authored
## positions (a level must never spawn half its figures).
##
## Issue #626: EVERY regime ends in a settle pass. A figure whose body
## ended up IN the terrain (embedded marker, authored staging, or any
## other overlap) is lifted along the local gravity axis to the
## NEAREST clear standing spot — the gravity field gives the axis
## (LevelTerrain.gravity_at points to the nearest face when the figure
## is inside a mass, and onto the surface when it is outside), so the
## search probes both directions and keeps the closest escape.
## Figures that merely float in the air are left alone: gravity drops
## them onto the ground once the game starts.

## Teams grouped together — one random team anchor, teammates nearby.
const REGIME_GROUPED := 0
## Teammates spawn randomly — every figure gets its own random spot.
const REGIME_RANDOM := 1
## Spawn points defined in the level by the level designer.
const REGIME_DESIGNER := 2
## Issue #547 "choose after the start" — the player picks each
## first-team figure's spot interactively once the level runs,
## whatever plays the team (see scripts/SpawnChooser.gd).
const REGIME_CHOOSE := 3

## Labels of the menu rows, index = regime constant.
const REGIME_LABELS: Array[String] = [
	"Random grouped teams", "All random", "Designer spawn points",
	"Choose after the start",
]

## Grid step of the candidate sampler, in world pixels.
const SAMPLE_STEP := 48.0
## How far below a candidate the floor may sit for it to count.
const MAX_DROP := 160.0
## Stand-off of a figure's centre from the surface along local gravity
## (capsule half-height 28.8 + 2 px so the first physics frame settles
## it onto the floor instead of popping it out).
const STAND_OFF := 30.8
## Clearance radius around a standing spot — nothing solid this close.
const CLEAR_RADIUS := 30.0
## Minimum distance between two sampled spots (two figures never share
## one spawn; a bit over one body width).
const MIN_GAP := 80.0
## Grouped regime: teammates are placed within this radius of the team
## anchor (relaxed to the nearest free spot when the level is crowded).
const TEAM_SPREAD := 160.0
## Grouped regime: anchors of different teams are pushed at least this
## far apart when the level has room for it.
const MIN_TEAM_GAP := 280.0
## Collision mask of the terrain: the ground bodies ride layer 1 (the
## figures' bodies are layer 8), so only ground is probed.
const GROUND_MASK := 1
## Issue #626: how far an embedded figure may be lifted along the
## local gravity axis while searching for a free standing spot (each
## direction; every mass sits within this reach).
const MAX_LIFT := 640.0
## Issue #626: step of the settle search along the gravity axis.
const LIFT_STEP := 8.0
## Issue #626: the settle delay for the choose regime, in seconds —
## a process_always SceneTreeTimer so it fires through the chooser's
## pause (the physics space stays queryable while paused).
const SETTLE_DELAY := 0.25

## Issue #547: the interactive placement phase (REGIME_CHOOSE).
## Preloaded, not a class_name reference — SpawnChooser mirrors this
## script's constants instead of referencing it back (no cycle).
const SpawnChooserScript := preload("res://scripts/SpawnChooser.gd")


## Apply the configured regime to `level` (GameConfig.spawn_regime).
## Call AFTER GameConfig.apply so the trimmed/dressed live figures move.
## The random regimes probe physics (raycasts along local gravity),
## and the level's freshly-entered ground bodies only become queryable
## once the next physics step has flushed the space — so the scatter
## runs two physics frames later (figures authored standing on the
## ground simply stand one more frame before being placed). The
## designer regime reads markers only and runs immediately.
static func apply(level: Node) -> void:
	match GameConfig.spawn_regime:
		REGIME_GROUPED, REGIME_RANDOM:
			var tree := level.get_tree()
			var grouped := GameConfig.spawn_regime == REGIME_GROUPED
			var place := func() -> void:
				await tree.physics_frame
				_scatter(level, grouped)
				# Issue #626: the check runs in every mode — sampled
				# spots are clear by construction, but when the scatter
				# runs out of spots the authored positions stay and
				# may sit in terrain.
				_settle_figures(level, [])
			tree.physics_frame.connect(place, CONNECT_ONE_SHOT)
		REGIME_CHOOSE:
			_apply_choose(level)
		_:
			_apply_designer(level)


## Issue #547 regime 4: hand-place the FIRST team after the start.
## A SpawnChooser child of the level pauses the tree and lets the
## player click each first-team figure onto a validated surface
## spot (hero first, see scripts/SpawnChooser.gd). Rework (owner
## 2026-11-20): the placement runs whether the first team plays as
## a human or as the computer — the chooser only needs the hand on
## the mouse, and since the #617 rework v2 defaults every team to
## the computer, the old controller fallback made the regime a
## silent no-op in the default setup. Rework (owner 2026-11-26):
## a figure must not exist on the ground before it is placed — the
## whole staged cast (first team included) enters the phase hidden,
## the authored staging doubling as each figure's spawn point; the
## chooser reveals the figure being placed at the cursor and, once
## the player is done, script-places everyone still hidden on
## their authored spots before the game begins. A level with no
## first-team figures at all (pure spectate staging) still falls
## back to the designer regime — there is nothing on the player
## side to click.
static func _apply_choose(level: Node) -> void:
	var figures: Array = []
	for figure in level.get_tree().get_nodes_in_group("player_team"):
		if _is_placeable(figure, level):
			figures.append(figure)
	if figures.is_empty():
		_apply_designer(level)
		return
	# Owner rework 2026-11-26: hide the staged cast BEFORE the chooser
	# enters the tree — nobody is ever seen standing on the authored
	# staging. The chooser reveals each figure when it is placed: the
	# player's at the clicked spot, the other teams' at their authored
	# spawn spots once the player is done.
	var staged: Array = _live_figures(level)
	for figure in staged:
		(figure as Node2D).visible = false
	var chooser := SpawnChooserScript.new()
	chooser.name = "SpawnChooser"
	chooser.process_mode = Node.PROCESS_MODE_ALWAYS
	chooser.figures = figures
	chooser.staged = staged
	level.add_child(chooser)
	# Issue #626: everyone NOT handed to the chooser (enemies, hot-seat
	# teams) keeps the authored positions — settle them out of the
	# ground while the chooser holds its pause. A process_always timer
	# fires through the pause, and the physics space stays queryable
	# (the chooser validates its own clicks the same way while paused).
	var others: Array = []
	for figure in _live_figures(level):
		if not figures.has(figure):
			others.append(figure)
	var tree := level.get_tree()
	var settle := func() -> void:
		await tree.create_timer(SETTLE_DELAY, true).timeout
		for figure in others:
			if is_instance_valid(figure):
				_unstick(figure as Node2D)
	settle.call()


## Issue #523 regime 3: fill the level's "spawn_points" markers (name
## order) with the figure plan — hero, teammates, then the computer
## teams. Issue #626: figures beyond the marker count spawn RANDOMLY
## on sampled standing spots, and every placed figure is settled out
## of the ground once the physics space has flushed. Levels with no
## markers keep the figures' authored positions (and settle them the
## same way).
static func _apply_designer(level: Node) -> void:
	var markers := level.get_tree().get_nodes_in_group("spawn_points")
	var usable: Array = []
	for marker in markers:
		var node := marker as Node2D
		if node != null and not node.is_queued_for_deletion() \
				and is_ancestor_or_self(level, node):
			usable.append(node)
	usable.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return str(a.name) < str(b.name))
	var figures := _live_figures(level)
	var placed := 0
	var rest: Array = []
	if not usable.is_empty():
		for i in mini(figures.size(), usable.size()):
			(figures[i] as Node2D).global_position = \
					(usable[i] as Node2D).global_position
			placed = i + 1
		# Issue #626: figures beyond the marker count spawn randomly.
		rest = figures.slice(placed)
	var taken: Array = []
	for marker in usable:
		taken.append((marker as Node2D).global_position)
	_settle_soon(level, rest, taken)


static func is_ancestor_or_self(ancestor: Node, node: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor == ancestor:
			return true
		cursor = cursor.get_parent()
	return false


## The live figure set in plan order — the player team (hero first,
## authoring order), then the computer/human-staged enemy teams.
static func _live_figures(level: Node) -> Array:
	var figures: Array = []
	for figure in level.get_tree().get_nodes_in_group("player_team"):
		if _is_placeable(figure, level):
			figures.append(figure)
	for figure in level.get_tree().get_nodes_in_group("enemy_team"):
		if _is_placeable(figure, level):
			figures.append(figure)
	return figures


static func _is_placeable(node: Node, level: Node) -> bool:
	return node is Node2D and not node.is_queued_for_deletion() \
			and is_ancestor_or_self(level, node)


## Issue #626: the deferred tail of the designer regime — runs once
## the physics space has flushed (the scatter's pattern): the random
## fallback deals the leftover figures onto sampled spots, then every
## live figure is checked against the ground and lifted out when
## embedded.
static func _settle_soon(level: Node, rest: Array, taken: Array) -> void:
	var tree := level.get_tree()
	var finish := func() -> void:
		await tree.physics_frame
		if not is_instance_valid(level) or not level.is_inside_tree():
			return
		if not rest.is_empty():
			_random_fallback(level, rest, taken)
		_settle_figures(level, [])
	tree.physics_frame.connect(finish, CONNECT_ONE_SHOT)


## Issue #626: figures the designer's markers could not hold spawn on
## randomly sampled standing spots (validated exactly like the random
## regimes). A sampler that cannot fit everyone leaves the rest on
## their authored positions — the settle pass still digs them out.
static func _random_fallback(level: Node, figures: Array,
		taken: Array) -> void:
	var spots := _collect_spots(level)
	var free: Array = []
	for spot in spots:
		if _far_enough(spot, taken):
			free.append(spot)
	for figure in figures:
		if free.is_empty():
			break
		var spot: Vector2 = free.pop_front()
		taken.append(spot)
		(figure as Node2D).global_position = spot


## Issue #626: dig every live figure out of the terrain (`skip` keeps
## figures another owner is moving — the choose regime's chooser).
static func _settle_figures(level: Node, skip: Array) -> void:
	for figure in _live_figures(level):
		if skip.has(figure):
			continue
		_unstick(figure as Node2D)


## Issue #626: a figure whose body sits IN the terrain is moved UP
## out of the ground along the local gravity field. The field read at
## the figure says which way is up: from OUTSIDE a mass it pulls onto
## the surface (escape = against it), from INSIDE it points at the
## escape face (escape = with it — a slab's inside field points up, a
## disc's outward). The escape pass runs first; the opposite direction
## is the fallback for a capped escape (a figure buried under an
## overhang exits through the underside floor instead). The clearance
## of each probe reads the LOCAL gravity at the probe — the axis
## gravity is stale once the probe has left the terrain. A figure that
## merely floats in the air is left alone; a figure the search cannot
## free within MAX_LIFT keeps its position and physics depenetration
## remains the last resort it always was.
static func _unstick(figure: Node2D) -> void:
	if figure == null or not figure.is_inside_tree():
		return
	var space := figure.get_world_2d().direct_space_state
	var at := figure.global_position
	if not _embedded(space, at):
		return
	var tree := figure.get_tree()
	var grav := LevelTerrain.gravity_at(tree, at)
	if grav == Vector2.ZERO:
		grav = Vector2.DOWN
	grav = grav.normalized()
	# Inside/outside decides the escape side (LevelTerrain.contains —
	# exact geometry, physics point queries miss inside concave
	# decomposition shapes).
	var inside := LevelTerrain.contains(tree, at)
	var escape := grav if inside else -grav
	var steps := int(MAX_LIFT / LIFT_STEP)
	for i in range(1, steps + 1):
		var probe: Vector2 = at + escape * (LIFT_STEP * i)
		if _is_clear(space, probe, LevelTerrain.gravity_at(tree, probe)):
			figure.global_position = probe
			return
	for i in range(1, steps + 1):
		var probe: Vector2 = at - escape * (LIFT_STEP * i)
		if _is_clear(space, probe, LevelTerrain.gravity_at(tree, probe)):
			figure.global_position = probe
			return


## Issue #626: does a figure-sized clearance disc at `at` overlap the
## terrain? True means the position is inside the ground.
static func _embedded(space: PhysicsDirectSpaceState2D,
		at: Vector2) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = CLEAR_RADIUS
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = GROUND_MASK
	params.transform = Transform2D(0.0, at)
	return not space.intersect_shape(params, 1).is_empty()


## Issue #523 regimes 1–2: scatter the live figures over sampled
## standing spots — GROUPED keeps each team around one random anchor,
## RANDOM deals the spots independently.
static func _scatter(level: Node, grouped: bool) -> void:
	var figures := _live_figures(level)
	if figures.is_empty():
		return
	var spots := _collect_spots(level)
	if spots.size() < figures.size():
		# Not enough standing room for everyone — never drop half the
		# cast; the authored positions stay.
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	spots.shuffle()
	var taken: Array[Vector2] = []
	if not grouped:
		for figure in figures:
			var spot: Vector2 = spots.pop_front()
			taken.append(spot)
			(figure as Node2D).global_position = spot
		return
	# Grouped regime: one random anchor per team — tried in random team
	# order so no team is structurally stuck on one side of the level —
	# with the team's figures placed on free spots around the anchor.
	var team_colors: Array = []
	for figure in figures:
		var color: Color = figure.get("team_color")
		if not team_colors.has(color):
			team_colors.append(color)
	var team_order: Array = []
	for i in team_colors.size():
		team_order.append(i)
	team_order.shuffle()
	var anchors: Array[Vector2] = []
	for team_index in team_order:
		var color: Color = team_colors[team_index]
		var anchor := _pick_anchor(spots, anchors, rng)
		if anchor == Vector2.INF:
			return
		anchors.append(anchor)
		var first := true
		for figure in figures:
			if figure.get("team_color") != color:
				continue
			var spot := anchor
			if not first:
				spot = _nearest_free(spots, anchor, TEAM_SPREAD, taken)
				if spot == Vector2.INF:
					return
			first = false
			taken.append(spot)
			spots.erase(spot)
			(figure as Node2D).global_position = spot


## One team anchor: try a handful of random spots, keep the one
## farthest from the already-taken anchors (spacing MIN_TEAM_GAP when
## the level has room — crowded levels simply take the best of the
## tries rather than failing).
static func _pick_anchor(spots: Array, anchors: Array[Vector2],
		rng: RandomNumberGenerator) -> Vector2:
	var best := Vector2.INF
	var best_score := -INF
	var tries := maxi(4, mini(spots.size(), 12))
	for i in tries:
		var candidate: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		var score := INF
		for anchor in anchors:
			score = minf(score, candidate.distance_to(anchor))
		if score > best_score:
			best_score = score
			best = candidate
	return best


## Nearest free spot to `center` (within `radius`, relaxed to global
## nearest when the neighbourhood is full).
static func _nearest_free(spots: Array, center: Vector2,
		radius: float, taken: Array[Vector2]) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for spot in spots:
		if taken.has(spot):
			continue
		var d: float = (spot as Vector2).distance_to(center)
		if d <= radius and d < best_d:
			best_d = d
			best = spot
	if best != Vector2.INF:
		return best
	for spot in spots:
		if taken.has(spot):
			continue
		var d: float = (spot as Vector2).distance_to(center)
		if d < best_d:
			best_d = d
			best = spot
	return best


## Sample standing spots on a grid across the terrain extent. Each
## candidate reads its LOCAL gravity, casts along it for a floor and
## validates the standing point with a clearance circle; kept spots are
## at least MIN_GAP apart.
static func _collect_spots(level: Node) -> Array:
	var rect := _terrain_rect(level)
	if not rect.has_area():
		return []
	var space := (level as Node2D).get_world_2d().direct_space_state
	var tree := level.get_tree()
	var spots: Array = []
	var y := rect.position.y - SAMPLE_STEP
	while y <= rect.end.y + SAMPLE_STEP:
		var x := rect.position.x - SAMPLE_STEP
		while x <= rect.end.x + SAMPLE_STEP:
			var at := Vector2(x, y)
			var grav := LevelTerrain.gravity_at(tree, at)
			var params := PhysicsRayQueryParameters2D.create(
					at, at + grav * MAX_DROP, GROUND_MASK)
			var hit := space.intersect_ray(params)
			if not hit.is_empty():
				var stand: Vector2 = hit["position"] - grav * STAND_OFF
				if _is_clear(space, stand, grav) \
						and _far_enough(stand, spots):
					spots.append(stand)
			x += SAMPLE_STEP
		y += SAMPLE_STEP
	spots.shuffle()
	return spots


## The standing spot must be free of terrain AND still have its floor:
## a clearance circle finds nothing solid, and a short ray along
## gravity reaches the ground.
static func _is_clear(space: PhysicsDirectSpaceState2D, stand: Vector2,
		grav: Vector2) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = CLEAR_RADIUS
	var shape_params := PhysicsShapeQueryParameters2D.new()
	shape_params.shape = circle
	shape_params.collision_mask = GROUND_MASK
	shape_params.transform = Transform2D(0.0, stand)
	if not space.intersect_shape(shape_params, 1).is_empty():
		return false
	var floor_params := PhysicsRayQueryParameters2D.create(
			stand, stand + grav * (STAND_OFF + CLEAR_RADIUS), GROUND_MASK)
	return not space.intersect_ray(floor_params).is_empty()


static func _far_enough(candidate: Vector2, spots: Array) -> bool:
	for spot in spots:
		if candidate.distance_to(spot) < MIN_GAP:
			return false
	return true


## World-space extent of the level's terrain: the union of every
## collision shape on the level's StaticBody2Ds (figures are
## CharacterBody2Ds, so they never contribute).
static func _terrain_rect(level: Node) -> Rect2:
	var rect := Rect2()
	var any_point := false
	for body in _static_bodies(level):
		for child in body.get_children():
			var poly := child as CollisionPolygon2D
			var shape_node := child as CollisionShape2D
			if poly != null and poly.disabled == false:
				for point in poly.polygon:
					rect = _expand(rect, poly.to_global(point), any_point)
					any_point = true
			elif shape_node != null and shape_node.shape != null:
				for point in _shape_points(shape_node.shape):
					rect = _expand(rect, shape_node.to_global(point),
							any_point)
					any_point = true
	return rect


## Rect2.expand from a DEGENERATE origin would pin the rect at (0,0);
## the first sample seeds the rect instead.
static func _expand(rect: Rect2, at: Vector2, any_point: bool) -> Rect2:
	if any_point:
		return rect.expand(at)
	return Rect2(at, Vector2.ZERO)


## Bounding-box corners of a primitive shape (its local space).
static func _shape_points(shape: Shape2D) -> Array:
	var rect := shape as RectangleShape2D
	if rect != null:
		var half := rect.size / 2.0
		return [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(-half.x, half.y), Vector2(half.x, half.y)]
	var circle := shape as CircleShape2D
	if circle != null:
		return [Vector2(-circle.radius, 0.0), Vector2(circle.radius, 0.0),
				Vector2(0.0, -circle.radius), Vector2(0.0, circle.radius)]
	var capsule := shape as CapsuleShape2D
	if capsule != null:
		return [Vector2(-capsule.radius, -capsule.height / 2.0),
				Vector2(capsule.radius, -capsule.height / 2.0),
				Vector2(-capsule.radius, capsule.height / 2.0),
				Vector2(capsule.radius, capsule.height / 2.0)]
	var segment := shape as SegmentShape2D
	if segment != null:
		return [segment.a, segment.b]
	var convex := shape as ConvexPolygonShape2D
	if convex != null:
		return Array(convex.points)
	var concave := shape as ConcavePolygonShape2D
	if concave != null:
		return Array(concave.points)
	return []


## Every StaticBody2D under `level`, at any depth (custom levels author
## ground as direct children; stock scenes nest theirs the same way).
static func _static_bodies(level: Node) -> Array:
	var bodies: Array = []
	for child in level.get_children():
		if child is StaticBody2D:
			bodies.append(child)
		var inner := child as Node
		if inner != null:
			bodies.append_array(_static_bodies(inner))
	return bodies
