extends Node
## Regression check for issue #236: rework ground types.
##
## Asserts, for every playable level:
##   - every StaticBody2D (every piece of ground) is one of the TWO ground
##     types — DestructibleGround or IndestructibleGround — never a bare
##     untyped StaticBody2D with hand-authored shape/visual children;
##   - every gravity source is an IndestructibleGround, and every level
##     HAS one — gravity in a level comes only from indestructible ground;
##   - ground nodes carry no hand-authored ColorRect visuals (the typed
##     grounds draw themselves in their type color);
##   - destructible ground is brown and indestructible ground is purple.
##
## Run headless: godot --headless res://tests/test_issue236.tscn
## Exit code 0 = pass.

const DestructibleScript := preload("res://scripts/DestructibleGround.gd")
const IndestructibleScript := preload("res://scripts/IndestructibleGround.gd")

const LEVELS := [
	"res://Level.tscn",
	"res://Level2.tscn",
	"res://Level3.tscn",
	"res://Level4.tscn",
	"res://LevelDuel.tscn",
]


func _ready() -> void:
	var ok := true

	# --- The two type colors: brown destructible, purple indestructible. ---
	var brown: Color = DestructibleScript.COLOR
	var purple: Color = IndestructibleScript.COLOR
	if not brown.r > brown.b:
		ok = false
		print("ISSUE236 FAIL destructible ground must be brown, got ", brown)
	if not purple.b > purple.r:
		ok = false
		print("ISSUE236 FAIL indestructible ground must be purple, got ", purple)
	print("ISSUE236 colors brown=", brown, " purple=", purple)

	for path in LEVELS:
		var level: Node = (load(path) as PackedScene).instantiate()
		add_child(level)
		for i in 10:
			await get_tree().physics_frame

		# --- Every StaticBody2D is one of the two ground types. ---
		for body in level.find_children("*", "StaticBody2D", true, false):
			var script: Script = body.get_script()
			if script != DestructibleScript and script != IndestructibleScript:
				ok = false
				print("ISSUE236 FAIL ", path, ":", body.name,
					" is an untyped ground StaticBody2D")
			# No hand-authored visuals on typed ground: the script draws it.
			for child in body.get_children():
				if child is ColorRect:
					ok = false
					print("ISSUE236 FAIL ", path, ":", body.name,
						" still carries a ColorRect visual child")

		# --- Gravity sources are exactly the indestructible grounds. ---
		var sources: Array = get_tree().get_nodes_in_group("gravity_source")
		if sources.is_empty():
			ok = false
			print("ISSUE236 FAIL ", path, " has no gravity source at all")
		for source in sources:
			if source.get_script() != IndestructibleScript:
				ok = false
				print("ISSUE236 FAIL ", path, ":", source.name,
					" is a gravity source but not IndestructibleGround")
		for soil in get_tree().get_nodes_in_group("destructible_ground"):
			if soil.get_script() != DestructibleScript:
				ok = false
				print("ISSUE236 FAIL ", path, ":", soil.name,
					" is destructible_ground but not DestructibleGround")
		print("ISSUE236 ", path, " grounds typed, gravity sources=",
			sources.size())

		level.queue_free()
		for i in 5:
			await get_tree().physics_frame

	print("ISSUE236 ok=", ok)
	get_tree().quit(0 if ok else 1)
