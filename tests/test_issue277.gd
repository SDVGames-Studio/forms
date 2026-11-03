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
## Run headless: godot --headless res://tests/test_issue277.tscn
## Exit code 0 = pass.

const PlayerScript := preload("res://Player.gd")
const NpcScript := preload("res://Npc.gd")
const Indestructible := preload("res://scripts/IndestructibleGround.gd")
const EPS := 0.001


func _figure(script: Script, grav: Vector2, view: float) -> CharacterBody2D:
	var fig := script.new() as CharacterBody2D
	fig.set("view_angle", view)
	fig.set("_aim_grav", grav)
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
	print("ISSUE277 ok=", ok)
	get_tree().quit(0 if ok else 1)
