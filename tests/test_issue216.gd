extends Node
## Regression check for issue #216: the level's gravity affects a grenade.
##
## The grenade is a ProjectileBody rigid body. Before #216 it used the
## engine's gravity_scale (straight down, world space) so on levels with
## terrain gravity sources (curved hills, ceilings) grenades fell the
## WRONG way — unlike the figures. Now the grenade uses the figures'
## gravity rule (issue #293): the level's indestructible grounds are the
## only gravity source, otherwise plain down.
##
## Run headless: godot --headless res://tests/test_issue216.tscn
## Exit code 0 = pass.

const GrenadeScript := preload("res://ProjectileBody.gd")
const GroundScript := preload("res://scripts/IndestructibleGround.gd")

func _spawn_grenade() -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(GrenadeScript)
	# Zero launch velocity, harmless damage, long fuse — only gravity moves it.
	body.setup(ProjectileBody.Kind.GRENADE, Vector2.ZERO, 0, 60.0,
		Vector2(14, 14), Color.WHITE, 0.0, 0.6)
	add_child(body)
	return body


func _ready() -> void:
	var ok := true

	# --- A level without gravity sources: the grenade falls DOWN. ---
	var a := _spawn_grenade()
	var a_start := a.global_position.y
	for i in 20:
		await get_tree().physics_frame
	var fell_down: bool = a.global_position.y > a_start + 10.0
	print("ISSUE216 fell_down=", fell_down, " y=", a.global_position.y)
	ok = ok and fell_down
	a.queue_free()
	await get_tree().physics_frame

	# --- A ceiling gravity source ABOVE: terrain gravity pulls UP. ---
	var ceiling := StaticBody2D.new()
	ceiling.set_script(GroundScript)
	ceiling.rect_size = Vector2(600, 40)
	ceiling.position = Vector2(0, -200)
	add_child(ceiling)
	var b := _spawn_grenade()
	var b_start := b.global_position.y
	for i in 20:
		await get_tree().physics_frame
	var rose_up: bool = b.global_position.y < b_start - 10.0
	print("ISSUE216 rose_up=", rose_up, " y=", b.global_position.y)
	ok = ok and rose_up
	b.queue_free()
	ceiling.queue_free()
	await get_tree().physics_frame

	# --- Issue #293: no separately configured gravity remains — with no
	# terrain source the grenade falls DOWN even far below where a
	# central line used to flip gravity. ---
	var c := _spawn_grenade()
	c.global_position = Vector2(0, 200)
	var c_start := c.global_position.y
	for i in 20:
		await get_tree().physics_frame
	var no_flip: bool = c.global_position.y > c_start + 10.0
	print("ISSUE216 no_flip_falls_down=", no_flip, " y=", c.global_position.y)
	ok = ok and no_flip

	print("ISSUE216 ok=", ok)
	get_tree().quit(0 if ok else 1)
