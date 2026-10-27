extends Node
## Regression check for issue #131: weapon selection is locked after the
## first shot of a turn and unlocked again at the start of the next turn.
##
## Run headless: godot --headless res://tests/test_issue131.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var inv := WeaponInventory
	var failures := 0

	# Fresh state.
	inv.locked = false
	inv.selected_weapon = 0

	# Unlocked: selection works.
	inv.set_selected(2)
	if inv.selected_weapon != 2:
		printerr("FAIL: selection change ignored while unlocked")
		failures += 1

	# After the first shot (TurnController.notify_shot locks the inventory).
	inv.locked = true
	inv.set_selected(0)
	if inv.selected_weapon != 2:
		printerr("FAIL: selection changed while locked")
		failures += 1
	if inv._slots[0].button_pressed or not inv._slots[2].button_pressed:
		printerr("FAIL: highlight desynced after locked selection attempt")
		failures += 1

	# New turn: TurnController._begin_turn path unlocks via locked=false.
	inv.locked = false
	inv.set_selected(0)
	if inv.selected_weapon != 0:
		printerr("FAIL: selection still frozen after unlock")
		failures += 1

	if failures == 0:
		print("ISSUE131 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE131 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
