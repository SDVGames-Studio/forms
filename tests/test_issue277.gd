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
##  6. AUTHORED CENTER LINE BEATS TERRAIN: on a level that authors a
##     central line AND sits an indestructible base slab under the soil,
##     a figure standing flat above the slab's rounded corner region gets
##     plain DOWN gravity — no corner lean, no tilted weapon (Level3/
##     Level4 "with the horizontal line too").
##  7. LOBBED THROWS FOLLOW THE INDICATED AIM: Weapon.lobbed_velocity
##     points along the weapon's aim plus the frame's lob — facing LEFT
##     no longer launches the grenade 180° backwards, and facing right on
##     flat ground reproduces the exact legacy arc.
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


## Rework check 6: an authored central line beats the base slab's corner —
## flat gravity above a corner region that terrain rules would bend.
func _check_center_line_beats_corner(label: String) -> bool:
	var slab := StaticBody2D.new()
	slab.set_script(Indestructible)
	slab.rect_size = Vector2(400, 448)
	slab.position = Vector2(0.0, 300.0)
	add_child(slab)
	var fig := PlayerScript.new() as CharacterBody2D
	fig.set("center_line_y", 150.0)
	add_child(fig)
	# Above the slab, over its rounded left corner: terrain gravity would
	# tilt; the authored line must keep it plain DOWN.
	fig.global_position = Vector2(-180.0, 40.0)
	fig.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grav: Vector2 = fig.get("_aim_grav")
	var line_ok := grav.distance_to(Vector2.DOWN) < EPS
	print("ISSUE277 ", label, " line-beats-corner: grav=", grav,
			" -> ", line_ok)
	fig.set("center_line_y", 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	grav = fig.get("_aim_grav")
	var terrain_ok := absf(grav.angle_to(Vector2.DOWN)) > 0.05
	print("ISSUE277 ", label, " no-line terrain corner: grav=", grav,
			" -> ", terrain_ok)
	fig.queue_free()
	slab.queue_free()
	await get_tree().physics_frame
	return line_ok and terrain_ok


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
	ok = await _check_center_line_beats_corner("rework") and ok
	ok = _check_lob("rework") and ok
	print("ISSUE277 ok=", ok)
	get_tree().quit(0 if ok else 1)
