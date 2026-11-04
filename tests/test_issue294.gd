extends Node
## Regression check for issue #294: "add the hotkeys settings; change
## the space with the c key to change camera type".
##
## Root cause of the Space complaint: the camera-type Button kept keyboard
## focus after a click, and Godot activates a focused button on Space —
## the JUMP key — so after one click on the CAM button every jump also
## flipped the camera. The fix: the button never takes focus, and the
## camera type is switched by the "camera_switch" action (default C),
## rebindable in the new hotkeys settings screen.
##
## Checks:
##  1. The "camera_switch" action exists and its default binding is C.
##  2. The CameraSwitch button cannot take keyboard focus (Space must
##     stay the jump key, not a second camera switch).
##  3. A C key event through CameraSwitch._unhandled_input flips the
##     camera mode; a Space event does not.
##  4. GameConfig.set_hotkey rebinds an action in the InputMap (exactly
##     ONE event with the new physical key) and persists it to
##     user://settings.cfg (a fresh load applies it again).
##  5. reset_hotkeys restores the authored defaults (move_left gets its
##     TWO events back: A and Left; camera_switch back to C).
##  6. The hotkeys screen builds one row per action and the settings
##     menu has the Hotkeys entry.
##
## Run headless: godot --headless res://tests/test_issue294.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://ZoomCamera.gd")
const CameraSwitchScript := preload("res://CameraSwitch.gd")
const GameConfigScript := preload("res://scripts/GameConfig.gd")


func _ready() -> void:
	var ok := true

	# --- 1. The camera action exists, default bound to C. ---
	var action_ok := InputMap.has_action("camera_switch")
	var bound_to_c := false
	if action_ok:
		for event in InputMap.action_get_events("camera_switch"):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_C:
				bound_to_c = true
	print("ISSUE294 action=", action_ok, " default_c=", bound_to_c)
	ok = ok and action_ok and bound_to_c

	# Snapshot the authored defaults BEFORE any rebinding below.
	GameConfigScript.capture_hotkey_defaults()

	# --- 2 + 3. The switch button ignores focus; C flips, Space does not. ---
	var switch: CanvasLayer = CameraSwitchScript.new()
	add_child(switch)
	await get_tree().physics_frame
	var switch_button: Button = null
	for child in switch.get_children():
		if child is Button:
			switch_button = child
	var focus_ok: bool = switch_button != null \
			and switch_button.focus_mode == Control.FOCUS_NONE
	print("ISSUE294 button=", switch_button != null, " focus_none=", focus_ok)
	ok = ok and focus_ok

	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	switch._unhandled_input(_key_event(KEY_C))
	var c_flips: bool = ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_CHARACTER
	switch._unhandled_input(_key_event(KEY_C))
	var c_toggles_back: bool = ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	switch._unhandled_input(_key_event(KEY_SPACE))
	var space_idle: bool = ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	print("ISSUE294 c_flips=", c_flips, " c_back=", c_toggles_back,
			" space_idle=", space_idle)
	ok = ok and c_flips and c_toggles_back and space_idle

	# --- 4. Rebind one action: InputMap + persistence. ---
	GameConfigScript.set_hotkey("camera_switch", KEY_X)
	var events := InputMap.action_get_events("camera_switch")
	var rebound: bool = events.size() == 1 and events[0] is InputEventKey \
			and (events[0] as InputEventKey).physical_keycode == KEY_X
	var reloaded: bool = false
	var cfg := ConfigFile.new()
	if cfg.load(GameConfigScript.SETTINGS_PATH) == OK:
		var saved: Dictionary = cfg.get_value("hotkeys", "bindings", {})
		reloaded = int(saved.get("camera_switch", 0)) == KEY_X
	# A fresh startup load applies the saved binding over the defaults.
	GameConfigScript.hotkeys = {}
	GameConfigScript.load_settings()
	var applied: bool = false
	for event in InputMap.action_get_events("camera_switch"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_X:
			applied = true
	print("ISSUE294 rebound=", rebound, " persisted=", reloaded,
			" applied_on_load=", applied)
	ok = ok and rebound and reloaded and applied

	# --- 5. Reset restores the authored defaults. ---
	GameConfigScript.reset_hotkeys()
	var reset_move: int = InputMap.action_get_events("move_left").size()
	var reset_cam := false
	for event in InputMap.action_get_events("camera_switch"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_C:
			reset_cam = true
	var reset_saved: bool = false
	var cfg2 := ConfigFile.new()
	if cfg2.load(GameConfigScript.SETTINGS_PATH) == OK:
		reset_saved = (cfg2.get_value("hotkeys", "bindings", {}) as Dictionary).is_empty()
	print("ISSUE294 reset_move_events=", reset_move, " reset_c=", reset_cam,
			" reset_saved=", reset_saved)
	ok = ok and reset_move == 2 and reset_cam and reset_saved

	# --- 6. The screens: hotkeys rows + the settings entry. ---
	var hotkeys_menu: Node = load("res://HotkeysMenu.tscn").instantiate()
	add_child(hotkeys_menu)
	await get_tree().physics_frame
	var rows: VBoxContainer = hotkeys_menu.get_node("%Rows") as VBoxContainer
	var rows_ok: bool = rows != null \
			and rows.get_child_count() == GameConfigScript.HOTKEY_ACTIONS.size()
	var labels_ok := true
	if rows_ok:
		for row in rows.get_children():
			var key_button: Button = row.get_node_or_null("Key") as Button
			if key_button == null or key_button.text.is_empty():
				labels_ok = false
	var settings_menu: Node = load("res://SettingsMenu.tscn").instantiate()
	add_child(settings_menu)
	await get_tree().physics_frame
	var entry_ok: bool = settings_menu.get_node_or_null("%HotkeysButton") != null
	print("ISSUE294 rows=", rows_ok, " labels=", labels_ok,
			" settings_entry=", entry_ok)
	ok = ok and rows_ok and labels_ok and entry_ok

	print("ISSUE294 ok=", ok)
	get_tree().quit(0 if ok else 1)


## A pressed, non-echo key event with the given PHYSICAL keycode —
## exactly what _unhandled_input receives for a real key press.
func _key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	event.pressed = true
	event.echo = false
	return event
