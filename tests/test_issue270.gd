extends Node
## Regression check for issue #270 (part 1 — indestructible terrain
## geometry): in EVERY level
##  - each indestructible mass is at least 7 character widths thick
##    (BODY_SIZE = 64 -> 448 px; discs by diameter, slabs by the effective
##    size built in IndestructibleGround._ready),
##  - each slab's walkable top face is exactly where the scene authored it
##    (the thickness guard only extends downward),
##  - each slab's collision is a rounded-rect polygon with a corner radius
##    of at least 3 character widths (192 px),
##  - two SEPARATED indestructible masses keep at least 8 character widths
##    (512 px) of gap; touching/overlapping masses count as ONE landmass,
##  - gravity still points toward the slab surface (down above it, up below
##    it) with the new polygon shape.
##
## Run headless: godot --headless res://tests/test_issue270.tscn
## Exit code 0 = pass.

const LEVELS := [
	preload("res://scenes/levels/Level.tscn"),
	preload("res://scenes/levels/Level2.tscn"),
	preload("res://scenes/levels/Level3.tscn"),
	preload("res://scenes/levels/Level4.tscn"),
	preload("res://scenes/levels/Level5.tscn"),
	preload("res://scenes/levels/LevelDuel.tscn"),
]
const Terrain := preload("res://scripts/LevelTerrain.gd")

const CHAR := 64.0
const MIN_THICK := 7.0 * CHAR
const MIN_CORNER := 3.0 * CHAR
const MIN_GAP := 8.0 * CHAR
const EPS := 0.5


func _ready() -> void:
	var ok := true
	for level_res in LEVELS:
		var level: Node = level_res.instantiate()
		add_child(level)
		# Let _ready + GameConfig.apply (deferred) settle.
		await get_tree().physics_frame
		await get_tree().physics_frame
		ok = _check_level(level) and ok
		if level.scene_file_path.ends_with("Level.tscn"):
			ok = _check_gravity(level) and ok
		level.queue_free()
		await get_tree().physics_frame
	print("ISSUE270 ok=", ok)
	get_tree().quit(0 if ok else 1)


func _check_level(level: Node) -> bool:
	var lvl_name := String(level.name)
	var ok := true
	var grounds: Array = []
	for node in level.get_children():
		if node is Node2D and node.is_in_group("indestructible_ground"):
			grounds.append(node)
	print("ISSUE270 ", lvl_name, " grounds=", grounds.size())

	# --- Per-mass rules: thickness, top face, rounded corners. ---
	for ground in grounds:
		if float(ground.get("radius")) > 0.0:
			var thick := 2.0 * float(ground.get("radius"))
			var disc_ok := thick >= MIN_THICK - EPS
			print("ISSUE270 ", lvl_name, " disc_thickness=", thick, " ok=", disc_ok)
			ok = ok and disc_ok
			continue
		var eff: Vector2 = ground.call("effective_size")
		var corner := float(ground.call("corner_radius"))
		var offset := float(ground.call("effective_offset"))
		var authored: Vector2 = ground.get("rect_size")
		var thick_ok := eff.y >= MIN_THICK - EPS
		# The walking surface must sit exactly at the authored top face.
		var top_ok := is_equal_approx(
				offset - eff.y / 2.0, -authored.y / 2.0)
		var shape := ground.get_node_or_null("Shape") as CollisionPolygon2D
		var poly_ok := shape != null and shape.polygon.size() >= 16
		var corner_ok := corner >= MIN_CORNER - EPS
		print("ISSUE270 ", lvl_name, " slab=", authored, " eff_h=", eff.y,
			" thick_ok=", thick_ok, " top_face_ok=", top_ok,
			" corner=", corner, " corner_ok=", corner_ok,
			" poly_points=", shape.polygon.size() if shape != null else 0,
			" poly_ok=", poly_ok)
		ok = ok and thick_ok and top_ok and corner_ok and poly_ok

	# --- Separation: gap <= 0 (one landmass) or >= 8 widths. ---
	for i in grounds.size():
		for j in range(i + 1, grounds.size()):
			var gap := _gap(grounds[i], grounds[j])
			var gap_ok := gap <= EPS or gap >= MIN_GAP - EPS
			print("ISSUE270 ", lvl_name, " pair=", i, "-", j,
				" gap=", gap, " ok=", gap_ok)
			ok = ok and gap_ok
	return ok


## Gap between two indestructible masses (0 when they touch or overlap).
## Slabs use their full effective rect — the rounded corners only cut
## material away, so this never overestimates the gap.
func _gap(a: Node2D, b: Node2D) -> float:
	var ra := float(a.get("radius"))
	var rb := float(b.get("radius"))
	var pa := _center(a)
	var pb := _center(b)
	if ra > 0.0 and rb > 0.0:
		return maxf(0.0, pa.distance_to(pb) - ra - rb)
	if ra > 0.0:
		return _circle_rect_gap(pa, ra, _rect(b))
	if rb > 0.0:
		return _circle_rect_gap(pb, rb, _rect(a))
	return _rect_gap(_rect(a), _rect(b))


## World-space centre of a mass (slabs: node origin + the downward
## thickness-guard offset).
func _center(g: Node2D) -> Vector2:
	return g.global_position + Vector2(0.0, float(g.call("effective_offset")))


func _rect(g: Node2D) -> Rect2:
	var eff: Vector2 = g.call("effective_size")
	return Rect2(_center(g) - eff / 2.0, eff)


func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(b.position.x - a.end.x, a.position.x - b.end.x)
	var dy := maxf(b.position.y - a.end.y, a.position.y - b.end.y)
	if dx < 0.0 and dy < 0.0:
		return 0.0
	return Vector2(maxf(dx, 0.0), maxf(dy, 0.0)).length()


func _circle_rect_gap(c: Vector2, r: float, rect: Rect2) -> float:
	var closest := Vector2(clampf(c.x, rect.position.x, rect.end.x),
			clampf(c.y, rect.position.y, rect.end.y))
	return maxf(0.0, closest.distance_to(c) - r)


## Issue #270: gravity must still work with the rounded-rect polygon
## slabs — straight down above the slab, straight up below it.
func _check_gravity(level: Node) -> bool:
	var probe := Node2D.new()
	level.add_child(probe)
	probe.global_position = Vector2(576, 300)
	var above: Vector2 = Terrain.gravity_vector(probe)
	probe.global_position = Vector2(576, 1050)
	var below: Vector2 = Terrain.gravity_vector(probe)
	probe.queue_free()
	var ok := above.y > 0.99 and below.y < -0.99
	print("ISSUE270 gravity above=", above, " below=", below, " ok=", ok)
	return ok
