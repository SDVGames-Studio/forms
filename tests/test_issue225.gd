extends Node
## Regression check for issue #225: every level ships destructible ground
## that explosions carve chunk by chunk (DestructibleGround.apply_blast).
##
## Run headless: godot --headless res://tests/test_issue225.tscn
## Exit code 0 = pass.

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
	print("ISSUE225 ok=", ok)
	get_tree().quit(0 if ok else 1)
