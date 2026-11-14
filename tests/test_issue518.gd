extends Node
## Issue #518 rework regression: the owner directive — "each character
## has a local coordinate system, which used by the character's cam, so
## use this local coordinate system to choose where should a/d keys
## lead". The walk/aim tangent must be the character's LOCAL +x — the
## raw perpendicular (grav.y, -grav.x) — which the character camera
## (#289, view rotation grav.angle() - PI/2) renders as screen-RIGHT
## wherever gravity points. The first fix anchored the tangent to the
## WORLD x axis (non-negative x): under upward gravity (Level4's floor
## underside) it kept the tangent at world +x, the rotated camera
## rendered that axis screen-LEFT, and D still walked left.
##
## The fix: Player/Npc set _aim_tangent = (grav.y, -grav.x) directly
## (continuity and world-x anchor rules removed), so D walks the
## character's own right — screen-right in the character camera on flat
## ground, a floor's underside and a disc rim alike.
##
## Run headless: godot --headless res://tests/test_issue518.tscn
## Exit code 0 = pass; the printed ISSUE518 ok= verdict is authoritative.

const LEVEL4 := preload("res://scenes/levels/Level4.tscn")

## The underside of Level4's floor slab (open air below y=928 — the figure
## falls UP onto the underside; gravity (0, -1)).
const UNDER_SLAB := Vector2(2048, 990)

## The character's LOCAL +x in world space — exactly the axis the #289
## character camera renders as screen-right (its view rotation is
## grav.angle() - PI/2, so rotating RIGHT by it gives the local x axis).
func _local_x(grav: Vector2) -> Vector2:
	return Vector2.RIGHT.rotated(grav.angle() - PI / 2.0)

## The full local-frame contract: the tangent IS the character's local +x
## (both the direct formula and the camera-screen-right axis), which for
## upward gravity is world (-1, 0) — D walks screen-right, not world +x.
func _check_frame(label: String, figure: Node2D) -> bool:
	var grav: Vector2 = figure.current_gravity()
	var tangent: Vector2 = figure.current_tangent()
	var formula_ok := tangent.distance_to(Vector2(grav.y, -grav.x)) < 0.1
	var camera_ok := tangent.distance_to(_local_x(grav)) < 0.1
	var ok := formula_ok and camera_ok
	print("ISSUE518 ", label, " grav=", grav, " tangent=", tangent,
			" ok=", ok)
	return ok

func _ready() -> void:
	var level: Node = LEVEL4.instantiate()
	add_child.call_deferred(level)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: Node2D = level.get_node("Player")
	var npc: Node2D = level.get_node("Npc")
	var ok := true

	# --- Case 1 (sanity): flat ground keeps D = local right = world +x. ---
	await _place(player, Vector2(400, 200), 60)
	ok = _check_frame("flat", player) and ok

	# --- Case 2 (the report): teleport to the slab underside. Under
	# UPWARD gravity the local +x is world (-1, 0) — the world-x anchor of
	# the first fix kept the tangent at (1, 0) and D walked screen-LEFT
	# in the rotated camera view. Walking there (no teleport) already
	# followed the raw local tangent, which is why walking to the spot
	# worked and teleporting did not. ---
	await _teleport(player, UNDER_SLAB)
	await _settle(player, 150)
	var grav_up: Vector2 = player.current_gravity()
	var t2: Vector2 = player.current_tangent()
	var ok2 := grav_up.y < -0.9 and t2.x < -0.99 and absf(t2.y) < 0.1
	print("ISSUE518 flat->underside grav=", grav_up, " tangent=", t2,
			" ok=", ok2)
	ok = ok and ok2

	# --- Case 3: the right-face arrival (the exact reported path — the
	# corner arc's vertical tangent used to survive the discrete jump).
	# The tangent must snap to the destination's LOCAL frame, not keep
	# the old spot's or the world-x orientation. ---
	await _place(player, Vector2(4110, 700), 150)
	var pre3: Vector2 = player.current_tangent()
	await _teleport(player, UNDER_SLAB)
	await _settle(player, 150)
	ok = _check_frame("right-face->underside", player) and ok
	var t3: Vector2 = player.current_tangent()
	var ok3 := pre3.y > 0.9 and t3.x < -0.99 and absf(t3.y) < 0.1
	print("ISSUE518 right-face=", pre3, " ->underside tangent=", t3,
			" ok=", ok3)
	ok = ok and ok3

	# --- Case 4 (same trap from the LEFT end of the slab). ---
	await _place(player, Vector2(-30, 700), 150)
	var pre4: Vector2 = player.current_tangent()
	await _teleport(player, UNDER_SLAB)
	await _settle(player, 150)
	ok = _check_frame("left-face->underside", player) and ok
	var t4: Vector2 = player.current_tangent()
	var ok4 := pre4.y < -0.9 and t4.x < -0.99 and absf(t4.y) < 0.1
	print("ISSUE518 left-face=", pre4, " ->underside tangent=", t4,
			" ok=", ok4)
	ok = ok and ok4

	# --- Case 5 (NPC hop, issue #221 path): Npc._try_teleport_away makes
	# the same discrete move and shares the local-frame rule. Short
	# settle — the NPC AI is live headless. ---
	await _place(npc, Vector2(4110, 700), 150)
	await _teleport(npc, UNDER_SLAB)
	await _settle(npc, 10)
	var t5: Vector2 = npc.current_tangent()
	var ok5 := t5.x < -0.9
	print("ISSUE518 npc-hop tangent=", t5, " ok=", ok5)
	ok = ok and ok5

	print("ISSUE518 ok=", ok)
	get_tree().quit(0 if ok else 1)

## Put a figure at `pos` and let `frames` physics ticks settle it.
func _place(figure: Node2D, pos: Vector2, frames: int) -> void:
	figure.global_position = pos
	figure.velocity = Vector2.ZERO
	await _settle(figure, frames)

## The exact discrete move the teleport tool makes (ToolInventory, issue
## #170 click path): position jump, velocity reset, frame re-anchor.
func _teleport(figure: Node2D, dest: Vector2) -> void:
	figure.global_position = dest
	figure.velocity = Vector2.ZERO
	if figure.has_method("reanchor_gravity_frame"):
		figure.reanchor_gravity_frame()

func _settle(figure: Node2D, frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
