extends Node
## Regression check for issue #245: the rocket has weight and is affected
## by gravity, while keeping the launch speed the character gave it.
##
## Before #245 the rocket was the only ProjectileBody with gravity OFF —
## it flew dead straight no matter the level. Now it obeys the same
## terrain gravity rule as the grenade (issue #216) and the figures
## (issue #293: indestructible grounds are the only gravity source), and
## its launch velocity is still applied in full as the starting velocity.
##
## Run headless: godot --headless res://tests/test_issue245.tscn
## Exit code 0 = pass.

const RocketScript := preload("res://ProjectileBody.gd")
const GroundScript := preload("res://scripts/IndestructibleGround.gd")

func _spawn_rocket(velocity: Vector2) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(RocketScript)
	# Zero-damage, no blast, long fuse — only flight physics is tested.
	body.setup(ProjectileBody.Kind.ROCKET, velocity, 0, 60.0,
		Vector2(22, 8), Color.WHITE, 0.0, 1.0)
	add_child(body)
	return body


func _ready() -> void:
	var ok := true

	# --- No launch speed: the rocket simply falls DOWN. ---
	var a := _spawn_rocket(Vector2.ZERO)
	var a_start := a.global_position.y
	for i in 20:
		await get_tree().physics_frame
	var fell_down: bool = a.global_position.y > a_start + 10.0
	print("ISSUE245 fell_down=", fell_down, " y=", a.global_position.y)
	ok = ok and fell_down
	a.queue_free()
	await get_tree().physics_frame

	# --- Launch speed kept: fired right at 400 px/s it still travels right
	# while falling — initial speed plus gravity, not gravity alone. ---
	var b := _spawn_rocket(Vector2(400.0, 0.0))
	var b_start := b.global_position
	for i in 20:
		await get_tree().physics_frame
	var moved_right: bool = b.global_position.x > b_start.x + 60.0
	var b_fell: bool = b.global_position.y > b_start.y + 10.0
	print("ISSUE245 moved_right=", moved_right, " fell=", b_fell,
		" x=", b.global_position.x, " y=", b.global_position.y)
	ok = ok and moved_right and b_fell
	b.queue_free()
	await get_tree().physics_frame

	# --- Issue #293: an indestructible ceiling above inverts the rocket's
	# gravity — terrain, not an authored central line, decides the side. ---
	var ceiling := StaticBody2D.new()
	ceiling.set_script(GroundScript)
	ceiling.rect_size = Vector2(600, 40)
	ceiling.position = Vector2(0, -200)
	add_child(ceiling)
	var c := _spawn_rocket(Vector2.ZERO)
	# The #270 thickness guard extends the 40px ceiling down to 448px
	# (slab y -220..228), so start clearly BELOW the solid: the rocket
	# must rise toward the ground above it.
	c.global_position = Vector2(0, 400)
	var c_start := c.global_position.y
	for i in 20:
		await get_tree().physics_frame
	var inverted: bool = c.global_position.y < c_start - 10.0
	print("ISSUE245 inverted=", inverted, " y=", c.global_position.y)
	ok = ok and inverted
	c.queue_free()
	ceiling.queue_free()
	await get_tree().physics_frame

	print("ISSUE245 ok=", ok)
	get_tree().quit(0 if ok else 1)
