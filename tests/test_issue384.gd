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
## Run headless: godot --headless res://tests/test_issue384.tscn
## Exit code 0 = pass.


func _ready() -> void:
	var ok := true
	GameConfig.debug_gravity_field = false
	var level: Node = load("res://Level2.tscn").instantiate()
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

	print("ISSUE384 ok=", ok)
	GameConfig.debug_gravity_field = false
	get_tree().quit(0 if ok else 1)


func _overlay() -> Node:
	var node := get_tree().get_first_node_in_group("gravity_field_debug")
	return node if node != null and is_instance_valid(node) else null


func _camera() -> Node:
	for cam in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(cam) and cam.get_tree() != null:
			return cam
	return null
