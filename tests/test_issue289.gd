extends Node
## Regression check for issue #289: "Make an additional camera type".
## Two camera types: the default STATIC (world-aligned) view and the new
## CHARACTER camera aligned with the character's local coordinate system
## (the figure's gravity frame — the same frame FigurePose rotates the
## body to), switched with the bottom-left button (CameraSwitch).
## Issue #552 renamed both (STATIC → "CAM: CHARACTER GLOBAL", CHARACTER →
## "CAM: CHARACTER LOCAL"), added the third GLOBAL type and made the
## button a 3-way cycle — this test follows the new names/cycle.
##
## Uses Level3, which authors a central gravity line at y = 540: a figure
## BELOW the line is pulled UP, so its local frame is rotated 180° — a
## clearly observable, deterministic angle for the character camera.
##
## Checks:
##  1. The camera-type button exists (bottom-left CameraSwitch) and says
##     "CAM: STATIC" by default.
##  2. Static default: with the figure standing in the flipped (upside-
##     down) frame the view stays world-aligned (rotation 0).
##  3. Pressing the button switches to the character camera; the view
##     eases to the figure's frame — rotation ≈ π (feet to screen-down)
##     — and the canvas transform mirrors it (the view REALLY rotates).
##  4. Drag-panning is rotation-aware: _pan_by converts screen delta
##     through the rotated view, not the raw world axes.
##  5. Pressing again returns to the static camera (rotation back to 0).
##
## Run headless: godot --headless res://tests/test_issue289.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

const CENTER_LINE_Y := 540.0
const EPS := 0.06


func _ready() -> void:
	var ok := true
	# Issue #617: every team now defaults to the computer — this
	# regression drives the HUMAN camera flow, so opt the hero team in
	# as the player (the level configuration menu's choice) before the
	# level loads.
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	# Pin the historic STATIC cycle start BEFORE the level builds its
	# camera switch button (the label syncs at build time).
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	var level: Node = load("res://scenes/levels/Level3.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame

	var cam: Camera2D = null
	for c in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(c) and c.get_tree() != null:
			cam = c
	var member: Node2D = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if m.get("controlled") == true:
			member = m
			break
	var member_ok: bool = cam != null and member != null
	print("ISSUE289 cam=", cam != null, " member=", member_ok)
	ok = ok and member_ok

	# --- 1. The switch button exists, default type is STATIC. ---
	var switch_button: Button = null
	if member_ok:
		for child in cam.get_children():
			var path := String(child.get_script().resource_path) \
					if child.get_script() != null else ""
			if path.ends_with("CameraSwitch.gd"):
				for grand in child.get_children():
					if grand is Button:
						switch_button = grand
	var button_ok: bool = switch_button != null \
			and switch_button.text == "CAM: CHARACTER GLOBAL" \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	print("ISSUE289 button=", switch_button != null,
			" label=", switch_button.text if switch_button != null else "—",
			" mode=static")
	ok = ok and button_ok

	if member_ok:
		# Stand the figure BELOW the central line: gravity flips to UP, so
		# its frame is rotated 180°. Freeze it there so it cannot fall back.
		member.global_position = Vector2(400.0, CENTER_LINE_Y + 300.0)
		for i in 5:
			await get_tree().physics_frame
		member.set_physics_process(false)
	var frame_flipped: bool = member_ok and is_instance_valid(member) \
			and member.current_gravity().dot(Vector2.UP) > 0.99
	print("ISSUE289 frame_flipped=", frame_flipped)
	ok = ok and frame_flipped

	# Issue #617 rework v2: the defaults field THREE teams — pin the
	# camera window deterministically: land on a PLAYER turn (skipping
	# computer turns, whose "enemy:<color>" ids are not the legacy
	# "enemy") and stretch the turn timer so no hand-over retargets the
	# camera mid-ease (the ease needs the full 240-frame window).
	GameConfig.turn_time = 600.0
	var waited := 0.0
	while TurnController.active_team != "player" and waited < 20.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		if TurnController.active_team != "player" \
				and TurnController.active_team != "":
			TurnController._end_turn()
			for i in 5:
				await get_tree().physics_frame
			waited = 0.0
	TurnController.active_member = member

	# --- 2. Static default: the view stays world-aligned anyway. ---
	for i in 60:
		await get_tree().physics_frame
	var static_ok: bool = member_ok and absf(cam.rotation) < EPS
	print("ISSUE289 static_rotation=", absf(cam.rotation) if member_ok else -1.0,
			" ok=", static_ok)
	ok = ok and static_ok

	# --- 3. Character camera: the view eases onto the figure's frame. ---
	if switch_button != null:
		switch_button.pressed.emit()
	for i in 240:
		await get_tree().physics_frame
	var target := PI
	var rotated: bool = member_ok \
			and absf(wrapf(cam.rotation - target, -PI, PI)) < EPS
	var label_ok: bool = switch_button != null \
			and switch_button.text == "CAM: CHARACTER LOCAL"
	var canvas_rotated := false
	if member_ok:
		# The canvas transform is the VIEW transform: it must carry the
		# opposite rotation (world rotated by -camera angle on screen).
		var view_rot := get_viewport().get_canvas_transform().get_rotation()
		canvas_rotated = absf(wrapf(view_rot + cam.rotation, -PI, PI)) < 0.1
	print("ISSUE289 character_rotation=", cam.rotation if member_ok else -99.0,
			" rotated=", rotated, " label=", label_ok,
			" canvas_rotated=", canvas_rotated)
	ok = ok and rotated and label_ok and canvas_rotated

	# --- 4. Drag-pan is rotation-aware (screen delta -> world frame). ---
	var pan_ok := false
	if member_ok:
		var start := cam.global_position
		var delta_screen := Vector2(100.0, 0.0)
		cam._pan_by(delta_screen)
		var expected := start - delta_screen.rotated(cam.rotation) / cam.zoom.x
		pan_ok = cam.global_position.distance_to(expected) < 0.001
	print("ISSUE289 pan_rotation_aware=", pan_ok)
	ok = ok and pan_ok

	# --- 5. Back to the default type — the #552 cycle needs TWO presses
	# from character local: GLOBAL first (view world-aligned again), then
	# the default character-global follow type. ---
	if switch_button != null:
		switch_button.pressed.emit()
	for i in 240:
		await get_tree().physics_frame
	var global_ok: bool = member_ok and absf(cam.rotation) < EPS \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_GLOBAL
	print("ISSUE289 global_untilts=", global_ok)
	ok = ok and global_ok
	if switch_button != null:
		switch_button.pressed.emit()
	for i in 60:
		await get_tree().physics_frame
	var back_ok: bool = member_ok and absf(cam.rotation) < EPS \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	print("ISSUE289 back_to_static=", back_ok)
	ok = ok and back_ok

	print("ISSUE289 ok=", ok)
	get_tree().quit(0 if ok else 1)
