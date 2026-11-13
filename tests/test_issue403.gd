extends Node
## Regression check for issue #403 — created items must never appear
## inside the indestructible ground. Overlapping masses are legal level
## authoring (issue #270 counts touching/overlapping masses as ONE
## landmass; Level.tscn half-buries a disc in its main slab), and the
## round drop used to draw ANY surface point — including disc arcs and
## top faces buried inside a neighbour mass — so items appeared buried
## inside the ground, unreachable and invisible.
##
## Run headless: godot --headless res://tests/test_issue403.tscn
## Exit code 0 = pass.

const ROLLS := 400

var _fails: Array = []
var _arena: Node2D


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE403 %s — %s" % ["ok" if ok else "FAIL", what])


## The same five probe points the spawn check uses: the item's centre
## plus four points just inside its 64 px edges. None may touch a
## ground collision body.
func _clear_of_ground(pos: Vector2) -> bool:
	var space := _arena.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1
	var reach := LevelItem.SIZE / 2.0 - 4.0
	var probes: Array[Vector2] = [pos,
			pos + Vector2(reach, 0.0), pos + Vector2(-reach, 0.0),
			pos + Vector2(0.0, reach), pos + Vector2(0.0, -reach)]
	for probe in probes:
		query.position = probe
		if not space.intersect_point(query, 1).is_empty():
			return false
	return true


func _ready() -> void:
	# 1) The bug arena: a wide slab with a disc half-embedded in it (the
	# Level.tscn layout) and a second slab stacked on the first — three
	# legal landmasses whose buried surface stretches are exactly where
	# created items used to appear inside the ground.
	var arena := Node2D.new()
	add_child(arena)
	_arena = arena
	var slab := IndestructibleGround.new()
	slab.rect_size = Vector2(900, 448)
	slab.position = Vector2(0, 0)
	arena.add_child(slab)
	var disc := IndestructibleGround.new()
	disc.radius = 224.0
	disc.position = Vector2(-320, -60)
	arena.add_child(disc)
	var stack := IndestructibleGround.new()
	stack.rect_size = Vector2(300, 448)
	stack.position = Vector2(200, -448)
	arena.add_child(stack)
	await get_tree().physics_frame

	# 2) Every created item must sit clear of every ground piece, and
	# the exposed surfaces must still host drops.
	seed(403)
	var spawned := 0
	var buried := 0
	for i in ROLLS:
		var item := LevelItems.spawn_random_item(arena)
		if item == null:
			continue
		spawned += 1
		if not _clear_of_ground(item.global_position):
			buried += 1
		item.queue_free()
		if i % 100 == 99:
			await get_tree().physics_frame
	_check("items still appear on the overlapping arena", spawned > 50)
	_check("no item appears inside the ground", buried == 0)
	arena.queue_free()
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE403 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE403 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
