extends Node
## Regression check for issue #154: a character could get permanently stuck
## when wedged between the ground and another figure/wall — the round
## (circle) collision shape caught in the notch. All character collision
## shapes are now capsules (flat sides slide along obstacles).
##
## Run headless: godot --headless res://tests/test_issue154.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true

	# --- Static check: every character shape in every level is a capsule. ---
	for level_path in ["res://Level.tscn", "res://Level2.tscn",
			"res://Level3.tscn", "res://LevelDuel.tscn"]:
		var scene: PackedScene = load(level_path)
		var root := scene.instantiate()
		add_child(root)
		for body in root.find_children("*", "CharacterBody2D", true, false):
			for child in body.get_children():
				var col := child as CollisionShape2D
				if col != null and col.shape != null:
					var capsule := col.shape is CapsuleShape2D
					if not capsule:
						ok = false
						print("ISSUE154 not_capsule ", level_path, " ", body.name)
		# Npc.gd builds its own shape in _ready — covered by the same scan.
		root.queue_free()
	print("ISSUE154 all_character_shapes_capsules=", ok)

	print("ISSUE154 ok=", ok)
	get_tree().quit(0 if ok else 1)
