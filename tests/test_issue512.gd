extends Node
## Regression check for issue #512: "add on-screen touch controls in
## github [pages] on mobile browsers". The overlay must reuse the exact
## Android control set (stick + JUMP/FIRE/MENU driving the real input
## actions) and must appear on web browsers whose touchscreen the
## engine's 'ontouchstart' probe misses. A non-touch desktop — the PC
## browser on GitHub Pages — must stay control-free, exactly as before.
##
## 1. Gate closed headless: no controls are built and _process is off.
## 2. Forced build produces the full Android set (stick + 3 buttons).
## 3. The stick drives move_left/move_right through Input actions.
## 4. Buttons drive jump/shoot through Input actions.
## 5. Outside a level, _process hides the overlay and releases actions.
## 6. The JS web fallback is platform-gated: no JS probe off the web.
##
## Run headless: godot --headless res://tests/test_issue512.tscn
## Exit code 0 = pass.

const TouchControlsScript := preload("res://scripts/TouchControls.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _ready() -> void:
	await get_tree().process_frame

	# 1) Headless (no touchscreen, not web): gate closed, nothing built.
	var tc := TouchControlsScript.new()
	add_child(tc)
	await get_tree().process_frame
	_check(tc.get_child_count() == 0,
			"non-touch headless must build no controls (got %d)" % tc.get_child_count())
	_check(not tc.is_processing(),
			"non-touch headless must disable _process")
	_check(not tc._touchscreen_available(),
			"non-touch headless must fail the enable gate")

	# 2) Forced build — the full Android control set is reused verbatim.
	tc._build_ui()
	_check(tc.get_child_count() == 4,
			"stick + JUMP + FIRE + MENU must be built (got %d)" % tc.get_child_count())
	_check(InputMap.has_action("jump") and InputMap.has_action("shoot"),
			"buttons must target real input actions")

	# 3) The virtual stick drives move_left/move_right.
	var center: Vector2 = tc._stick_base.size * 0.5
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.index = 7
	press.position = center
	tc._on_stick_input(press)
	_check(not Input.is_action_pressed("move_left")
			and not Input.is_action_pressed("move_right"),
			"a centered stick must press nothing")
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = center + Vector2(TouchControlsScript.STICK_RADIUS, 0.0)
	tc._on_stick_input(drag)
	_check(Input.is_action_pressed("move_right"),
			"a full-right drag must press move_right")
	_check(not Input.is_action_pressed("move_left"),
			"a right drag must not press move_left")
	var release := InputEventScreenTouch.new()
	release.pressed = false
	release.index = 7
	tc._on_stick_input(release)
	_check(not Input.is_action_pressed("move_right"),
			"releasing the stick must release move_right")

	# 4) Buttons drive the real actions.
	tc._on_button_down("jump")
	_check(Input.is_action_pressed("jump"), "button_down must press jump")
	tc._on_button_up("jump")
	_check(not Input.is_action_pressed("jump"), "button_up must release jump")

	# 5) Outside a level: hidden and every action released.
	tc._on_button_down("shoot")
	tc._process(0.0)
	_check(not tc.visible,
			"outside a level the overlay must hide")
	_check(not Input.is_action_pressed("shoot"),
			"hiding must release held buttons")

	# 6) The JS probe stays gated to the web platform (no JS headless).
	_check(not tc._web_touch_fallback(),
			"off the web export the maxTouchPoints probe must not run")

	tc.queue_free()
	for i in 5:
		await get_tree().physics_frame

	if failures == 0:
		print("issue512: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		print("issue512: %d CHECK(S) FAILED" % failures)
		get_tree().quit(1)
