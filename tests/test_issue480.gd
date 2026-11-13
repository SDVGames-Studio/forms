extends Node
## Regression check for issue #480: the Rock tool's created ground must
## fill up to the TRUE shape of nearby polygon soil — the old exclusion
## used each chunk's AABB, so beside a dome or trapezoid hill (whose
## bounding box is mostly empty air) the crumble disk kept an unfilled
## RECTANGLE. Verified against synthetic copies of Level2's hills:
##  - probes inside a hill's AABB but OUTSIDE the hill itself (the old
##    rectangular hole) must land on fresh soil,
##  - every strip corner stays within PRECISION of the disk circle.
## Issue #480 rework: existing soil is no longer banned — the crumble
## covers it (same material, invisible) so the initial ground and the
## disk read as ONE body: every grid sample inside the disk (clear of
## the rim, where strips legally end on the circle) must be hill soil
## or fresh crumble soil — NO seam anywhere between them.
## Issue #480 rework 2: the indestructible-slab ban follows the slab's
## EFFECTIVE rounded rectangle (#270 corner arcs) — the corner recess
## (inside the authored AABB, outside the rounded polygon, inside the
## disk) must be FILLED, and no strip may poke into the polygon; the
## old raw-rect ban left an air wedge at every rounded corner.
##
## Run headless: godot --headless res://tests/test_issue480.tscn
## Exit code 0 = pass.

const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")

## Issue #324 contract, unchanged: no strip corner overshoots the disk.
const PRECISION := 5.0

## Level2's TrapezoidHill shape: base half-width 180, top 130, 256 tall
## (PackedVector2Array is not a constant expression — built at runtime).
var _trap_poly := PackedVector2Array()
## Level2's DomeHill shape: a 32-gon disc of radius 256.
const DOME := Vector2(2000, 0)
const TRAP := Vector2(1000, 0)

var _level: Node2D
## Issue #480 rework 2: the rounded slab whose top-left corner the third
## crumble hugs (authored 600 x 448 — corner arcs of 192 px, the exact
## geometry every level slab gets from the #270 rules).
var _slab: IndestructibleGround


func _ready() -> void:
	var ok := true
	_trap_poly = PackedVector2Array([Vector2(-180, 0), Vector2(180, 0),
			Vector2(130, -256), Vector2(-130, -256)])
	_level = Node2D.new()
	_level.name = "Issue480Level"
	add_child(_level)
	_make_soil(TRAP, _trap_poly)
	_make_soil(DOME, _disc_polygon(256.0, 32))
	# Impact beside the trapezoid's slanted side, INSIDE its AABB: the
	# old AABB ban left a rectangle of thin air inside the disk here.
	ok = ok and await _check_crumble(Vector2(1165, -200))
	# Impact beside the dome, inside its square AABB but outside the disc.
	ok = ok and await _check_crumble(Vector2(2235, -180))
	# Issue #480 rework 2: impact beside a slab's rounded top-left corner,
	# where the raw-rect ban left the wedge-shaped air gap.
	_slab = IndestructibleGround.new()
	_slab.rect_size = Vector2(600, 448)
	_slab.position = Vector2(1100, 640)
	_level.add_child(_slab)
	ok = ok and await _check_corner_crumble(Vector2(880, 360))
	print("ISSUE480 ok=", ok)
	get_tree().quit(0 if ok else 1)


func _make_soil(at: Vector2, poly: PackedVector2Array) -> void:
	var soil := DestructibleGround.new()
	soil.position = at
	soil.polygon = poly
	_level.add_child(soil)


## A closed regular n-gon disc like Level2's DomeHill authoring.
func _disc_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


## Crumble a rock at `at` and verify the issue #480 rules.
func _check_crumble(at: Vector2) -> bool:
	var before: Array = get_tree().get_nodes_in_group("destructible_ground").duplicate()
	var rock := RigidBody2D.new()
	rock.set_script(ProjectileBodyScript)
	rock.setup(ProjectileBody.Kind.ROCK, Vector2.ZERO, 0, 3.0,
		Vector2(16, 16), Color.GRAY, ProjectileBody.ROCK_GROUND_RADIUS, 0.8)
	_level.add_child(rock)
	rock.global_position = at
	rock._explode()
	for i in 5:
		await get_tree().physics_frame
	var fresh: Array = []
	for chunk in get_tree().get_nodes_in_group("destructible_ground"):
		if not before.has(chunk):
			fresh.append(chunk)
	print("ISSUE480 crumble at ", at, " new_soil=", fresh.size())
	var good := fresh.size() >= 3
	var hills: Array[PackedVector2Array] = []
	for chunk in before:
		var soil := chunk as DestructibleGround
		if soil == null:
			continue
		var world := PackedVector2Array()
		for p in soil.local_outline():
			world.append(p + soil.position)
		hills.append(world)
	for chunk in fresh:
		var rect := Rect2(chunk.position - chunk.rect_size / 2.0, chunk.rect_size)
		for corner in [rect.position, rect.end,
				Vector2(rect.position.x, rect.end.y),
				Vector2(rect.end.x, rect.position.y)]:
			var over: float = corner.distance_to(at) - ProjectileBody.ROCK_GROUND_RADIUS
			if over > PRECISION:
				print("ISSUE480 FAIL corner ", over, " px past the disk: ", corner)
				good = false
	# Rework contract: hill soil ∪ fresh crumble soil must cover the whole
	# disk (minus a rim margin, where strips legally end ON the circle) —
	# a wedge or staircase gap along a hill's slanted edge reads as a
	# border between the initial ground and the crumble and fails here.
	var rim := ProjectileBody.ROCK_GROUND_RADIUS - 9.0
	var samples := 0
	for gy in range(int(-rim), int(rim) + 1, 6):
		for gx in range(int(-rim), int(rim) + 1, 6):
			var probe := at + Vector2(gx, gy)
			if probe.distance_to(at) > rim:
				continue
			samples += 1
			var covered := false
			for hill in hills:
				if _point_in_polygon(probe, hill):
					covered = true
					break
			if not covered:
				for chunk in fresh:
					var r := Rect2(chunk.position - chunk.rect_size / 2.0,
							chunk.rect_size)
					if r.has_point(probe):
						covered = true
						break
			if not covered:
				print("ISSUE480 FAIL seam/hole inside the disk at ", probe)
				good = false
	print("ISSUE480 seam samples at ", at, ": ", samples)
	# The old bug's signature: probes inside a hill's AABB but OUTSIDE
	# the hill itself used to stay empty. They must be covered now.
	var holes := 0
	for probe in _hole_probes(at):
		holes += 1
		var covered := false
		for chunk in fresh:
			var r := Rect2(chunk.position - chunk.rect_size / 2.0, chunk.rect_size)
			if r.has_point(probe):
				covered = true
				break
		if not covered:
			print("ISSUE480 FAIL old-style rectangular hole at ", probe)
			good = false
	print("ISSUE480 hole probes at ", at, ": ", holes)
	return good and holes > 0


## Crumble a rock beside the slab's ROUNDED corner (issue #480 rework 2)
## and verify both directions of the contract: the corner recess gets
## filled (the raw-rect ban left an air wedge there) and no strip pokes
## into the rounded polygon (bordering it is legal and required).
func _check_corner_crumble(at: Vector2) -> bool:
	var before: Array = get_tree().get_nodes_in_group("destructible_ground").duplicate()
	var rock := RigidBody2D.new()
	rock.set_script(ProjectileBodyScript)
	rock.setup(ProjectileBody.Kind.ROCK, Vector2.ZERO, 0, 3.0,
		Vector2(16, 16), Color.GRAY, ProjectileBody.ROCK_GROUND_RADIUS, 0.8)
	_level.add_child(rock)
	rock.global_position = at
	rock._explode()
	for i in 5:
		await get_tree().physics_frame
	var fresh: Array = []
	for chunk in get_tree().get_nodes_in_group("destructible_ground"):
		if not before.has(chunk):
			fresh.append(chunk)
	print("ISSUE480 corner crumble at ", at, " new_soil=", fresh.size())
	var good := fresh.size() >= 3
	var poly := _outline_world(IndestructibleGround.rounded_rect_polygon(
				_slab.effective_size(), _slab.corner_radius(),
				_slab.effective_offset()), _slab.position)
	var aabb := Rect2(_slab.position - _slab.rect_size / 2.0,
			_slab.rect_size)
	# 1) The corner recess — inside the authored AABB, outside the
	# rounded polygon (clear of its outline by a row band), inside the
	# disk clear of the rim — must be fresh crumble soil, not air.
	var rim := ProjectileBody.ROCK_GROUND_RADIUS - 9.0
	var recess := 0
	for gy in range(int(-rim), int(rim) + 1, 4):
		for gx in range(int(-rim), int(rim) + 1, 4):
			var probe := at + Vector2(gx, gy)
			if probe.distance_to(at) > rim or not aabb.has_point(probe):
				continue
			if _point_in_polygon(probe, poly) or _point_near_polygon(probe,
					poly, ProjectileBody.ROCK_ROW + 0.5):
				continue
			recess += 1
			var covered := false
			for chunk in fresh:
				var r := Rect2(chunk.position - chunk.rect_size / 2.0,
						chunk.rect_size)
				if r.has_point(probe):
					covered = true
					break
			if not covered:
				print("ISSUE480 FAIL corner wedge stayed empty at ", probe)
				good = false
	print("ISSUE480 corner recess probes: ", recess)
	if recess == 0:
		print("ISSUE480 FAIL no recess probes generated")
		good = false
	# 2) No fresh strip may overlap the rounded polygon (deeper than the
	# sub-pixel slack between the arc and its 12-segment polygon).
	for chunk in fresh:
		var r := Rect2(chunk.position - chunk.rect_size / 2.0, chunk.rect_size)
		for sample in [r.position, r.end, Vector2(r.position.x, r.end.y),
				Vector2(r.end.x, r.position.y), r.get_center()]:
			if _deep_inside(sample, poly, 1.0):
				print("ISSUE480 FAIL strip pokes into the slab at ", sample)
				good = false
	return good


## Probes in the disk, inside a hill's AABB, but clear of every hill by
## more than one row band — exactly the spots the AABB ban hollowed out.
func _hole_probes(at: Vector2) -> Array:
	var hills: Array[PackedVector2Array] = [
		_outline_world(_trap_poly, TRAP),
		_outline_world(_disc_polygon(256.0, 32), DOME)]
	var probes: Array = []
	for i in 180:
		var probe := at + Vector2.from_angle(TAU * float(i) / 180.0) \
				* ProjectileBody.ROCK_GROUND_RADIUS * 0.6
		var near_aabb := false
		var clear := true
		for hill in hills:
			var aabb := Rect2(hill[0], Vector2.ZERO)
			for p in hill:
				aabb = aabb.expand(p)
			if aabb.grow(1.0).has_point(probe):
				near_aabb = true
			if _point_near_polygon(probe, hill,
					ProjectileBody.ROCK_ROW + 0.5):
				clear = false
		if near_aabb and clear:
			probes.append(probe)
	return probes


func _outline_world(poly: PackedVector2Array, at: Vector2) -> PackedVector2Array:
	var world := PackedVector2Array()
	for p in poly:
		world.append(p + at)
	return world


func _point_in_polygon(p: Vector2, pts: PackedVector2Array) -> bool:
	var inside := false
	var n := pts.size()
	var j := n - 1
	for i in n:
		if (pts[i].y > p.y) != (pts[j].y > p.y) \
				and p.x < (pts[j].x - pts[i].x) * (p.y - pts[i].y) \
				/ (pts[j].y - pts[i].y) + pts[i].x:
			inside = not inside
		j = i
	return inside


## True when `p` is inside the polygon or within `margin` of its outline.
func _point_near_polygon(p: Vector2, pts: PackedVector2Array,
		margin: float) -> bool:
	if _point_in_polygon(p, pts):
		return true
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001),
				0.0, 1.0)
		if p.distance_to(a + ab * t) <= margin:
				return true
	return false


## True when `p` sits inside `pts` deeper than `margin` from its outline —
## the strict half of `_point_near_polygon`, for overlap checks where
## touching the outline is legal but crossing it is not.
func _deep_inside(p: Vector2, pts: PackedVector2Array,
		margin: float) -> bool:
	if not _point_in_polygon(p, pts):
		return false
	var best := 1e9
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001),
				0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best > margin
