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
##  1. Static camera: HUD rotations stay world-aligned (≈ 0); record
##     where each HUD rect sits on screen in that frame.
##  2. Character camera, flipped frame: camera eases to ≈ π AND every
##     HUD child (name label, health bar, debug HP) of the player figure
##     AND an enemy NPC matches the camera angle — upright on screen —
##     AND (rework) each rect sits at the SAME screen spot as in the
##     static frame: the HUD offsets rotate into the view frame around
##     the FIGURE ORIGIN, so the name stays ABOVE the head on screen
##     instead of sliding below the flipped figure.
##  3. Back to static: the HUD eases back to world-aligned (≈ 0) and the
##     same screen spots again.
##
## Run headless: godot --headless res://tests/test_issue311.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

const CENTER_LINE_Y := 540.0
const SETTLE := Vector2(400.0, CENTER_LINE_Y + 300.0)
const EPS := 0.06


## Where the flipped figure is pinned once it has settled (recorded after
## the free settle — the rest spot is where the gravity field points UP).
var _pin := Vector2.ZERO

## Screen-frame centre of every visible HUD rect while the STATIC camera
## held (rotation 0) — key is the child's instance id. The character-camera
## phases must land on the same spots (issue #311 rework).
var _static_centers := {}


func _ready() -> void:
	var ok := true
	# Debug visuals (DebugHp label) must exist for the HUD set to be full.
	GameConfig.debug_mode = true
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
	_record_static(member)
	_record_static(npc)
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
	var spot_ok: bool = setup_ok and _hud_same_spot(member, cam.rotation) \
			and _hud_same_spot(npc, cam.rotation)
	print("ISSUE311 character cam_rot=", cam_rot,
			" view_ok=", view_ok, " hud_matches_view=", hud_ok,
			" hud_same_spot=", spot_ok)
	ok = ok and view_ok and hud_ok and spot_ok

	# --- 3. Back to static: the HUD eases back to world-aligned. ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	for i in 240:
		_pin_member()
		await get_tree().physics_frame
	var back_ok: bool = setup_ok and absf(cam.rotation) < EPS \
			and _hud_upright(member, 0.0) and _hud_upright(npc, 0.0) \
			and _hud_same_spot(member, 0.0) and _hud_same_spot(npc, 0.0)
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


## Remember where every visible HUD rect's centre sits on screen while the
## view is world-aligned (static camera) — the reference spot the rotated
## view must reproduce (issue #311 rework).
func _record_static(figure: Node2D) -> void:
	if figure == null or not is_instance_valid(figure):
		return
	for child in figure.get_children():
		if HudPose.is_hud_child(child) and child.visible:
			_static_centers[child.get_instance_id()] = _screen_center(child, 0.0)


## The rect's centre in the view frame: rotate the figure-space centre by
## the OPPOSITE of the view rotation (a view rotated by r shows world
## content rotated by -r on screen).
func _screen_center(child: Control, cam_rotation: float) -> Vector2:
	var pivot: Vector2 = child.pivot_offset
	var local: Vector2 = child.size / 2.0
	var in_figure: Vector2 = child.position + pivot \
			+ (local - pivot).rotated(child.rotation)
	return in_figure.rotated(-cam_rotation)


## Under ANY view rotation every visible HUD rect must sit at the SAME
## screen spot the static camera showed (name above the head, bar under
## it) — the rework: spinning around the rect centre kept world-frame
## offsets, sliding the cluster below a 180°-flipped figure on screen.
func _hud_same_spot(figure: Node2D, cam_rotation: float) -> bool:
	if figure == null or not is_instance_valid(figure):
		return false
	var compared := 0
	for child in figure.get_children():
		if not HudPose.is_hud_child(child) or not child.visible:
			continue
		var key := child.get_instance_id()
		if not _static_centers.has(key):
			continue
		compared += 1
		var want: Vector2 = _static_centers[key]
		if (_screen_center(child, cam_rotation) - want).length() > 1.0:
			print("ISSUE311 spot_mismatch on ", child.name,
					" got ", _screen_center(child, cam_rotation),
					" want ", want)
			return false
	return compared >= 2
