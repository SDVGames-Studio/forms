extends Node
## Regression check for issue #322: "incorrect place of power indicator".
##
## The charge bar (the power indicator shown while holding F on a charged
## weapon) is a Control child of the figure's Weapon node, authored above
## the wielder in the WEAPON's local frame. The weapon rides the figure's
## gravity frame, so on a level whose gravity is rotated 180° (Level3's
## central gravity line) the bar rendered BELOW the wielder, upside-down,
## while charging — the same class of bug the HUD had before #311's
## HudPose rework.
##
## The fix (Weapon._align_charge_bar_to_view, wired in Weapon
## _physics_process) rotates the bar around the wielder's origin into the
## coordinate system the CURRENT view shows, every tick the charge is up.
##
## Uses Level3, which authors a central gravity line at y = 540: a figure
## BELOW the line is pulled UP, so its frame is rotated 180° — the same
## deterministic setup as the #289/#311 tests. The figure is PINNED there
## (position + zero velocity each physics frame) so FigurePose keeps
## updating while the camera eases. The charge is driven directly
## (`weapon._charging = true`, grenade selected) so no input simulation
## is needed; it is never released, so nothing is fired.
##
## Checks, in both camera types:
##   1. the bar is visible while charging;
##   2. it is UPRIGHT in the view frame (its rotation matches the camera
##      angle minus everything it inherits from the figure chain);
##   3. its centre sits ABOVE the wielder's origin (~54 px, centred) in
##      the view frame — the old code left it in the weapon frame, which
##      flips it 180° to BELOW the figure on this level.
##
## Run headless: godot --headless res://tests/test_issue322.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

const CENTER_LINE_Y := 540.0
const SETTLE := Vector2(400.0, CENTER_LINE_Y + 300.0)
const EPS := 0.06

## Where the flipped figure is pinned once it has settled (recorded after
## the free settle — the rest spot is where the gravity field points UP).
var _pin := Vector2.ZERO


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
	var weapon: Node = null
	if member != null:
		weapon = member.get_node_or_null("Weapon")
	var setup_ok: bool = cam != null and member != null and weapon != null
	print("ISSUE322 cam=", cam != null, " member=", member != null,
			" weapon=", weapon != null)
	ok = ok and setup_ok

	if setup_ok:
		# Drop the figure below the central line and let it SETTLE first —
		# only at the rest spot does the gravity field point UP (the same
		# rest spot the #289/#311 tests pin their figure at).
		member.global_position = SETTLE
		for i in 10:
			await get_tree().physics_frame
		_pin = member.global_position
	for i in 5:
		_pin_member()
		await get_tree().physics_frame
	var flipped: bool = member != null and is_instance_valid(member) \
			and member.current_gravity().dot(Vector2.UP) > 0.99
	print("ISSUE322 frame_flipped=", flipped, " pin=", _pin)
	ok = ok and flipped

	if setup_ok:
		# A charged weapon (grenade, index 2) and a live charge held for
		# the whole check — the bar must be up from the next tick on and
		# nothing is fired (the shoot action is never released). The level
		# may take a moment to start the player's turn (before it does the
		# weapon is not `controlled` and ticks nothing), so wait bounded for
		# the FIRST charge tick before checking anything.
		WeaponInventory.selected_weapon = 2
		weapon._charging = true
		var waited := 0
		while not weapon._charge_bar.visible and waited < 300:
			_pin_member()
			await get_tree().physics_frame
			waited += 1
		if not weapon._charge_bar.visible:
			print("ISSUE322 charge_never_ticked waited=", waited)
			ok = false

	# --- 1. Static camera: the view stays world-aligned; the bar must be
	# upright and ABOVE the wielder on screen. ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	for i in 60:
		_pin_member()
		await get_tree().physics_frame
	var static_ok: bool = _charge_checks(cam.rotation, "static")
	print("ISSUE322 static power_bar_upright_above=", static_ok)
	ok = ok and static_ok

	# --- 2. Character camera: the view eases to the flipped frame (≈ π);
	# the bar rides the ease and stays upright above the wielder. ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_CHARACTER
	for i in 240:
		_pin_member()
		await get_tree().physics_frame
	var cam_rot := wrapf(cam.rotation, -PI, PI)
	var view_ok: bool = absf(absf(cam_rot) - PI) < EPS
	var char_ok: bool = _charge_checks(cam.rotation, "character")
	print("ISSUE322 character cam_rot=", cam_rot, " view_ok=", view_ok,
			" power_bar_upright_above=", char_ok)
	ok = ok and view_ok and char_ok

	print("ISSUE322 ok=", ok)
	get_tree().quit(0 if ok else 1)


## Keep the flipped figure pinned at its settled rest spot so the frame
## stays rotated 180° WITHOUT freezing its physics (the weapon's own
## _physics_process must keep running to re-aim the bar each tick).
func _pin_member() -> void:
	if _pin == Vector2.ZERO:
		return
	for m in get_tree().get_nodes_in_group("player_team"):
		if m.get("controlled") == true and is_instance_valid(m):
			m.velocity = Vector2.ZERO
			m.global_position = _pin
			return


## The charge bar must be visible, UPRIGHT in the frame the view shows
## (its rotation = view rotation minus everything it inherits through the
## figure chain), and its centre ~54 px ABOVE the wielder's origin in the
## view frame. The old code left it in the weapon's local frame, which on
## this 180°-flipped figure rendered it BELOW, upside-down.
func _charge_checks(cam_rotation: float, label: String) -> bool:
	var member: Node2D = null
	for m in get_tree().get_nodes_in_group("player_team"):
		if m.get("controlled") == true and is_instance_valid(m):
			member = m
			break
	if member == null:
		return false
	var weapon: Node = member.get_node_or_null("Weapon")
	if weapon == null or not weapon._charge_bar.visible:
		print("ISSUE322 ", label, ": charge bar not visible")
		return false
	var bar: ColorRect = weapon._charge_bar
	var upright: bool = absf(wrapf(bar.rotation + weapon.global_rotation \
			- cam_rotation, -PI, PI)) < EPS
	var center: Vector2 = _bar_center(bar, cam_rotation)
	var above: bool = center.y < -50.0 and absf(center.x) < 1.0
	if not (upright and above):
		print("ISSUE322 ", label, ": upright=", upright,
				" center=", center, " (want ~(0, -54))")
	return upright and above


## The bar's centre relative to the wielder's origin (the weapon node sits
## on it), expressed in the view frame: rotate the figure-space centre by
## the OPPOSITE of the view rotation (a view rotated by r shows world
## content rotated by -r on screen).
func _bar_center(bar: Control, cam_rotation: float) -> Vector2:
	var pivot: Vector2 = bar.pivot_offset
	var local: Vector2 = bar.size / 2.0
	var in_figure: Vector2 = bar.position + pivot \
			+ (local - pivot).rotated(bar.rotation)
	return in_figure.rotated(-cam_rotation)
