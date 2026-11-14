extends Node
## Regression check for issue #353: "clickable interface buttons in the
## in-game menu" — while the pause menu was open, the inventory and the
## camera-type buttons kept floating above the pause dim and stayed
## clickable, because GUI input is NOT blocked by SceneTree pause and
## both HUD layers draw above the in-game menu's dim.
##
## Root cause: CameraSwitch sits on layer 12 (above the menu's layer 10)
## and WeaponInventory shares layer 10 but is the LATER autoload, so it
## also draws above the dim. Both layers now hide themselves while the
## tree is paused, and their key shortcuts (C / weapon hotkeys) no
## longer act from behind the pause menu.
##
## Checks:
##  1. In a level, unpaused: both HUD layers are visible.
##  2. Paused (in-game menu open): both layers hide.
##  3. The C key ("camera_switch") does not flip the camera while
##     paused.
##  4. A weapon hotkey does not reselect a weapon while paused.
##  5. Unpausing restores both layers.
##
## Run headless: godot --headless res://tests/test_issue353.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")
const CameraSwitchScript := preload("res://scripts/CameraSwitch.gd")


func _ready() -> void:
	# The test itself must keep running while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ok := true

	# A fake level root so WeaponInventory treats this scene as gameplay
	# (its _process hides the layer outside levels).
	var level := Node.new()
	level.name = "FakeLevel"
	level.add_to_group("level")
	add_child(level)

	# The camera-type button layer (ZoomCamera builds it in real levels).
	var switch: CanvasLayer = CameraSwitchScript.new()
	add_child(switch)
	await get_tree().physics_frame

	var inv: CanvasLayer = get_node("/root/WeaponInventory")

	# --- 1. Unpaused baseline: both HUD layers visible in a level. ---
	inv._process(0.0)
	switch._process(0.0)
	var base_inv: bool = inv.visible
	var base_switch: bool = switch.visible
	print("ISSUE353 base inv=", base_inv, " switch=", base_switch)
	ok = ok and base_inv and base_switch

	# --- 2. Paused: the in-game menu hides both layers. ---
	get_tree().paused = true
	inv._process(0.0)
	switch._process(0.0)
	var paused_inv: bool = not inv.visible
	var paused_switch: bool = not switch.visible
	print("ISSUE353 paused inv_hidden=", paused_inv,
			" switch_hidden=", paused_switch)
	ok = ok and paused_inv and paused_switch

	# --- 3. C key while paused must NOT flip the camera. ---
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_STATIC
	switch._unhandled_input(_key_event(KEY_C))
	var cam_idle: bool = ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_STATIC
	print("ISSUE353 cam_key_idle=", cam_idle)
	ok = ok and cam_idle

	# --- 4. Weapon hotkey while paused must NOT reselect. ---
	var weapon_before: int = inv.selected_weapon
	inv._unhandled_input(_action_event("weapon_2"))
	var weapon_idle: bool = inv.selected_weapon == weapon_before
	print("ISSUE353 hotkey_idle=", weapon_idle)
	ok = ok and weapon_idle

	# --- 5. Unpaused: both layers come back. ---
	get_tree().paused = false
	inv._process(0.0)
	switch._process(0.0)
	var restored_inv: bool = inv.visible
	var restored_switch: bool = switch.visible
	print("ISSUE353 restored inv=", restored_inv,
			" switch=", restored_switch)
	ok = ok and restored_inv and restored_switch

	print("ISSUE353 ok=", ok)
	get_tree().quit(0 if ok else 1)


## A pressed, non-echo key event with the given PHYSICAL keycode —
## exactly what _unhandled_input receives for a real key press.
func _key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	event.pressed = true
	event.echo = false
	return event


## A pressed action event — what is_action_pressed matches for hotkeys.
func _action_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
