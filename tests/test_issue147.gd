extends Node
## Regression check for issue #147: computer team members must not shoot
## without aiming. An NPC holds fire until it actually faces the target and
## its view angle has slewed onto the direct line to the target; while the
## aim is still turning no projectile is fired.
##
## Run headless: godot --headless res://tests/test_issue147.tscn
## Exit code 0 = pass.

const NpcScript := preload("res://Npc.gd")


func _ready() -> void:
	var ok := true

	# --- Static check: the hold-fire gate exists. ---
	var npc_script: Script = load("res://Npc.gd")
	var has_gate: bool = not npc_script.get_script_method_list().filter(
			func(m): return m.name == "_aim_ready").is_empty()
	ok = ok and has_gate
	print("ISSUE147 aim_gate_code=", has_gate)

	# --- Behavioral check: an NPC with a mis-turned aim does not fire. ---
	var floor_body := StaticBody2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(4000.0, 40.0)
	floor_body.add_child(floor_shape_helper(floor_rect))
	floor_body.position = Vector2(500.0, 520.0)
	add_child(floor_body)

	var shooter: CharacterBody2D = NpcScript.new()
	shooter.position = Vector2(300.0, 480.0)
	# Force a clearly wrong aim (pointing up instead of flat at the target).
	shooter.view_angle = 1.2
	add_child(shooter)

	var target: CharacterBody2D = NpcScript.new()
	target.position = Vector2(700.0, 480.0)
	target.add_to_group("enemy_team")  # placeholder; fixed below
	add_child(target)
	# Make them opposing sides.
	shooter.remove_from_group("enemy_team")
	shooter.add_to_group("player_team")
	target.remove_from_group("enemy_team")
	target.add_to_group("enemy_team")
	# Normally _physics_process picks the target each frame; point at it
	# directly so the gate can be probed without physics.
	shooter._target = target

	# Assign the acquired target explicitly: _aim_ready() judges against
	# shooter._target, which is only populated by in-game targeting frames.
	shooter._target = target

	# The shooter must consider the enemy a target but hold fire while the
	# aim is far off.
	var sees_target: bool = shooter._nearest_opponent() == target
	var gate_blocks: bool = not shooter._aim_ready()
	ok = ok and sees_target and gate_blocks
	print("ISSUE147 sees_target=", sees_target, " gate_blocks=", gate_blocks)

	# With the view angle slewed onto the target, the gate opens.
	shooter.view_angle = 0.0
	var gate_open: bool = shooter._aim_ready()
	ok = ok and gate_open
	print("ISSUE147 gate_open_when_aimed=", gate_open)

	# Firing away from the target stays blocked even with a good angle.
	shooter.view_angle = 0.0
	shooter._weapon._facing = -1.0
	var gate_blocks_backshots: bool = not shooter._aim_ready()
	ok = ok and gate_blocks_backshots
	print("ISSUE147 gate_blocks_backshots=", gate_blocks_backshots)

	print("ISSUE147 ok=", ok)
	get_tree().quit(0 if ok else 1)


func floor_shape_helper(shape: RectangleShape2D) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	cs.shape = shape
	return cs
