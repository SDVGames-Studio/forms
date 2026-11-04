extends Node
## Regression check for issue #277: the aim — the direction the held
## weapon indicates — must live in the figure's CURRENT gravity frame so
## it corresponds to the character's stance/position. Issue #270 rotated
## figure bodies to the level's real gravity (disc arenas included), but
## the aim kept the world-vertical frame with only the legacy center-line
## flip: beside a disc rim the weapon indicated a direction sticking out
## of the character's head/feet line instead of aiming along its body.
##
## Checks (for BOTH Player and Npc figures):
##  1. FLAT frame (gravity DOWN) — aim is EXACTLY the legacy formula
##     (cos(view) * facing, -sin(view)): flat levels unchanged.
##  2. FLIPPED frame (gravity UP, the old below-the-center-line world) —
##     aim is the legacy formula with the flipped sign: (cos, +sin).
##  3. RADIAL frame (gravity +x — standing on a disc's left rim) —
##     view 0 aims along the surface tangent (0, -1), not world (1, 0);
##     raising the view tilts the muzzle AWAY from the floor;
##     current_gravity() exposes the frame for the Weapon's facing.
##  4. LIVE PLUMBING: beside a real IndestructibleGround disc the physics
##     tick feeds the radial gravity into the frame and the aim follows.
##
## Rework checks (issue #277 rework):
##  5. TANGENT CONTINUITY: walking a disc's rim across the 3 o'clock
##     position (where the tangent is vertical) keeps the aim rotating
##     smoothly — the old "flip while tangent.x < 0" rule snapped the aim
##     180° there with every wobble of the gravity vector.
##  6. TERRAIN-ONLY GRAVITY (issue #293): the separately configured
##     central line is gone — over a base slab's rounded corner region
##     the frame now ALWAYS follows the terrain (the corner tilt is the
##     honest, ground-derived gravity).
##  7. LOBBED THROWS FOLLOW THE INDICATED AIM: Weapon.lobbed_velocity
##     points along the weapon's aim plus the frame's lob — facing LEFT
##     no longer launches the grenade 180° backwards, and facing right on
##     flat ground reproduces the exact legacy arc.
##
## Rework-2 checks (issue #277 rework 2 — "the character is flying, but
## it must be grounded"):
##  8. NO SKY-HOPPING ON A DISC: an active NPC on a disc rim whose target
##     is WORLD-above (the player team sits at the ring's top) but NOT
##     above in the gravity frame must NOT jump at all — the old world-y
##     trigger made every arriving NPC hop-spam into the sky.
##  9. JUMP COOL-DOWN: with the target genuinely above IN FRAME (flat
##     ground, target on a platform overhead), the NPC still jumps — but
##     at most once per JUMP_COOLDOWN second, never on every landing tick.
##
## Run headless: godot --headless res://tests/test_issue277.tscn
## Exit code 0 = pass.

const PlayerScript := preload("res://Player.gd")
const NpcScript := preload("res://Npc.gd")
const Indestructible := preload("res://scripts/IndestructibleGround.gd")
const WeaponScript := preload("res://Weapon.gd")
const EPS := 0.001


func _figure(script: Script, grav: Vector2, view: float) -> CharacterBody2D:
	var fig := script.new() as CharacterBody2D
	fig.set("view_angle", view)
	fig.set("_aim_grav", grav)
	# Rework: the tangent is hysteresis state — seed it the way the first
	# physics tick would have (legacy orientation against the +x axis).
	var tangent := Vector2(grav.y, -grav.x)
	if tangent.x < 0.0:
		tangent = -tangent
	fig.set("_aim_tangent", tangent)
	return fig


func _expect(label: String, got: Vector2, want: Vector2) -> bool:
	var good := got.distance_to(want) < EPS
	print("ISSUE277 ", label, ": got ", got, " want ", want, " -> ", good)
	return good


func _check_script(script: Script, label: String) -> bool:
	var ok := true
	var view := 0.6
	# 1. Flat frame — legacy formula, no change.
	var flat := _figure(script, Vector2.DOWN, view)
	ok = _expect(label + " flat aim", flat.aim_dir(-1.0, 1.0),
			Vector2(cos(view) * -1.0, -sin(view))) and ok
	ok = _expect(label + " flat frame", flat.current_gravity(),
			Vector2.DOWN) and ok
	ok = _expect(label + " flat tangent", flat.current_tangent(),
			Vector2.RIGHT) and ok
	# 2. Flipped frame (the old center-line underside) — legacy dir = -1.
	var flipped := _figure(script, Vector2.UP, view)
	ok = _expect(label + " flipped aim", flipped.aim_dir(1.0, -1.0),
			Vector2(cos(view), sin(view))) and ok
	# 3. Radial frame — disc left rim, gravity pulls +x toward the core.
	var radial := _figure(script, Vector2(1.0, 0.0), 0.0)
	ok = _expect(label + " radial view=0", radial.aim_dir(1.0, 1.0),
			Vector2(0.0, -1.0)) and ok
	var raised := _figure(script, Vector2(1.0, 0.0), 0.5)
	var aim: Vector2 = raised.aim_dir(1.0, 1.0)
	var away := aim.dot(Vector2(-1.0, 0.0)) > 0.2
	print("ISSUE277 ", label, " radial raise away-from-floor: ", aim,
			" -> ", away)
	ok = away and ok
	return ok


## Rework check 5: the aim rotates CONTINUOUSLY across a disc rim's
## vertical-tangent position (3 o'clock) — no 180° snap.
func _check_rim_continuity(label: String) -> bool:
	var fig := PlayerScript.new() as CharacterBody2D
	add_child(fig)
	var disc := Indestructible.new()
	disc.radius = 300.0
	add_child(disc)
	var ok := true
	var prev_aim := Vector2.ZERO
	for deg in [-15.0, -5.0, 5.0, 15.0]:
		fig.global_position = Vector2(cos(deg_to_rad(deg)),
				sin(deg_to_rad(deg))) * 360.0
		fig.velocity = Vector2.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		var aim: Vector2 = fig.aim_dir(1.0, 1.0)
		if prev_aim != Vector2.ZERO:
			var smooth := aim.dot(prev_aim) > 0.7
			print("ISSUE277 ", label, " rim ", deg, "deg aim=", aim,
					" continuity=", smooth)
			ok = smooth and ok
		prev_aim = aim
	fig.queue_free()
	disc.queue_free()
	await get_tree().physics_frame
	return ok


## Rework check 6 (issue #293): terrain-only gravity — over the base
## slab's rounded corner the frame follows the ground tilt; no authored
## central line exists anymore to flatten it.
func _check_terrain_corner(label: String) -> bool:
	var slab := StaticBody2D.new()
	slab.set_script(Indestructible)
	slab.rect_size = Vector2(400, 448)
	slab.position = Vector2(0.0, 300.0)
	add_child(slab)
	var fig := PlayerScript.new() as CharacterBody2D
	add_child(fig)
	# Above the slab, over its rounded left corner: the ground's tilt is
	# the gravity — no separate central-line contract to beat it (#293).
	fig.global_position = Vector2(-180.0, 40.0)
	fig.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grav: Vector2 = fig.get("_aim_grav")
	var corner_ok := absf(grav.angle_to(Vector2.DOWN)) > 0.05
	print("ISSUE277 ", label, " terrain corner: grav=", grav,
			" -> ", corner_ok)
	fig.queue_free()
	slab.queue_free()
	await get_tree().physics_frame
	return corner_ok


## Rework check 7: lobbed throws follow the INDICATED aim.
func _check_lob(label: String) -> bool:
	# Facing LEFT on flat ground: the weapon indicates up-left; the launch
	# velocity must point left and up (the old construction flipped 180°).
	var left := WeaponScript.lobbed_velocity(Vector2(-1.0, 0.0),
			Vector2.UP, 500.0, 1.0)
	var left_ok := left.x < -EPS and left.y < -EPS
	print("ISSUE277 ", label, " lob left: ", left, " -> ", left_ok)
	# Facing RIGHT, flat ground, full power: the exact legacy arc
	# (speed, -320).
	var right := WeaponScript.lobbed_velocity(Vector2(1.0, 0.0),
			Vector2.UP, 500.0, 1.0)
	var right_ok := right.distance_to(Vector2(500.0, -320.0)) < EPS
	print("ISSUE277 ", label, " lob legacy: ", right, " -> ", right_ok)
	# Partial power lob scale (legacy: 320 * strength).
	var part := WeaponScript.lobbed_velocity(Vector2(1.0, 0.0),
			Vector2.UP, 500.0, 0.4)
	var part_ok := part.distance_to(Vector2(500.0, -128.0)) < EPS
	print("ISSUE277 ", label, " lob power: ", part, " -> ", part_ok)
	return left_ok and right_ok and part_ok


## Rework-2 helper: run `ticks` physics frames with `npc` forced as the
## active turn member (the AI branch only runs on the NPC's own turn) and
## count REAL take-offs (air stretches longer than contact flicker).
func _count_takeoffs(npc: CharacterBody2D, ticks: int) -> int:
	var takeoffs := 0
	var air := 0
	var was_floor := true
	for i in ticks:
		TurnController.set("game_over", false)
		TurnController.set("active_member", npc)
		TurnController.set("active_team", TurnController.team_id_of(npc))
		await get_tree().physics_frame
		var fl := npc.is_on_floor()
		if fl:
			# Landed: count the air stretch just ended if it was a real arc
			# (> 10 ticks); shorter stretches are contact flicker on bumpy
			# ground, not jumps.
			if not was_floor and air >= 10:
				takeoffs += 1
			air = 0
		else:
			air += 1
		was_floor = fl
	return takeoffs


## Rework-2 check 8: disc rim — target world-above must NOT lift the NPC.
func _check_disc_no_skyhop(label: String) -> bool:
	var disc := Indestructible.new()
	disc.radius = 300.0
	add_child(disc)
	var target := PlayerScript.new() as CharacterBody2D
	target.set("display_name", "Target")
	add_child(target)
	target.global_position = Vector2(0.0, -332.0)
	var npc := NpcScript.new() as CharacterBody2D
	add_child(npc)
	# 3 o'clock rim; the target at 12 o'clock is 332px WORLD-above — the
	# old (target.y - y) * gravity_dir < -80 trigger fired here constantly.
	npc.global_position = Vector2(332.0, 0.0)
	npc.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var takeoffs := await _count_takeoffs(npc, 120)
	var grounded := npc.is_on_floor()
	var ok := takeoffs <= 1 and grounded
	print("ISSUE277 ", label, " disc no-skyhop: takeoffs=", takeoffs,
			" grounded=", grounded, " -> ", ok)
	npc.queue_free()
	target.queue_free()
	disc.queue_free()
	await get_tree().physics_frame
	return ok


## Rework-2 check 9: target genuinely above IN FRAME — jumps, but cooled
## down (at most one take-off per JUMP_COOLDOWN second, not per tick).
func _check_jump_cooldown(label: String) -> bool:
	var slab := StaticBody2D.new()
	slab.set_script(Indestructible)
	slab.rect_size = Vector2(400, 448)
	slab.position = Vector2(0.0, 300.0)
	add_child(slab)
	var target := PlayerScript.new() as CharacterBody2D
	target.set("display_name", "Target")
	add_child(target)
	var npc := NpcScript.new() as CharacterBody2D
	add_child(npc)
	# Slab top face at y=76; NPC standing on it, target 300px overhead —
	# above in the gravity frame, so jumping stays allowed.
	npc.global_position = Vector2(0.0, 44.0)
	npc.velocity = Vector2.ZERO
	target.global_position = Vector2(0.0, -256.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 240 ticks = 4s: the old trigger jumped on nearly every landing
	# (>15 take-offs); the cool-down must keep it to a handful.
	var takeoffs := await _count_takeoffs(npc, 240)
	var ok := takeoffs >= 1 and takeoffs <= 4
	print("ISSUE277 ", label, " jump cooldown: takeoffs=", takeoffs,
			" -> ", ok)
	npc.queue_free()
	target.queue_free()
	slab.queue_free()
	await get_tree().physics_frame
	return ok


func _ready() -> void:
	var ok := true
	ok = _check_script(PlayerScript, "Player") and ok
	ok = _check_script(NpcScript, "Npc") and ok
	# 4. Live plumbing: a real disc feeds the frame through the physics tick.
	var disc := Indestructible.new()
	disc.radius = 300.0
	add_child(disc)
	var fig := PlayerScript.new() as CharacterBody2D
	add_child(fig)
	fig.global_position = Vector2(-360.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grav: Vector2 = fig.get("_aim_grav")
	var live_aim: Vector2 = fig.aim_dir(1.0, 1.0)
	var live_ok := grav.distance_to(Vector2(1.0, 0.0)) < 0.01 \
			and live_aim.distance_to(Vector2(0.0, -1.0)) < EPS
	print("ISSUE277 live disc: grav ", grav, " aim ", live_aim,
			" -> ", live_ok)
	ok = live_ok and ok
	fig.queue_free()
	disc.queue_free()
	await get_tree().physics_frame
	# Rework checks.
	ok = await _check_rim_continuity("rework") and ok
	ok = await _check_terrain_corner("rework") and ok
	ok = _check_lob("rework") and ok
	# Rework-2 checks ("flying, must be grounded").
	ok = await _check_disc_no_skyhop("rework2") and ok
	ok = await _check_jump_cooldown("rework2") and ok
	print("ISSUE277 ok=", ok)
	get_tree().quit(0 if ok else 1)
