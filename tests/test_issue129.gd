extends Node
## Regression check for issue #129: in the mobile (touchscreen) version the
## weapon inventory must be BIGGER and CENTERED on the screen.
##
## Headless runs have no touchscreen, so the test calls
## WeaponInventory._apply_mobile_layout() directly (the same path taken in
## _ready when DisplayServer.is_touchscreen_available() is true) and asserts:
##   - the panel anchors are CENTER with zeroed offsets;
##   - slots grew from 60x44 to 120x88;
##   - the PC layout is unaffected when the method is not called
##     (bottom-right anchors preserved before applying).
##
## Run headless: godot --headless res://tests/test_issue129.tscn
## Exit code 0 = pass.

func _ready() -> void:
	# Allow the autoload _ready to run first.
	await get_tree().process_frame
	var inv := WeaponInventory
	var panel: PanelContainer = inv._panel
	var is_center_anchors := func(c: Control) -> bool:
		return c.anchor_left == 0.5 and c.anchor_right == 0.5 \
			and c.anchor_top == 0.5 and c.anchor_bottom == 0.5
	# PC layout: bottom-right before the mobile layout is applied.
	var pc_ok: bool = not is_center_anchors.call(panel)
	# Apply the mobile layout (the touchscreen path).
	inv._apply_mobile_layout()
	var centered: bool = is_center_anchors.call(panel)
	var zeroed: bool = panel.offset_left == 0.0 and panel.offset_right == 0.0 \
		and panel.offset_top == 0.0 and panel.offset_bottom == 0.0
	var slot: Button = inv._slots[0]
	var big_slots: bool = slot.custom_minimum_size == Vector2(120, 88)
	var idempotent: bool = true
	inv._apply_mobile_layout()
	# Second call must not change anything (still centered, same slot size).
	idempotent = is_center_anchors.call(panel) \
		and slot.custom_minimum_size == Vector2(120, 88)
	if pc_ok and centered and zeroed and big_slots and idempotent:
		print("ISSUE129 OK: mobile inventory centered and enlarged")
		get_tree().quit(0)
	else:
		print("ISSUE129 FAIL pc_ok=%s centered=%s zeroed=%s big_slots=%s idempotent=%s" \
			% [pc_ok, centered, zeroed, big_slots, idempotent])
		get_tree().quit(1)
