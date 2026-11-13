extends Node
## Regression check for issue #384: "gravity field enabling in game
## doesn't work".
## Since #304 the Settings screen (with the Gravity Field switch) is
## reachable from the in-game pause overlay, so the switch can be
## flipped while a level runs. The camera used to sample the flag only
## in _ready, so enabling the field mid-level never spawned the overlay.
## Now ZoomCamera._process reconciles the overlay with the LIVE flag.
##
## Checks (Level2, switch off at level start):
##  1. No overlay exists while the switch is off.
##  2. Flipping GameConfig.debug_gravity_field on mid-level (exactly
##     what the settings switch does) makes the overlay appear, parented
##     to the level's camera, without restarting the level.
##  3. Flipping it off again hides the overlay (its _process mirrors the
##     flag); exactly one overlay exists (no duplicates from the flips).
##  4. Flipping it on once more shows the SAME overlay again.
##
## Rework (owner comment 2026-11-07): "a menu button hides if I move the
## cursor on it". A CHECKED CheckButton under the cursor draws in the
## hover_pressed state (BaseButton.DRAW_HOVER_PRESSED); MenuTheme defined
## no hover_pressed stylebox (empty default) and a near-black
## font_hover_pressed_color, so the GRAVITY FIELD switch disappeared the
## moment the mouse hovered it. Check 5: the theme now resolves a VISIBLE
## StyleBoxFlat for hover_pressed through the CheckButton fallback — the
## exact lookup the engine makes when drawing a hovered, checked switch.
##
## Run headless: godot --headless res://tests/test_issue384.tscn
## Exit code 0 = pass.


func _ready() -> void:
	var ok := true
	GameConfig.debug_gravity_field = false
	var level: Node = load("res://scenes/levels/Level2.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame

	# --- 1. Switch off: no overlay. ---
	var off_ok: bool = _overlay() == null and _camera() != null
	print("ISSUE384 off_no_overlay=", off_ok)
	ok = ok and off_ok

	# --- 2. Flip ON mid-level: the overlay appears on the camera. ---
	GameConfig.debug_gravity_field = true
	for i in 5:
		await get_tree().process_frame
	var field := _overlay()
	var cam := _camera()
	var on_ok: bool = field != null and cam != null \
			and field.get_parent() == cam and field.visible
	print("ISSUE384 flip_on=", on_ok)
	ok = ok and on_ok

	# --- 3. Flip OFF: the overlay hides and stays single. ---
	GameConfig.debug_gravity_field = false
	for i in 5:
		await get_tree().process_frame
	var hidden_ok: bool = _overlay() != null \
			and not _overlay().visible \
			and get_tree().get_nodes_in_group(
					"gravity_field_debug").size() == 1
	print("ISSUE384 flip_off_hidden=", hidden_ok)
	ok = ok and hidden_ok

	# --- 4. On again: the same overlay reappears. ---
	GameConfig.debug_gravity_field = true
	for i in 5:
		await get_tree().process_frame
	var again_ok: bool = _overlay() == field and _overlay().visible
	print("ISSUE384 flip_on_again=", again_ok)
	ok = ok and again_ok

	# --- 5. Rework: a hovered CHECKED switch must stay visible. ---
	var hover_ok := _hover_pressed_style_visible()
	print("ISSUE384 hover_pressed_visible=", hover_ok)
	ok = ok and hover_ok

	print("ISSUE384 ok=", ok)
	GameConfig.debug_gravity_field = false
	get_tree().quit(0 if ok else 1)


## Issue #384 rework: the engine draws a hovered, checked CheckButton
## with the hover_pressed stylebox and font_hover_pressed_color. Both must
## resolve to something visible through the CheckButton theme fallback.
func _hover_pressed_style_visible() -> bool:
	var root := Control.new()
	root.theme = load("res://scenes/menus/MenuTheme.tres")
	add_child(root)
	var check := CheckButton.new()
	check.toggle_mode = true
	check.button_pressed = true
	root.add_child(check)
	var sb: StyleBox = check.get_theme_stylebox("hover_pressed", "CheckButton")
	var visible_box: bool = sb is StyleBoxFlat \
			and (sb as StyleBoxFlat).bg_color.a > 0.5
	var font_color: Color = check.get_theme_color(
			"font_hover_pressed_color", "CheckButton")
	var flat := sb as StyleBoxFlat
	var box_lum := (flat.bg_color.r * 0.3 + flat.bg_color.g * 0.5
			+ flat.bg_color.b * 0.2) if flat != null else 0.0
	var font_lum := font_color.r * 0.3 + font_color.g * 0.5 \
			+ font_color.b * 0.2
	var readable: bool = absf(box_lum - font_lum) > 0.3
	root.queue_free()
	return visible_box and readable


func _overlay() -> Node:
	var node := get_tree().get_first_node_in_group("gravity_field_debug")
	return node if node != null and is_instance_valid(node) else null


func _camera() -> Node:
	for cam in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(cam) and cam.get_tree() != null:
			return cam
	return null
