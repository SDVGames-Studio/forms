extends Node
## Regression check for issue #690 rework 4 (owner 2026-11-27): the
## armed Talk pick shows its hint from the figure's COLLISION SHAPE —
## a physics POINT query, not a drawn-rectangle guess: the cursor on
## a figure's shape turns the mouse cursor into a POINTING HAND and
## outlines that figure's body in YELLOW (ModularCharacterVisual's
## talk_hover ring — "if there is a yellow outline the click will
## select the character"); off the shape the plain arrow returns and
## the ring drops. The CLICK prefers the same shape pick — an
## outlined figure always selects — and only a shape-missing click
## falls back to the TALK_PICK_RADIUS tap tolerance. The hint
## disappears on ANY disarm path even without further mouse motion.
## The test drives ToolInventory exactly the way the game does: real
## physics figures (the pick queries the figure layers), the armed
## tool, injected mouse-motion events (Input.parse_input_event, the
## issue #126/#233 pattern) and the hint flag/figure the cursor shape
## is derived from. (The headless display server ignores cursor
## shapes, so the SHAPE call itself is only compile-checked; the
## flags are exactly what the shape is set from.)
##
## Run headless: godot --headless res://tests/test_issue690_cursor_hint.tscn
## Exit code 0 = pass.


## Smallest figure stand-in the physics pick can see: a body on the
## player layer (value 8, inside TALK_FIGURE_MASK 10), in the team
## group, with health, the real game's body capsule (radius 24,
## height 57.6) and the modular body visual that draws the ring.
class Figure extends CharacterBody2D:
	var display_name := "Figure"
	var health := 100
	var visual: Control


func _ready() -> void:
	# Allow the autoload _ready to run first.
	await get_tree().process_frame
	var ok := true

	# Two figures with real collision shapes: the ACTIVE member (the
	# pick never returns itself) and a teammate next to it, plus a
	# teammate whose body children are GRAVITY-ROTATED 45 degrees the
	# way FigurePose.align_to_gravity tilts them (the point query must
	# follow the turned capsule).
	var talker := _figure(Vector2(100.0, 100.0))
	var teammate := _figure(Vector2(300.0, 100.0))
	var rotated := _figure(Vector2(500.0, 100.0), true)
	add_child(talker)
	add_child(teammate)
	add_child(rotated)
	TurnController.active_member = talker

	# Let the physics bodies enter the world before any shape query.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Arm the Talk pick exactly like use_tool's slot branch does.
	ToolInventory.armed_tool = ToolInventory.TOOL_TALK
	var _pq := PhysicsPointQueryParameters2D.new()
	_pq.position = Vector2(300.0, 100.0)
	_pq.collision_mask = 10
	_pq.collide_with_bodies = true

	# Cursor at the teammate's CENTER (inside the collision shape):
	# the hint is the pointing hand AND the yellow ring is on the
	# teammate's body visual (and only on it).
	await _move_mouse(Vector2(300.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == true
	ok = ok and ToolInventory._talk_hint_figure == teammate
	ok = ok and teammate.visual.get("talk_hover") == true
	ok = ok and talker.visual.get("talk_hover") == false

	# Cursor on the teammate's drawn body EDGE but OUTSIDE its
	# collision capsule (30px off-center: inside the 64x64 body,
	# outside the 24px capsule half-width) — rework 4: the plain
	# arrow, no ring — the SHAPE is the boundary, not the drawn body.
	await _move_mouse(Vector2(330.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false
	ok = ok and teammate.visual.get("talk_hover") == false

	# Cursor NEAR the teammate (40px off-center, inside the old 48px
	# click tolerance) — the plain arrow, no ring.
	await _move_mouse(Vector2(340.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# The CLICK keeps its promise (owner 2026-11-27): where the ring
	# shows — the point pick — the click selects that figure; where no
	# shape is hit, the tolerant TALK_PICK_RADIUS fallback still
	# rescues near-missed taps.
	var exact: Node = ToolInventory._figure_at_point(
			Vector2(300.0, 100.0), talker)
	ok = ok and exact == teammate
	var miss: Node = ToolInventory._figure_at_point(
			Vector2(340.0, 100.0), talker)
	ok = ok and miss == null
	var rescue: Node = ToolInventory._figure_at(
			Vector2(340.0, 100.0), talker)
	ok = ok and rescue == teammate

	# Cursor over the ACTIVE MEMBER ITSELF: not a pickable partner —
	# the plain arrow (the pick skips the talker).
	await _move_mouse(Vector2(100.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# Cursor over empty ground: the plain arrow.
	await _move_mouse(Vector2(700.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# Rotated figure (45 degrees, children tilted like FigurePose):
	# 10px diagonally from its center sits INSIDE the turned capsule
	# (the point query follows the rotated shape) — the hand and the
	# ring, and the ring MOVED off the teammate onto this figure.
	await _move_mouse(Vector2(510.0, 110.0))
	ok = ok and ToolInventory._talk_cursor_hint == true
	ok = ok and ToolInventory._talk_hint_figure == rotated
	ok = ok and rotated.visual.get("talk_hover") == true
	ok = ok and teammate.visual.get("talk_hover") == false
	# 24px right and 24px up from the rotated center — inside the plain
	# axis-aligned 64x64 body but OUTSIDE the turned capsule — the
	# arrow (the rotated SHAPE decides, not an axis-aligned guess).
	await _move_mouse(Vector2(524.0, 76.0))
	ok = ok and ToolInventory._talk_cursor_hint == false
	ok = ok and rotated.visual.get("talk_hover") == false

	# Back over the teammate (hand and ring again)…
	await _move_mouse(Vector2(300.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == true
	ok = ok and teammate.visual.get("talk_hover") == true
	# …then ANY disarm path drops the hint and the ring without
	# further motion: _process restores the arrow on a following frame.
	ToolInventory.armed_tool = -1
	await get_tree().process_frame
	await get_tree().process_frame
	ok = ok and ToolInventory._talk_cursor_hint == false
	ok = ok and ToolInventory._talk_hint_figure == null
	ok = ok and teammate.visual.get("talk_hover") == false

	TurnController.active_member = null
	if ok:
		print("ISSUE690 CURSOR HINT OK: hand+ring exactly on the collision shape (rotated too), arrow off it, click prefers the shape and keeps the tap tolerance, disarm resets")
		get_tree().quit(0)
	else:
		print("ISSUE690 CURSOR HINT FAIL")
		get_tree().quit(1)


## A stand-in figure with the game's real body: capsule (radius 24,
## height 57.6), the modular visual (offsets -32..32, REF_SIZE 64),
## player layer 8, the team group, health. rotate_children tilts the
## body children the way FigurePose.align_to_gravity does (pivot at
## the rect centre), so the rotated case matches the real game.
func _figure(pos: Vector2, rotate_children := false) -> Figure:
	var figure := Figure.new()
	figure.position = pos
	figure.collision_layer = 8
	figure.collision_mask = 0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 57.6
	shape.shape = capsule
	if rotate_children:
		shape.rotation = PI / 4.0
	figure.add_child(shape)
	var visual: Control = load(
			"res://scripts/ModularCharacterVisual.gd").new()
	visual.offset_left = -32.0
	visual.offset_top = -32.0
	visual.offset_right = 32.0
	visual.offset_bottom = 32.0
	if rotate_children:
		visual.pivot_offset = visual.size / 2.0
		visual.rotation = PI / 4.0
	figure.add_child(visual)
	figure.visual = visual
	figure.add_to_group("player_team")
	return figure


func _move_mouse(world: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	# Injected events travel the full window path: the dispatch maps
	# window pixels -> viewport content with the FINAL transform (the
	# canvas_items stretch — headless the window is a tiny 64x64), then
	# the handler maps content -> world with the canvas transform
	# (identity in this scene). The inverse chain lands the WORLD point
	# the test wants under the cursor.
	ev.position = get_viewport().get_final_transform() * world
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame
