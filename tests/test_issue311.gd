extends Node
## Regression check for issue #311: "all names and hp text should be shown
## in the current coordinate system".
##
## Issue #289 added the CHARACTER camera: the view rotates with the
## figure's gravity frame. The per-figure HUD (name label, health bar,
## shield, debug HP number) was kept world-aligned (#270), so under the
## rotating view the names and HP text rendered tilted — upside-down
## after a central-line flip.
##
## The fix (scripts/HudPose.gd, wired in Player/Npc _physics_process)
## rotates every HUD child by the ACTIVE camera's rotation each physics
## frame, so the text lives in the coordinate system the view currently
## shows and reads upright on screen in BOTH camera types.
##
## Uses Level3, which authors a central gravity line at y = 540: a figure
## BELOW the line is pulled UP, so its frame is rotated 180° — the same
## deterministic setup as the #289 test. The figure is PINNED there
## (position + zero velocity each physics frame) instead of frozen, so
## FigurePose/HudPose keep updating while the camera eases.
##
## Checks:
##  1. Static camera: HUD rotations stay world-aligned (≈ 0).
##  2. Character camera, flipped frame: camera eases to ≈ π AND every
##     HUD child (name label, health bar, debug HP) of the player figure
##     AND an enemy NPC matches the camera angle — upright on screen.
##  3. Back to static: the HUD eases back to world-aligned (≈ 0).
##
## Run headless: godot --headless res://tests/test_issue311.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://ZoomCamera.gd")

const CENTER_LINE_Y := 540.0
const SETTLE := Vector2(400.0, CENTER_LINE_Y + 300.0)
const EPS := 0.06


## Where the flipped figure is pinned once it has settled (recorded after
## the free settle — the rest spot is where the gravity field points UP).
var _pin := Vector2.ZERO


func _ready() -> void:
	var ok := true
	# Debug visuals (DebugHp label) must exist for the HUD set to be full.
	GameConfig.debug_mode = true
	var level: Node = load("res://Level3.tscn").instantiate()
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
	var npc: Node2D = null
	for n in get_tree().get_nodes_in_group("enemy_team"):
		if is_instance_valid(n):
			npc = n
			break
	var setup_ok: bool = cam != null and member != null
	print("ISSUE311 cam=", cam != null, " member=", setup_ok, " npc=", npc != null)
	ok = ok and setup_ok

	if setup_ok:
		# Drop the figure below the central line and let it SETTLE first —
		# only at the rest spot does the gravity field point UP (the same
		# rest spot the #289 test freezes its figure at). Pinning at the raw
		# teleport point would keep it in a DOWN-gravity zone.
		member.global_position = SETTLE
		for i in 10:
			await get_tree().physics_frame
		_pin = member.global_position
	for i in 5:
		_pin_member()
		await get_tree().physics_frame
	var flipped: bool = member != null and is_instance_valid(member) \
			and member.current_gravity().dot(Vector2.UP) > 0.99
	print("ISSUE311 frame_flipped=", flipped, " pin=", _pin)
	ok = ok and flipped

	# --- 1. Static camera: HUD stays world-aligned (≈ 0). ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	for i in 60:
		_pin_member()
		await get_tree().physics_frame
	var static_ok: bool = setup_ok and absf(cam.rotation) < EPS \
			and _hud_upright(member, 0.0) and _hud_upright(npc, 0.0)
	print("ISSUE311 static hud_world_aligned=", static_ok)
	ok = ok and static_ok

	# --- 2. Character camera: view eases to the flipped frame (≈ π) and
	# every HUD child of BOTH figure types matches the view angle. ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_CHARACTER
	for i in 240:
		_pin_member()
		await get_tree().physics_frame
	var cam_rot := wrapf(cam.rotation, -PI, PI)
	var view_ok: bool = setup_ok and absf(absf(cam_rot) - PI) < EPS
	var hud_ok: bool = setup_ok and _hud_upright(member, cam.rotation) \
			and _hud_upright(npc, cam.rotation)
	print("ISSUE311 character cam_rot=", cam_rot,
			" view_ok=", view_ok, " hud_matches_view=", hud_ok)
	ok = ok and view_ok and hud_ok

	# --- 3. Back to static: the HUD eases back to world-aligned. ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	for i in 240:
		_pin_member()
		await get_tree().physics_frame
	var back_ok: bool = setup_ok and absf(cam.rotation) < EPS \
			and _hud_upright(member, 0.0) and _hud_upright(npc, 0.0)
	print("ISSUE311 back_to_static=", back_ok)
	ok = ok and back_ok

	print("ISSUE311 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Keep the flipped figure pinned at its settled rest spot so the frame
## stays rotated 180° WITHOUT freezing its physics (FigurePose/HudPose must
## keep running).
func _pin_member() -> void:
	if _pin == Vector2.ZERO:
		return
	for m in get_tree().get_nodes_in_group("player_team"):
		if m.get("controlled") == true and is_instance_valid(m):
			m.velocity = Vector2.ZERO
			m.global_position = _pin
			return


## Every HUD child of `figure` (name label, health bar, debug HP) must sit
## at `angle` (the coordinate system the view currently shows) so it reads
## upright on screen; missing optional bits (debug label, a dead NPC) are
## reported as failures only when the figure itself exists.
func _hud_upright(figure: Node2D, angle: float) -> bool:
	if figure == null or not is_instance_valid(figure):
		return false
	var checked := 0
	for child in figure.get_children():
		if not HudPose.is_hud_child(child):
			continue
		checked += 1
		if absf(wrapf(child.rotation - angle, -PI, PI)) > EPS:
			return false
	return checked >= 2
