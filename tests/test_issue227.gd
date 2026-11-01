extends Node
## Regression check for issue #227: the Rock tool. A thrown rock never
## explodes — on its fuse it crumbles into a disk of destructible ground
## (radius a little over a grenade blast) that keeps 1.3 x the figure
## shape size of clearance around every character and never overlaps
## indestructible ground (it borders it instead).
##
## Run headless: godot --headless res://tests/test_issue227.tscn
## Exit code 0 = pass.

const ProjectileBodyScript := preload("res://ProjectileBody.gd")

## Same value as ProjectileBody.ROCK_CHAR_CLEAR (1.3 x the 64 px shape).
const CLEAR := 1.3 * 64.0


func _ready() -> void:
	var ok := true
	# Registration: the fourth tool and the throw hook on the weapon.
	ok = ok and ToolInventory.TOOLS.size() >= 4 and ToolInventory.TOOLS[3] == "Rock"
	print("ISSUE227 tools=", ToolInventory.TOOLS)

	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 10:
		await get_tree().physics_frame
	var player: Node = get_tree().get_first_node_in_group("player_team")
	ok = ok and player != null \
			and player.get_node("Weapon").has_method("throw_rock")
	print("ISSUE227 throw_rock hook=", ok)

	var chars: Array = []
	chars.append_array(get_tree().get_nodes_in_group("player_team"))
	chars.append_array(get_tree().get_nodes_in_group("enemy_team"))

	# Crumble one rock mid-air above the figures (figure clearance) and one
	# next to the indestructible hill disc (border instead of overlap).
	# Open air above the figures: a healthy disk of soil must appear.
	ok = ok and await _check_crumble(level, Vector2(576, 330), chars, 5)
	# Tight spot beside the hill disc: the disc, the soil slab below and
	# the figure clearance each bite into the disk, so fewer strips
	# survive — every survivor must still obey all three issue rules.
	ok = ok and await _check_crumble(level, Vector2(380, 380), chars, 3)
	print("ISSUE227 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Crumble a rock at `at` and verify every spawned soil strip obeys the
## issue rules: inside the radius, clear of characters, never overlapping
## indestructible ground (slab or disc).
func _check_crumble(level: Node, at: Vector2, chars: Array, min_soil: int) -> bool:
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
	print("ISSUE227 crumble at ", at, " new_soil=", fresh.size())
	var good := fresh.size() >= min_soil
	for chunk in fresh:
		var rect := Rect2(chunk.position - chunk.rect_size / 2.0, chunk.rect_size)
		if chunk.position.distance_to(at) > ProjectileBody.ROCK_GROUND_RADIUS:
			print("ISSUE227 FAIL outside the rock radius: ", chunk.position)
			good = false
		for c in chars:
			if _rect_distance(rect, c.global_position) < CLEAR - 0.01:
				print("ISSUE227 FAIL inside figure clearance: ", chunk.position)
				good = false
		for node in get_tree().get_nodes_in_group("indestructible_ground"):
			var g := node as IndestructibleGround
			if g == null:
				continue
			if g.radius > 0.0:
				if _rect_distance(rect, g.position) < g.radius - 0.01:
					print("ISSUE227 FAIL overlaps the hill disc: ", chunk.position)
					good = false
			else:
				var solid := Rect2(g.position - g.rect_size / 2.0, g.rect_size)
				if rect.intersects(solid):
					print("ISSUE227 FAIL overlaps an indestructible slab: ",
						chunk.position)
					good = false
	return good


## Distance from `point` to the closest point of `rect` (0 when inside).
func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var closest := Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y))
	return closest.distance_to(point)
