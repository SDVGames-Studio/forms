extends Node
## Issue #518 regression: a TELEPORT is a discrete jump, but the figure's
## walking/aiming tangent is oriented by CONTINUITY with the previous
## physics frame (Player/Npc _aim_tangent, issue #277 rework). A figure
## leaving Level4's bottom-right corner arc for the underside of the
## level floor therefore arrived with a 180°-mirrored frame: pressing D
## walked LEFT, A walked RIGHT (walking there keeps the correct frame).
##
## The fix: Player.reanchor_gravity_frame() / Npc.reanchor_gravity_frame()
## snap the frame to the destination's gravity with the tangent anchored
## screen-right (non-negative x component — the same anchor a fresh spawn
## gets); ToolInventory's teleport click and Npc's teleport-away hop call
## it right after the discrete move.
##
## Run headless: godot --headless res://tests/test_issue518.tscn
## Exit code 0 = pass; the printed ISSUE518 ok= verdict is authoritative.

const LEVEL4 := preload("res://Level4.tscn")

## The underside of Level4's floor slab (open air below y=928 — the figure
## falls UP onto the underside; gravity (0, -1)).
const UNDER_SLAB := Vector2(2048, 990)

func _ready() -> void:
	var level: Node = LEVEL4.instantiate()
	add_child.call_deferred(level)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: Node2D = level.get_node("Player")
	var npc: Node2D = level.get_node("Npc")
	var ok := true

	# --- Case 1 (sanity): flat ground -> underside keeps D = screen-right.
	# Was already correct pre-fix (continuity from (1,0) survives the flip);
	# guards the fix against regressing the plain case. ---
	await _place(player, Vector2(400, 200), 60)
	await _teleport(player, UNDER_SLAB)
	await _settle(player, 150)
	var t1: Vector2 = player.current_tangent()
	var ok1 := t1.x > 0.99 and absf(t1.y) < 0.1
	print("ISSUE518 flat->underside tangent=", t1, " ok=", ok1)
	ok = ok and ok1

	# --- Case 2 (the report): right face -> underside. Settling on the
	# slab's right face rotates the tangent to vertical (0, 1); the old
	# continuity rule then KEPT the raw (-1, 0) at the underside (dot = 0,
	# not < 0) — D walked LEFT. The re-anchor must give (1, 0). ---
	await _place(player, Vector2(4110, 700), 150)
	var pre2: Vector2 = player.current_tangent()
	await _teleport(player, UNDER_SLAB)
	await _settle(player, 150)
	var t2: Vector2 = player.current_tangent()
	var ok2 := pre2.y > 0.9 and t2.x > 0.99 and absf(t2.y) < 0.1
	print("ISSUE518 right-face=", pre2, " ->underside tangent=", t2,
			" ok=", ok2)
	ok = ok and ok2

	# --- Case 3 (same trap at the LEFT end of the slab): the left face's
	# vertical tangent (0, -1) also kept the raw (-1, 0) mirror at the
	# underside. ---
	await _place(player, Vector2(-30, 700), 150)
	var pre3: Vector2 = player.current_tangent()
	await _teleport(player, UNDER_SLAB)
	await _settle(player, 150)
	var t3: Vector2 = player.current_tangent()
	var ok3 := pre3.y < -0.9 and t3.x > 0.99 and absf(t3.y) < 0.1
	print("ISSUE518 left-face=", pre3, " ->underside tangent=", t3,
			" ok=", ok3)
	ok = ok and ok3

	# --- Case 4 (NPC hop, issue #221 path): Npc._try_teleport_away makes
	# the same discrete move and now re-anchors too. Short settle — the NPC
	# AI is live headless. ---
	await _place(npc, Vector2(4110, 700), 150)
	await _teleport(npc, UNDER_SLAB)
	await _settle(npc, 10)
	var t4: Vector2 = npc.current_tangent()
	var ok4 := t4.x > 0.9
	print("ISSUE518 npc-hop tangent=", t4, " ok=", ok4)
	ok = ok and ok4

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
