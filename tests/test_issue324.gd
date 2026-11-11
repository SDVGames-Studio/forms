extends Node
## Regression check for issue #324: the Rock tool's created ground must be
## PRECISE — the crumble disk's outline follows its circle instead of the
## chunky 25 px cell staircase. Every strip's farthest corner stays within
## PRECISION (5 px) of ROCK_GROUND_RADIUS, the disk has no interior gaps,
## and the issue #227 rules still hold (figure clearance, never overlapping
## indestructible ground).
##
## Run headless: godot --headless res://tests/test_issue324.tscn
## Exit code 0 = pass.

const ProjectileBodyScript := preload("res://ProjectileBody.gd")

## Same value as ProjectileBody.ROCK_CHAR_CLEAR (1.3 x the 64 px shape).
const CLEAR := 1.3 * 64.0
## Issue #324 contract: no strip corner may reach farther than this past
## the disk radius (chord rows of ROCK_ROW px keep corners within
## ~4.8 px; the old 25 px cells overshot by up to ~18 px).
const PRECISION := 5.0


func _ready() -> void:
	var ok := true
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 10:
		await get_tree().physics_frame
	var chars: Array = []
	chars.append_array(get_tree().get_nodes_in_group("player_team"))
	chars.append_array(get_tree().get_nodes_in_group("enemy_team"))

	# Open air above the figures: the full disk must appear, precise and
	# gap-free.
	ok = ok and await _check_crumble(level, Vector2(576, 330), chars, true)
	# Tight spot beside the hill disc: exclusions bite into the disk but
	# every surviving strip still obeys the precision + issue rules.
	ok = ok and await _check_crumble(level, Vector2(380, 380), chars, false)
	print("ISSUE324 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Crumble a rock at `at` and verify every spawned soil strip hugs the
## disk's circle (corner overshoot <= PRECISION) and honours the #227
## rules; with `check_coverage`, 16 probes at 80% of the radius must all
## land on fresh soil (no gaps inside the disk).
func _check_crumble(level: Node, at: Vector2, chars: Array,
		check_coverage: bool) -> bool:
	var before: Array = get_tree().get_nodes_in_group("destructible_ground").duplicate()
	var rock := RigidBody2D.new()
	rock.set_script(ProjectileBodyScript)
	rock.setup(ProjectileBody.Kind.ROCK, Vector2.ZERO, 0, 3.0,
		Vector2(16, 16), Color.GRAY, ProjectileBody.ROCK_GROUND_RADIUS, 0.8)
	level.add_child(rock)
	rock.global_position = at
	rock._explode()
	for i in 5:
		await get_tree().physics_frame
	var fresh: Array = []
	for chunk in get_tree().get_nodes_in_group("destructible_ground"):
		if not before.has(chunk):
			fresh.append(chunk)
	print("ISSUE324 crumble at ", at, " new_soil=", fresh.size())
	var good := fresh.size() >= 3
	for chunk in fresh:
		var rect := Rect2(chunk.position - chunk.rect_size / 2.0, chunk.rect_size)
		# Precision: the farthest CORNER of every strip stays within
		# PRECISION of the disk radius — the outline hugs the circle.
		for corner in [rect.position, rect.end,
				Vector2(rect.position.x, rect.end.y),
				Vector2(rect.end.x, rect.position.y)]:
			var over: float = corner.distance_to(at) - ProjectileBody.ROCK_GROUND_RADIUS
			if over > PRECISION:
				print("ISSUE324 FAIL corner ", over, " px past the disk: ", corner)
				good = false
		for c in chars:
			if _rect_distance(rect, c.global_position) < CLEAR - 0.01:
				print("ISSUE324 FAIL inside figure clearance: ", chunk.position)
				good = false
		for node in get_tree().get_nodes_in_group("indestructible_ground"):
			var g := node as IndestructibleGround
			if g == null:
				continue
			if g.radius > 0.0:
				if _rect_distance(rect, g.position) < g.radius - 0.01:
					print("ISSUE324 FAIL overlaps the hill disc: ", chunk.position)
					good = false
			else:
				var solid := Rect2(g.position - g.rect_size / 2.0, g.rect_size)
				if rect.intersects(solid):
					print("ISSUE324 FAIL overlaps a slab: ", chunk.position)
					good = false
	if check_coverage:
		for i in 16:
			var probe := at + Vector2.from_angle(TAU * float(i) / 16.0) \
					* ProjectileBody.ROCK_GROUND_RADIUS * 0.8
			# A probe may stay soil-free when a strip covering it could not
			# exist: some exclusion (figure clearance, indestructible
			# ground, existing soil) reaches the probe's COLUMN across its
			# whole ROCK_ROW row band — the strip that would span that band is
			# banned. Test the vertical sliver at the probe's x.
			var rel_y := probe.y - at.y
			var sliver := Rect2(Vector2(probe.x,
					at.y + floorf(rel_y / ProjectileBody.ROCK_ROW)
							* ProjectileBody.ROCK_ROW),
					Vector2(0.001, ProjectileBody.ROCK_ROW))
			var excluded := false
			for c in chars:
				if _rect_distance(sliver, c.global_position) < CLEAR:
					excluded = true
					break
			if not excluded:
				for node in get_tree().get_nodes_in_group("indestructible_ground"):
					var g := node as IndestructibleGround
					if g == null:
						continue
					if g.radius > 0.0:
						if _rect_distance(sliver, g.position) < g.radius:
							excluded = true
							break
					else:
						var solid := Rect2(g.position - g.rect_size / 2.0, g.rect_size)
						if sliver.intersects(solid):
							excluded = true
							break
			if not excluded:
				for chunk in before:
					var soil := chunk as DestructibleGround
					if soil == null:
						continue
					var s := Rect2(soil.position - soil.rect_size / 2.0, soil.rect_size)
					if sliver.intersects(s):
						excluded = true
						break
			if excluded:
				continue
			var covered := false
			for chunk in fresh:
				var r := Rect2(chunk.position - chunk.rect_size / 2.0, chunk.rect_size)
				if r.has_point(probe):
					covered = true
					break
			if not covered:
				print("ISSUE324 FAIL gap in the disk at ", probe)
				good = false
	return good


## Distance from `point` to the closest point of `rect` (0 when inside).
func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var closest := Vector2(
			clampf(point.x, rect.position.x, rect.end.x),
			clampf(point.y, rect.position.y, rect.end.y))
	return closest.distance_to(point)
