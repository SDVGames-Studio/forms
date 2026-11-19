extends Node
## Regression check for issue #657: a dedicated, simplified training
## arena for curriculum learning.
##
## DoD coverage:
##  - the arena is an ENCLOSED flat rectangle: one indestructible floor
##    slab flanked by two side walls (plain StaticBody2D, terrain layer
##    1) that rise unjumpably above the floor, so an agent can never
##    wander off the slab and stall the episode in the void;
##  - the walls are NOT gravity sources — the floor slab stays the
##    arena's only gravity source (issue #190 single-source rule);
##  - the two teams are staged within 200 px of each other (agents
##    spawn inside firing range, issue acceptance);
##  - training_scene.tscn keeps its NcnnSync root and one BotController
##    per instanced arena environment, each bound to that environment's
##    Player figure (issue task 6).
##
## Run headless: godot --headless res://tests/test_issue657.tscn
## Exit code 0 = pass.

const BOT_PATH := "res://scripts/BotController.gd"
const SYNC_PATH := "res://addons/godot_native_rl/sync.gd"

## Max jump apex: JUMP_VELOCITY² / (2 * GRAVITY) ≈ 131 px (CharacterStats);
## no backflip exists in the move set yet (BotController issue #607 note).
const MIN_WALL_RISE := 300.0

func _ready() -> void:
	var ok := true
	ok = _test_enclosure() and ok
	ok = _test_wiring() and ok
	print("ISSUE657 ok=", ok)
	get_tree().quit(1 if not ok else 0)

## The arena floor is flanked by enclosing, unjumpable, non-gravity walls.
func _test_enclosure() -> bool:
	var ok := true
	var arena: Node2D = load(
			"res://scenes/testing/TrainingArena.tscn").instantiate()

	var floor_node: Node2D = null
	var walls: Array = []
	var figures := {}
	for child in arena.get_children():
		var script: Script = child.get_script()
		if script != null and script.resource_path \
				== "res://scripts/IndestructibleGround.gd":
			floor_node = child
		elif child is StaticBody2D and child.get_script() == null:
			walls.append(child)
		elif script != null and script.resource_path \
				== "res://scripts/Character.gd":
			figures[str(child.name)] = child

	ok = _expect(floor_node != null,
			"the arena has its indestructible floor slab") and ok
	if floor_node == null:
		arena.free()
		return ok
	var floor_top: float = floor_node.position.y \
			- floor_node.rect_size.y / 2.0
	var floor_left: float = floor_node.position.x \
			- floor_node.rect_size.x / 2.0
	var floor_right: float = floor_node.position.x \
			+ floor_node.rect_size.x / 2.0

	ok = _expect(walls.size() == 2,
			"the floor is flanked by exactly two walls, got %d"
					% walls.size()) and ok
	walls.sort_custom(func(a, b): return a.position.x < b.position.x)
	if walls.size() == 2:
		var left: StaticBody2D = walls[0]
		var right: StaticBody2D = walls[1]
		var left_shape: CollisionShape2D = left.get_node_or_null("Shape")
		var right_shape: CollisionShape2D = right.get_node_or_null("Shape")
		ok = _expect(left_shape != null and right_shape != null,
				"both walls carry a collision shape") and ok
		if left_shape != null and right_shape != null \
				and left_shape.shape is RectangleShape2D \
				and right_shape.shape is RectangleShape2D:
			var left_rect: RectangleShape2D = left_shape.shape
			var right_rect: RectangleShape2D = right_shape.shape
			ok = _expect(left.position.x + left_rect.size.x / 2.0
					<= floor_left + 0.5,
					"the left wall seals the floor's left edge") and ok
			ok = _expect(right.position.x - right_rect.size.x / 2.0
					>= floor_right - 0.5,
					"the right wall seals the floor's right edge") and ok
			for wall in [left, right]:
				var shape: CollisionShape2D = \
						wall.get_node("Shape") as CollisionShape2D
				var rect: RectangleShape2D = shape.shape
				ok = _expect(wall.position.y - rect.size.y / 2.0
						<= floor_top - MIN_WALL_RISE,
						"%s rises unjumpably (>= %.0f px) above the floor"
						% [wall.name, MIN_WALL_RISE]) and ok
				ok = _expect(wall.collision_layer == 1,
						"%s rides the terrain layer 1" % wall.name) and ok

	# The floor slab stays the ONLY gravity source: walls are plain
	# StaticBody2D bodies (no IndestructibleGround script ⇒ they never
	# join the gravity_source group and cannot bend training gravity).
	var gravity_sources := 0
	for child in arena.get_children():
		var script: Script = child.get_script()
		if script != null and script.resource_path \
				== "res://scripts/IndestructibleGround.gd":
			gravity_sources += 1
	ok = _expect(gravity_sources == 1,
			"the floor stays the arena's only gravity source, got %d"
					% gravity_sources) and ok

	# Teams staged within firing range, figures inside the walled corridor.
	if figures.has("Player") and figures.has("Team2mate1"):
		var gap: float = (figures["Player"] as Node2D).position.distance_to(
				(figures["Team2mate1"] as Node2D).position)
		ok = _expect(gap <= 200.0,
				"the staged teams are within 200 px, got %.0f" % gap) and ok
	for fig in figures.values():
		var x: float = (fig as Node2D).position.x
		ok = _expect(x > floor_left and x < floor_right,
				"figure at x=%.0f spawns inside the walled corridor" % x) and ok

	arena.free()
	return ok

## training_scene keeps NcnnSync + one BotController per environment,
## each bound to its own environment's Player figure. Pinned on the
## scene text (the same convention test_issue659 uses) — instantiating
## the scene would boot the ncnn stack, which a unit check must not do.
func _test_wiring() -> bool:
	var ok := true
	var text := FileAccess.get_file_as_string(
			"res://scenes/testing/training_scene.tscn")
	ok = _expect(text.contains('path="%s"' % SYNC_PATH)
			and text.contains('[node name="NcnnSync"'),
			"the NcnnSync root is attached with the ncnn sync script") and ok
	var environments := text.count('[node name="Environment_')
	ok = _expect(environments == 3,
			"three arena environments are instanced, got %d"
					% environments) and ok
	var bots := text.count('[node name="Bot"')
	ok = _expect(bots == environments,
			"every environment carries its own Bot node, got %d of %d"
					% [bots, environments]) and ok
	ok = _expect(text.contains('path="%s"' % BOT_PATH),
			"the Bot nodes run BotController.gd") and ok
	var bindings := text.count('figure_path = NodePath("../Player")')
	ok = _expect(bindings == environments,
			"every Bot is bound to its environment's Player figure, got %d of %d"
					% [bindings, environments]) and ok
	return ok

func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
