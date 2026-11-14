extends Node
## Regression check for issue #328: "character shouldn't be able to
## teleport into the ground".
##
## The teleport tool click (ToolInventory.gd, #170) used to move the
## member to ANY clicked point — including deep inside terrain. Now the
## click is resolved against the solid ground first:
##   1. a click in the open teleports exactly there (unchanged);
##   2. a click buried LESS than two character widths from open space
##      snaps to the nearest open spot ("target should move there");
##   3. a deeper click is IGNORED — no move, no spent use, the tool
##      stays armed so another point can simply be picked.
##
## Part A probes the resolver against a synthetic 400x400 block
## (deterministic geometry, before any level loads). Part B replays the
## real click path in Level3 (Input.parse_input_event) on self-located
## terrain points and checks the quota/arming side effects too. The
## figure AND its follow camera are awaited to rest before each click:
## a queued click is unwrapped a frame later and its world point is
## rebuilt from the canvas transform AT THAT MOMENT, so a gliding
## camera would shift the destination and test the wrong point.
##
## Run headless: godot --headless res://tests/test_issue328.tscn
## Exit code 0 = pass.

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE328 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	await _part_a_synthetic()
	await _part_b_level3()
	print("ISSUE328 ok=", _fails.is_empty())
	for f in _fails:
		print("ISSUE328 failed: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## --- Part A: the resolver against a synthetic block ------------------
## Solid x/y in [-200, 200]; open space starts 200 px from the centre.
func _part_a_synthetic() -> void:
	var prober := Node2D.new()
	add_child(prober)
	var block := StaticBody2D.new()
	block.collision_layer = 1
	block.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400, 400)
	shape.shape = rect
	block.add_child(shape)
	add_child(block)
	for i in 5:
		await get_tree().physics_frame
	var space := prober.get_world_2d().direct_space_state

	# 1) Open click: returned exactly as-is.
	var open = ToolInventory._resolve_teleport_destination(prober, Vector2(600, 0))
	_check("A open click returns the point itself",
		typeof(open) == TYPE_VECTOR2 and open == Vector2(600, 0))

	# 2) Click 10 px inside the edge: snaps to a free spot within two
	#    character widths (default capsule 48 wide -> reach 96 px).
	var snapped = ToolInventory._resolve_teleport_destination(prober, Vector2(190, 0))
	var snap_ok := typeof(snapped) == TYPE_VECTOR2
	if snap_ok:
		snap_ok = ToolInventory._teleport_spot_free(space, snapped) \
			and snapped.distance_to(Vector2(190, 0)) <= 96.0
	_check("A near-edge click snaps into the open (free, <= 2 widths)", snap_ok)

	# 3) Block centre — 200 px from any open space: ignored.
	_check("A deep click is ignored (null)",
		ToolInventory._resolve_teleport_destination(prober, Vector2(0, 0)) == null)

	# 4) The reach comes from the body's own shape: a radius-60 body
	#    (width 120 -> reach 240) escapes even from the centre.
	var big := CharacterBody2D.new()
	big.collision_layer = 0
	big.collision_mask = 0
	var big_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 60.0
	big_shape.shape = circle
	big.add_child(big_shape)
	add_child(big)
	for i in 2:
		await get_tree().physics_frame
	var wide = ToolInventory._resolve_teleport_destination(big, Vector2(0, 0))
	var wide_ok := typeof(wide) == TYPE_VECTOR2
	if wide_ok:
		wide_ok = ToolInventory._teleport_spot_free(space, wide) \
			and wide.distance_to(Vector2(0, 0)) <= 240.0
	_check("A wide body reaches further (shape-derived width)", wide_ok)

	big.free()
	block.free()
	prober.free()


## --- Part B: the real click path in Level3 ---------------------------
func _part_b_level3() -> void:
	var level: Node = load("res://scenes/levels/Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	var inv: Node = get_node("/root/WeaponInventory")
	# Wait for the player's turn to begin (an enemy team may move first).
	for i in 3600:
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			break
	if tc.active_team != "player" or tc.active_member == null:
		_check("B player turn with an active member", false)
		return
	var member: Node2D = tc.active_member
	_await_settled(member, 300)
	if tc.active_member != member:
		_check("B active member kept across the test", false)
		return
	var space := member.get_world_2d().direct_space_state

	# Self-locate the three terrain flavours: open sky, a point buried
	# near the surface (snappable) and one buried deep (ignorable).
	var open_pt: Variant = _scan_grid(member, space, "open")
	var near_pt: Variant = _scan_grid(member, space, "near")
	var deep_pt: Variant = _scan_grid(member, space, "deep")
	print("ISSUE328 B terrain open=", open_pt, " near=", near_pt, " deep=", deep_pt)
	_check("B level has open/near/deep probe points",
		open_pt != null and near_pt != null and deep_pt != null)
	if open_pt == null or near_pt == null or deep_pt == null:
		return

	ToolInventory.reset_turn()
	_check("B teleport arms",
		ToolInventory.use_tool(ToolInventory.TOOL_TELEPORT)
			and ToolInventory.armed_tool == ToolInventory.TOOL_TELEPORT)

	# 1) Deep click: ignored — no move, the tool stays armed, budget
	#    unspent. (Leftover enemy fire during the settle could have
	#    carved the terrain — re-pick the deep point if it went snappable.)
	if ToolInventory._resolve_teleport_destination(member, deep_pt) != null:
		deep_pt = _scan_grid(member, space, "deep")
	var before: Vector2 = member.global_position
	_click_world(deep_pt)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("B deep click does not move the member",
		member.global_position.distance_to(before) < 5.0)
	_check("B deep click keeps the tool armed",
		ToolInventory.armed_tool == ToolInventory.TOOL_TELEPORT)
	_check("B deep click spends no use",
		inv.tool_uses_left("player", ToolInventory.TOOL_TELEPORT) == 5)

	# 2) Near-edge click: the member lands on the resolved open spot —
	#    free of terrain and within two character widths of the click
	#    (body depenetration may nudge it a body-width further out).
	before = member.global_position
	_click_world(near_pt)
	await get_tree().process_frame
	await get_tree().process_frame
	var settled := await _await_settled(member, 480)
	_check("B scene settled after the near-edge landing", settled)
	_check("B near-edge click lands OUT of the ground (free spot)",
		ToolInventory._teleport_spot_free(space, member.global_position))
	_check("B near-edge click lands near the click (<= 2 widths + body)",
		member.global_position.distance_to(near_pt)
			<= ToolInventory._character_width(member) * 2.5)
	_check("B near-edge click actually moved the member",
		member.global_position.distance_to(before)
			> ToolInventory._character_width(member))
	_check("B near-edge click disarms", ToolInventory.armed_tool == -1)
	_check("B near-edge click spends one use (5 -> 4)",
		inv.tool_uses_left("player", ToolInventory.TOOL_TELEPORT) == 4)

	# 3) Open click: unchanged — exact landing, one use.
	if tc.active_member != member:
		_check("B active member kept across the test", false)
		return
	ToolInventory.reset_turn()
	ToolInventory.use_tool(ToolInventory.TOOL_TELEPORT)
	_click_world(open_pt)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("B open click lands on the clicked point",
		member.global_position.distance_to(open_pt) < 8.0)
	_check("B open click spends one use (4 -> 3)",
		inv.tool_uses_left("player", ToolInventory.TOOL_TELEPORT) == 3)


## First grid point of the wanted kind: "open" (clear sky), "near"
## (buried but snappable — the resolver returns a spot) or "deep"
## (buried too deep — the resolver returns null).
func _scan_grid(member: Node2D, space: PhysicsDirectSpaceState2D, kind: String) -> Variant:
	for y in range(80, 940, 40):
		for x in range(80, 1080, 80):
			var p := Vector2(x, y)
			var clear := ToolInventory._teleport_spot_free(space, p)
			match kind:
				"open":
					if clear:
						return p
				"near":
					if not clear and typeof(ToolInventory \
							._resolve_teleport_destination(member, p)) == TYPE_VECTOR2:
						return p
				"deep":
					if not clear and ToolInventory \
							._resolve_teleport_destination(member, p) == null:
						return p
	return null


## Await until the member's body and the canvas transform (the follow
## camera — including its smoothing tail) are BOTH at rest for 30
## consecutive physics frames (0.5 s — long enough that a stop-start
## physics depenetration pause cannot pass for "at rest"), and the
## body's velocity is zero. The click's screen position is computed
## here but unwrapped a frame later; any residual motion in between
## would shift the reconstructed world point.
func _await_settled(member: Node2D, max_frames: int) -> bool:
	var calm := 0
	var last_xf := get_viewport().get_canvas_transform()
	var last_pos := member.global_position
	for i in max_frames:
		await get_tree().physics_frame
		var xf := get_viewport().get_canvas_transform()
		var pos := member.global_position
		var vel := 0.0
		if member is CharacterBody2D:
			vel = (member as CharacterBody2D).velocity.length()
		var still := last_xf.origin.distance_to(xf.origin) < 0.05 \
				and absf(last_xf.x.length() - xf.x.length()) < 0.0001 \
				and absf(last_xf.x.angle_to(xf.x)) < 0.0001 \
				and last_pos.distance_to(pos) < 0.25 \
				and vel < 1.0
		if still:
			calm += 1
			if calm >= 30:
				return true
		else:
			calm = 0
		last_xf = xf
		last_pos = pos
	return false


## Dispatch a left-click at world point `p` through the real input
## path. The injected position is treated as a WINDOW coordinate: the
## input pipeline first maps window -> viewport coords with the final
## (content-scale) transform, and only then ToolInventory inverts the
## canvas transform. On a real display final == identity (window size
## == base size), but headless runs in a 64x64 window over a 1152x648
## base — without the final transform the click lands 18x off.
func _click_world(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = get_window().get_final_transform() \
			* (get_viewport().get_canvas_transform() * p)
	Input.parse_input_event(ev)
