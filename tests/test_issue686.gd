extends Node
## Regression check for issue #686: a ROCKET (contact-fused) detonating
## on destructible ground used to carve it from inside the body_entered
## physics callback — adding collision shapes while the space was still
## flushing queries, which Godot rejects with "Can't change this state
## while flushing queries" (body_set_shape_as_one_way_collision). The
## detonation is now deferred out of the physics flush. This drives the
## REAL contact path — a rocket flies into soil and explodes on touch —
## and checks the carve landed and the rocket is gone.
##
## Run headless: godot --headless res://tests/test_issue686.tscn
## Exit code 0 = pass.

const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")


func _ready() -> void:
	var ok := await _rocket_contact_carves_soil()
	print("ISSUE686 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Fire a rocket straight into a soil chunk: body_entered must fire
## during the physics step, the deferred detonation must then carve the
## chunk (it splits into leftover pieces) and free the rocket.
func _rocket_contact_carves_soil() -> bool:
	var soil := DestructibleGround.new()
	soil.rect_size = Vector2(200, 60)
	soil.position = Vector2(300, 300)
	add_child(soil)
	var rocket := RigidBody2D.new()
	rocket.set_script(ProjectileBodyScript)
	rocket.setup(ProjectileBody.Kind.ROCKET, Vector2(0, 400), 0, 3.0,
		Vector2(14, 14), Color(0.8, 0.3, 0.2, 1), 60.0, 0.8)
	add_child(rocket)
	# Straight above the soil: the launch speed drives it into the top
	# edge; the rocket is contact-fused, so body_entered must fire there.
	rocket.global_position = soil.position + Vector2(0, -120.0)
	# Wait for the contact detonation to run its course (deferred carve,
	# queue_free) — with a budget so a never-exploding rocket FAILS
	# instead of hanging the suite.
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(rocket) or rocket.is_queued_for_deletion():
			break
	var exploded := not is_instance_valid(rocket) \
			or rocket.is_queued_for_deletion()
	var pieces: Array = get_tree().get_nodes_in_group("destructible_ground")
	var carved := pieces.size() != 1
	print("ISSUE686 rocket exploded=", exploded,
		" soil pieces=", pieces.size(), " (1 = carve failed)")
	return exploded and carved
