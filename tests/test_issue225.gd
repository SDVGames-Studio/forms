extends Node
## Regression check for issue #225: every level ships destructible ground
## that explosions carve chunk by chunk (DestructibleGround.apply_blast),
## and a REAL grenade (ProjectileBody) explosion carves it too.
##
## Run headless: godot --headless res://tests/test_issue225.tscn
## Exit code 0 = pass.

const ProjectileBodyScript := preload("res://ProjectileBody.gd")

const LEVELS := {
	"res://Level.tscn": 2,
	"res://Level2.tscn": 2,
	"res://Level3.tscn": 1,
	"res://Level4.tscn": 2,
	"res://LevelDuel.tscn": 1,
}


func _ready() -> void:
	var ok := true
	for path in LEVELS:
		var level: Node = load(path).instantiate()
		add_child(level)
		for i in 10:
			await get_tree().physics_frame
		var soil := get_tree().get_nodes_in_group("destructible_ground")
		var expected: int = LEVELS[path]
		print("ISSUE225 ", path, " destructible=", soil.size(),
			" expected>=", expected)
		ok = ok and soil.size() >= expected
		# Blast the first chunk at its top edge: it must split into leftover
		# strips instead of vanishing or staying whole.
		if not soil.is_empty():
			var chunk = soil[0]
			var before: int = soil.size()
			chunk.apply_blast(
				chunk.global_position + Vector2(0, -chunk.rect_size.y / 2.0),
				40.0)
			for i in 5:
				await get_tree().physics_frame
			var after: int = get_tree().get_nodes_in_group(
				"destructible_ground").size()
			print("ISSUE225 ", path, " blast before=", before,
				" after=", after)
			ok = ok and after != before
		level.queue_free()
		for i in 5:
			await get_tree().physics_frame
	ok = ok and await _grenade_carves_soil()
	print("ISSUE225 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Rework #225: a real grenade (ProjectileBody — the physics projectile
## Weapon.gd fires) must carve soil when it explodes. The original run
## only exercised DestructibleGround.apply_blast directly, so the carve
## was missing from the actual grenade/rocket explosion path.
func _grenade_carves_soil() -> bool:
	var soil := DestructibleGround.new()
	soil.rect_size = Vector2(200, 60)
	soil.position = Vector2(300, 300)
	add_child(soil)
	var grenade := RigidBody2D.new()
	grenade.set_script(ProjectileBodyScript)
	grenade.setup(ProjectileBody.Kind.GRENADE, Vector2.ZERO, 0, 3.0,
		Vector2(14, 14), Color(0.3, 0.7, 0.3, 1), 60.0, 0.6)
	add_child(grenade)
	# Resting 8 px above the soil's top edge: the blast box overlaps the
	# chunk, so it must split into leftover strips instead of staying whole.
	grenade.global_position = soil.position + Vector2(0, -38.0)
	grenade._explode()
	for i in 5:
		await get_tree().physics_frame
	var pieces: Array = get_tree().get_nodes_in_group("destructible_ground")
	var carved := pieces.size() != 1
	print("ISSUE225 grenade explosion soil pieces=", pieces.size(),
		" (1 = carve failed)")
	for piece in pieces:
		piece.queue_free()
	return carved
