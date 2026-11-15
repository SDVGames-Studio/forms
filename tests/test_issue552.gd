extends Node
## Regression check for issue #552: "Make the new camera mode".
## The two camera types are renamed (#552): STATIC → "character global",
## CHARACTER → "character local" (same behaviour, new button labels), and a
## third type GLOBAL is added: fully independent of any figure — game
## events (turn switches, control changes, figures moving) never move the
## view; only the player's pans and zooms do.
##
## Uses Level3 exactly like test_issue289 (a real level with an authored
## shared camera and a controlled figure).
##
## Checks:
##  1. The switch button shows the renamed default "CAM: CHARACTER GLOBAL".
##  2. The #552 cycle: press → "CAM: CHARACTER LOCAL", press →
##     "CAM: GLOBAL", press → back to the default type.
##  3. GLOBAL follows nobody: with the view parked far away, moving the
##     controlled figure never drags the camera.
##  4. Leaving GLOBAL re-anchors the follow: back on the default type the
##     camera re-centers on the controlled figure.
##
## Run headless: godot --headless res://tests/test_issue552.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

const EPS := 2.0


func _ready() -> void:
	var ok := true
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
	print("ISSUE552 cam=", cam != null, " member=", member_ok)
	ok = ok and member_ok

	var switch_button: Button = null
	if member_ok:
		for child in cam.get_children():
			var path := String(child.get_script().resource_path) \
					if child.get_script() != null else ""
			if path.ends_with("CameraSwitch.gd"):
				for grand in child.get_children():
					if grand is Button:
						switch_button = grand

	# --- 1. Renamed default label (#552: "STATIC" is gone). ---
	var default_ok: bool = member_ok \
			and switch_button != null \
			and switch_button.text == "CAM: CHARACTER GLOBAL" \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	print("ISSUE552 default_label=", default_ok)
	ok = ok and default_ok

	# --- 2. The #552 3-way cycle with the renamed labels. ---
	if switch_button != null:
		switch_button.pressed.emit()
	await get_tree().physics_frame
	var local_ok: bool = member_ok \
			and switch_button != null \
			and switch_button.text == "CAM: CHARACTER LOCAL" \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_CHARACTER
	if switch_button != null:
		switch_button.pressed.emit()
	await get_tree().physics_frame
	var global_ok: bool = member_ok \
			and switch_button != null \
			and switch_button.text == "CAM: GLOBAL" \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_GLOBAL
	if switch_button != null:
		switch_button.pressed.emit()
	await get_tree().physics_frame
	var cycle_ok: bool = member_ok \
			and ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	print("ISSUE552 cycle local=", local_ok, " global=", global_ok,
			" back_to_default=", cycle_ok)
	ok = ok and local_ok and global_ok and cycle_ok

	# --- 3. GLOBAL follows nobody: park the view far away, then nudge the
	# controlled figure aside (pinned, like test_issue311) — the camera
	# must stay parked while the figure stands elsewhere. ---
	var parked_ok := false
	var recenter_ok := false
	var original := Vector2.ZERO
	var pin := Vector2.ZERO
	if member_ok:
		original = member.global_position
	if member_ok and switch_button != null:
		switch_button.pressed.emit()
		switch_button.pressed.emit()
		for i in 30:
			_pin_member(member, original)
			await get_tree().physics_frame
		var parked := Vector2(-20000.0, -20000.0)
		cam.global_position = parked
		pin = original + Vector2(300.0, 0.0)
		for i in 30:
			_pin_member(member, pin)
			await get_tree().physics_frame
		parked_ok = cam.global_position.distance_to(parked) < EPS
		# --- 4. Leaving GLOBAL re-anchors the follow (#552): one press back
		# on the default type re-centers the view on the camera's follow
		# target (the controlled figure — or the acting figure of a computer
		# team's turn, see ZoomCamera._focus_member). ---
		switch_button.pressed.emit()
		for i in 30:
			_pin_member(member, pin)
			await get_tree().physics_frame
		var target: Node2D = cam._focus_member()
		recenter_ok = target != null \
				and cam.global_position.distance_to(target.global_position) < 400.0
	print("ISSUE552 global_parked=", parked_ok,
			" follow_recenters=", recenter_ok)
	ok = ok and parked_ok and recenter_ok

	print("ISSUE552 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Freeze the figure in place (test_issue311's _pin_member approach) so
## physics drift can never blur the parked/recenter comparisons.
func _pin_member(member: Node2D, at: Vector2) -> void:
	if member == null or not is_instance_valid(member):
		return
	member.set("velocity", Vector2.ZERO)
	member.global_position = at
