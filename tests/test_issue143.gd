extends Node
## Regression check for issue #143: the one-weapon-per-turn constraint is
## a CHARACTER's constraint, not the player's. A member that already fired
## keeps its weapon locked, but switching to another controlled member
## restores free weapon selection for that member.
##
## Run headless: godot --headless res://tests/test_issue143.tscn
## Exit code 0 = pass.

func _ready() -> void:
	await get_tree().process_frame
	var inv := WeaponInventory
	var failures := 0

	var shooter := Node2D.new()
	add_child(shooter)
	var other := Node2D.new()
	add_child(other)
	TurnController.active_member = shooter

	# Fresh turn: selection is free.
	inv.unlock_all()
	inv.selected_weapon = 0
	inv.set_selected(1)
	if inv.selected_weapon != 1:
		printerr("FAIL: fresh turn selection ignored")
		failures += 1

	# The first character fires — its weapon becomes locked.
	inv.lock_for(shooter)
	inv.set_selected(2)
	if inv.selected_weapon != 1:
		printerr("FAIL: selection changed for a character that already fired")
		failures += 1

	# The player switches to another member that has NOT fired: free
	# selection again (the core of issue #143).
	TurnController.active_member = other
	inv.set_selected(2)
	if inv.selected_weapon != 2:
		printerr("FAIL: a fresh character could not pick its own weapon")
		failures += 1

	# Back to the shooter: its weapon stays locked within the same turn.
	TurnController.active_member = shooter
	inv.set_selected(0)
	if inv.selected_weapon != 2:
		printerr("FAIL: fired character escaped its weapon lock")
		failures += 1

	# New player turn (TurnController._begin_turn path): everyone unlocked.
	TurnController.active_member = shooter
	inv.unlock_all()
	inv.set_selected(3)
	if inv.selected_weapon != 3:
		printerr("FAIL: unlock_all did not restore free selection")
		failures += 1

	TurnController.active_member = null
	if failures == 0:
		print("ISSUE143 TEST PASS")
		get_tree().quit(0)
	else:
		printerr("ISSUE143 TEST FAIL: %d failure(s)" % failures)
		get_tree().quit(1)
