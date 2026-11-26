extends Node
## Regression check for issue #690 rework (owner 2026-11-24): the armed
## Talk pick shows a VISUAL HINT — moving the cursor over a figure the
## click would pick turns the mouse cursor into a POINTING HAND, over
## anything else it stays the plain arrow, and the hint disappears on
## ANY disarm path even without further mouse motion.
## Rework 2 (owner 2026-11-26): the hint is EXACT — the hand shows only
## when the cursor is ON the figure's 64x64 drawn body, never merely
## NEAR it (the old 48px click-tolerance circle was the bug); the body
## test follows the figure's rotation, so a gravity-rotated figure
## hits on its visible silhouette.
## The test drives ToolInventory exactly the way the game does: real
## physics figures (the pick queries the figure layers), the armed
## tool, injected mouse-motion events (Input.parse_input_event, the
## issue #126/#233 pattern) and the hint flag the cursor shape is
## derived from. (The headless display server ignores cursor shapes,
## so the SHAPE call itself is only compile-checked; the flag — hand
## or arrow — is exactly what the shape is set from.)
##
## Run headless: godot --headless res://tests/test_issue690_cursor_hint.tscn
## Exit code 0 = pass.


## Smallest figure stand-in the physics pick can see: a body on the
## player layer (value 8, inside TALK_FIGURE_MASK 10), in the team
## group, with health.
class Figure extends CharacterBody2D:
	var display_name := "Figure"
	var health := 100


func _ready() -> void:
	# Allow the autoload _ready to run first.
	await get_tree().process_frame
	var ok := true

	# Two figures with real collision shapes: the ACTIVE member (the
	# pick never returns itself) and a teammate next to it, plus a
	# 45-degree-rotated teammate (gravity-rotated figures hit on their
	# visible silhouette, issue #690 rework 2).
	var talker := _figure(Vector2(100.0, 100.0))
	var teammate := _figure(Vector2(300.0, 100.0))
	var rotated := _figure(Vector2(500.0, 100.0))
	rotated.rotation = PI / 4.0
	add_child(talker)
	add_child(teammate)
	add_child(rotated)
	TurnController.active_member = talker

	# Let the physics bodies enter the world before any shape query.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Arm the Talk pick exactly like use_tool's slot branch does.
	ToolInventory.armed_tool = ToolInventory.TOOL_TALK

	# Cursor over the TEAMMATE: the hint is the pointing hand.
	await _move_mouse(Vector2(300.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == true

	# Cursor NEAR the teammate but NOT on its body (40px off-center:
	# inside the old 48px click tolerance, outside the 64x64 body) —
	# rework 2: the plain arrow, exactly the owner's 2026-11-26 report.
	await _move_mouse(Vector2(340.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# Cursor ON the teammate's body edge (30px off-center, inside the
	# 32px half-body but outside the 24px physics circle): the hand —
	# the hint follows the DRAWN body, not the physics capsule.
	await _move_mouse(Vector2(330.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == true

	# Cursor over the ACTIVE MEMBER ITSELF: not a pickable partner —
	# the plain arrow (the pick skips the talker).
	await _move_mouse(Vector2(100.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# Cursor over empty ground: the plain arrow.
	await _move_mouse(Vector2(700.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# Rotated figure (45 degrees): 40px ABOVE its center is INSIDE the
	# turned silhouette (local ~28.3, 28.3) — the hand follows the
	# rotated body, while a plain axis-aligned test would say arrow.
	await _move_mouse(Vector2(500.0, 140.0))
	ok = ok and ToolInventory._talk_cursor_hint == true
	# 43.8px diagonally off its center is OUTSIDE the turned silhouette
	# (local ~0, 43.8) — the arrow, even though an unrotated square
	# would cover the point and the 48px circle still reaches it.
	await _move_mouse(Vector2(531.0, 131.0))
	ok = ok and ToolInventory._talk_cursor_hint == false

	# Back over the teammate (hand again)…
	await _move_mouse(Vector2(300.0, 100.0))
	ok = ok and ToolInventory._talk_cursor_hint == true
	# …then ANY disarm path drops the hint without further motion:
	# _process restores the arrow on a following frame.
	ToolInventory.armed_tool = -1
	await get_tree().process_frame
	await get_tree().process_frame
	ok = ok and ToolInventory._talk_cursor_hint == false

	TurnController.active_member = null
	if ok:
		print("ISSUE690 CURSOR HINT OK: hand exactly on the body (rotated too), arrow near it and over ground/self, disarm resets")
		get_tree().quit(0)
	else:
		print("ISSUE690 CURSOR HINT FAIL")
		get_tree().quit(1)


func _figure(pos: Vector2) -> Figure:
	var figure := Figure.new()
	figure.position = pos
	figure.collision_layer = 8
	figure.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	figure.add_child(shape)
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
