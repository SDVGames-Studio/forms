extends Node
## Regression check for issue #375 — new item creation rules:
##  - equal probability at any point: every walkable surface unit of
##    every ground type has the same chance of hosting a new item — two
##    identical slabs share the creations about evenly, and a disc / a
##    whole ring join with exactly their circumference's share;
##  - on any type of ground: every created item starts right ON a
##    ground surface (slab top face, disc circle, ring outer arc —
##    destructible sectors included);
##  - 25% round drop: wrapping the turn order many times (fixed seed)
##    creates the round drop in about a quarter of the wraps, never in
##    all of them (it was 100% before issue #375).
##
## Run headless: godot --headless res://tests/test_issue375.tscn
## Exit code 0 = pass.

const ROLLS := 2400
const WRAPS := 400

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE375 %s — %s" % ["ok" if ok else "FAIL", what])


## Distance from a point to the walkable surface of one ground piece of
## the synthetic arena — the top-face segment of a slab / rect chunk,
## the circle of a disc, the outer circle of a ring. The on-surface
## check and the share counting both use it.
func _surface_distance(ground: Node2D, pos: Vector2) -> float:
	var radius = ground.get("radius")
	if radius is float and float(radius) > 0.0:
		return absf(pos.distance_to(ground.global_position) - float(radius))
	var ring_outer = ground.get("ring_outer")
	if ring_outer is float and float(ring_outer) > 0.0:
		return absf(pos.distance_to(ground.global_position)
				- float(ring_outer))
	var size: Vector2 = ground.get("rect_size")
	var top := ground.global_position + Vector2(0.0, -size.y / 2.0)
	var cx := clampf(pos.x, top.x - size.x / 2.0, top.x + size.x / 2.0)
	return Vector2(cx, top.y).distance_to(pos)


func _ready() -> void:
	_check("the round-drop chance is 25% (was 100%)",
		is_equal_approx(TurnController.ROUND_DROP_CHANCE, 0.25))

	# 1) The synthetic arena: two identical slabs (500 px of top face
	# each), a 224-radius disc (full circle = ~1407 px) and a 250..300
	# ring (24 destructible sector chunks, outer arcs = ~1885 px).
	var arena := Node2D.new()
	add_child(arena)
	var slab_a := IndestructibleGround.new()
	slab_a.rect_size = Vector2(500, 200)
	slab_a.position = Vector2(-900, 0)
	arena.add_child(slab_a)
	var slab_b := IndestructibleGround.new()
	slab_b.rect_size = Vector2(500, 200)
	slab_b.position = Vector2(300, 0)
	arena.add_child(slab_b)
	var disc := IndestructibleGround.new()
	disc.radius = 224.0
	disc.position = Vector2(-300, -1000)
	arena.add_child(disc)
	var ring := DestructibleGround.new()
	ring.ring_inner = 250.0
	ring.ring_outer = 300.0
	ring.position = Vector2(900, 600)
	arena.add_child(ring)
	await get_tree().physics_frame

	# 2) Equal shares: with the fixed seed the creations must spread by
	# surface length — every surface unit, on every ground type, gets
	# the same chance. Each item must start right ON some surface
	# (half the 64 px body + a 2 px hair above it).
	seed(375)
	var counts := {"a": 0, "b": 0, "disc": 0, "ring": 0}
	var surfaces: Array = [
		{"key": "a", "node": slab_a},
		{"key": "b", "node": slab_b},
		{"key": "disc", "node": disc},
		{"key": "ring", "node": ring},
	]
	var off_surface := 0
	for i in ROLLS:
		var item := LevelItems.spawn_random_item(arena)
		if item == null:
			_check("spawn returns an item on a real arena", false)
			_finish()
			return
		var best_key := ""
		var best_dist := 1e9
		for s in surfaces:
			var d := _surface_distance(s["node"], item.global_position)
			if d < best_dist:
				best_dist = d
				best_key = s["key"]
		if best_dist < 30.0 or best_dist > 38.0:
			off_surface += 1
		counts[best_key] = int(counts[best_key]) + 1
		item.queue_free()
		if i % 200 == 199:
			await get_tree().physics_frame
	await get_tree().physics_frame
	_check("every created item starts right on a ground surface",
		off_surface == 0)
	var len_a := 500.0
	var len_disc := TAU * 224.0
	var len_ring := TAU * 300.0
	var total_len := len_a * 2.0 + len_disc + len_ring
	var shares := {
		"a": len_a / total_len,
		"b": len_a / total_len,
		"disc": len_disc / total_len,
		"ring": len_ring / total_len,
	}
	for key in shares:
		_check("%s gets its surface-length share of the creations" % key,
			absf(float(counts[key]) / ROLLS - float(shares[key])) < 0.05)
	_check("two identical slabs share the creations evenly",
		absf(int(counts["a"]) - int(counts["b"])) < 0.08 * ROLLS)
	arena.queue_free()
	await get_tree().physics_frame

	# 3) Level scene: wait for the player's turn (an enemy team may move
	# first), like test_issue364.
	var level: Node = load("res://Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	var player_turn := false
	for i in 3600:
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			player_turn = true
			break
	if not player_turn:
		print("ISSUE375 no player turn — ok=false")
		get_tree().quit(1)
		return

	# 4) The 25% round drop: WRAPS seeded wraps — each roll must fire in
	# about a quarter of them, and never in all of them. The group-size
	# delta is read right after each synchronous wrap call, so pickups
	# and resting items cannot distort the count.
	seed(375)
	var drops := 0
	for i in WRAPS:
		var before := get_tree().get_nodes_in_group("level_items").size()
		tc._turn_index = tc._turn_order.size() - 1
		tc._next_alive_team()
		if get_tree().get_nodes_in_group("level_items").size() > before:
			drops += 1
	_check("the round drop is probabilistic (no longer every round)",
		drops > 0 and drops < WRAPS)
	_check("the round drop fires in about a quarter of the wraps",
		drops >= 40 and drops <= 160)

	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE375 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE375 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
