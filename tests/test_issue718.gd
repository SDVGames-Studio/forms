extends Node
## Regression check for issue #718 (roadmap part 3c — impact, explosion
## and hit effects): the shared CartoonBlast component animates and
## frees itself, damaged figures pop exactly one rate-limited comic hit
## star, and the legacy Projectile explosion path spawns the fireball
## on the level root.
##
## Run headless: godot --headless res://tests/test_issue718.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	ok = await _check_blast_self_free() and ok
	ok = await _check_hit_star_on_character() and ok
	ok = await _check_projectile_explosion() and ok
	print("ISSUE718 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


## CartoonBlast children of the test root, by mode.
func _count_mode(want_mode: int) -> int:
	var n := 0
	for child in get_children():
		var fx := child as CartoonBlast
		if fx != null and fx.mode == want_mode:
			n += 1
	return n


## 1. Both modes animate (progress leaves 0) and free themselves when
## the animation ends — nothing lingers over the field.
func _check_blast_self_free() -> bool:
	var blast := CartoonBlast.pop(self, Vector2(100, 100), 80.0)
	var hit := CartoonBlast.pop_hit(self, Vector2(200, 100), 1.2)
	await get_tree().process_frame
	await get_tree().process_frame
	var animated: bool = blast.progress > 0.0 and hit.progress > 0.0
	# BLAST_TIME is the longer of the two lives; past it + margin both
	# nodes must be gone.
	await get_tree().create_timer(CartoonBlast.BLAST_TIME + 0.3).timeout
	var freed: bool = not is_instance_valid(blast) and not is_instance_valid(hit)
	var ok := animated and freed \
			and _count_mode(CartoonBlast.Mode.BLAST) == 0 \
			and _count_mode(CartoonBlast.Mode.HIT) == 0
	print("ISSUE718 blast/hit self-free: animated=", animated,
		" freed=", freed, " ok=", ok)
	return ok


## 2. A real figure pops exactly ONE comic hit star when damaged; an
## immediate second chunk (jackhammer/saw grinder ticks) is suppressed
## by the per-figure rate limit; a hit after the interval pops again.
func _check_hit_star_on_character() -> bool:
	var player := CharacterBody2D.new()
	player.set_script(load("res://scripts/Player.gd"))
	add_child(player)
	await get_tree().process_frame
	player.take_damage(30)
	await get_tree().process_frame
	var first: bool = _count_mode(CartoonBlast.Mode.HIT) == 1
	player.take_damage(1)
	await get_tree().process_frame
	var limited: bool = _count_mode(CartoonBlast.Mode.HIT) == 1
	# Past both the star's life (0.22 s) and the rate-limit interval
	# (380 ms): the first star is gone and a new hit pops a fresh one.
	await get_tree().create_timer(0.5).timeout
	var cleared: bool = _count_mode(CartoonBlast.Mode.HIT) == 0
	player.take_damage(10)
	await get_tree().process_frame
	var second: bool = _count_mode(CartoonBlast.Mode.HIT) == 1
	var ok := first and limited and cleared and second
	print("ISSUE718 hit star: first=", first, " rate-limited=", limited,
		" cleared=", cleared, " second=", second, " ok=", ok)
	player.queue_free()
	return ok


## 3. The legacy Projectile explosion path pops the fireball on the
## PARENT (the level root), not on the projectile, and frees the
## projectile itself as before.
func _check_projectile_explosion() -> bool:
	var proj := Projectile.new()
	proj.setup(Projectile.Type.ROCKET, Vector2(300, 0), 40, 2.0,
		Vector2(12, 6), Color.WHITE, 70.0)
	add_child(proj)
	await get_tree().process_frame
	proj._explode()
	await get_tree().process_frame
	await get_tree().process_frame
	var fireball: bool = _count_mode(CartoonBlast.Mode.BLAST) == 1
	var gone: bool = not is_instance_valid(proj)
	var ok := fireball and gone
	print("ISSUE718 projectile explosion: fireball=", fireball,
		" projectile freed=", gone, " ok=", ok)
	return ok
