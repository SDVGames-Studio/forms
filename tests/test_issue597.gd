extends Node
## Regression check for issue #597: "game accidentally crashed
## (web-version)".
##
## The owner's screenshot: Level 4, turn 15 — RED Member 1 fires a
## Baseball Bat, takes 30 damage (0/100) from a nearby mine and DIES
## while the bat victim is still flying; the OSD froze on "Shot fired —
## waiting for the projectiles...". The bat's turn-effect GATE node
## (BatKnockback) lives on the LEVEL while its ticking lives in the
## SHOOTER's Weapon._physics_process — when the shooter's corpse was
## freed mid-flight the ticking died with it and the gate stayed in the
## turn_effects group forever, so every handover after that stalled
## until the 30 s safety timer force-started the turn (on the web that
## reads as "the game crashed").
##
## Checked here:
##  1. a swing that hits REGISTERS its BatKnockback gate in
##     turn_effects (the handover correctly waits for the flight);
##  2. the shooter leaving the tree mid-flight (the death free) RELEASES
##     the gate at once — within frames, not the 5 s cap and not the
##     30 s safety timer — so the handover can complete;
##  3. the same release holds for the jackhammer's JackhammerDrill gate
##     when the driller leaves the tree mid-drill;
##  4. a VICTIM freed mid-flight (it died from the bat hit, corpse
##     queue_free()d 0.25 s later) does not error the tick (the pre-fix
##     `as`-cast on the freed record aborted _tick_bat_push every frame
##     — the web "crash") and the gate releases at once.
##
## Run headless: godot --headless res://tests/test_issue597.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A stand-in victim: plain Node2D with health + take_damage + velocity,
## so the bat's push takes the direct-offset branch (deterministic in
## headless tests — no physics shapes needed, same stand-in as
## test_issue549). No floor contact → the flight rides the BAT_FLIGHT_CAP
## to the end, which is exactly the window the shooter's death falls in.
class FakeFigure extends Node2D:
	var health := 100
	var velocity := Vector2.ZERO

	func take_damage(damage: int) -> void:
		health -= damage


func _effect_gates() -> int:
	return get_tree().get_nodes_in_group("turn_effects").size()


## Poll up to `max_frames` physics frames for every turn-effect gate to
## be gone. "Promptly" means frames — never the bat's 5 s flight cap and
## never the handover's 30 s safety timer.
func _wait_gates_clear(max_frames: int) -> bool:
	for i in max_frames:
		if _effect_gates() == 0:
			return true
		await get_tree().physics_frame
	return _effect_gates() == 0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- 1) the swing registers its gate ------------------------------
	var shooter := Node2D.new()
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	var victim := FakeFigure.new()
	victim.position = Vector2(60.0, 0.0)  # ahead along the aim (1, 0)
	add_child(victim)
	victim.add_to_group("enemy_team")
	gun._swing_bat(1.0)
	# Issue #721 rework: the strike lands at the forward sweep's peak —
	# wait out the wind-up so the flight is live before the free below.
	for i in 30:
		await get_tree().physics_frame
		if gun._bat_push_left > 0.0:
			break
	_check(victim.health == 100 - WeaponScript.BAT_DAMAGE,
			"the swing must reach and damage the figure ahead")
	await get_tree().physics_frame
	_check(_effect_gates() == 1,
			"a live bat flight must hold its BatKnockback gate (got %d)"
			% _effect_gates())

	# --- 2) the shooter's death free releases the gate at once --------
	# The corpse is queue_free()d 0.25 s after death; freeing the shooter
	# detaches the weapon mid-flight exactly like that death path.
	shooter.queue_free()
	# The section-1 victim goes with its shooter — otherwise a later
	# swing along the same aim would catch it too.
	victim.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_effect_gates() == 0,
			"the gate must be released when the shooter leaves the tree mid-flight (got %d left)"
			% _effect_gates())

	# --- 3) the drill gate follows the driller out --------------------
	var driller := Node2D.new()
	add_child(driller)
	var drill_gun := Node2D.new()
	drill_gun.set_script(WeaponScript)
	driller.add_child(drill_gun)
	drill_gun._start_jackhammer(1.0)
	# Same frame — before any physics tick, so the drill's air-stall
	# guard cannot end the drill (a plain Node2D in the void drills
	# nothing; the death-free path only needs the gate to be live).
	_check(_effect_gates() == 1,
			"a live drill must hold its JackhammerDrill gate (got %d)"
			% _effect_gates())
	driller.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_effect_gates() == 0,
			"the drill gate must be released when the driller leaves the tree mid-drill (got %d left)"
			% _effect_gates())

	# --- 4) a freed victim mid-flight neither errors nor wedges ------
	var shooter2 := Node2D.new()
	add_child(shooter2)
	var gun2 := Node2D.new()
	gun2.set_script(WeaponScript)
	shooter2.add_child(gun2)
	var victim2 := FakeFigure.new()
	victim2.position = Vector2(60.0, 0.0)
	add_child(victim2)
	victim2.add_to_group("enemy_team")
	gun2._swing_bat(1.0)
	# Issue #721 rework: same wind-up wait — the flight must be live
	# before the victim is freed mid-flight.
	for i in 30:
		await get_tree().physics_frame
		if gun2._bat_push_left > 0.0:
			break
	_check(victim2.health == 100 - WeaponScript.BAT_DAMAGE,
			"the second swing must reach its figure too")
	_check(_effect_gates() == 1,
			"the second swing must hold its own gate (got %d)" % _effect_gates())
	await get_tree().physics_frame
	# The victim died from the hit; the corpse free lands mid-flight.
	victim2.queue_free()
	var freed_ok := await _wait_gates_clear(10)
	_check(freed_ok,
			"a freed victim must release the flight gate promptly (still %d after 10 frames)"
			% _effect_gates())

	if failures == 0:
		print("issue597: ALL OK")
	else:
		push_error("issue597: %d check(s) failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)
