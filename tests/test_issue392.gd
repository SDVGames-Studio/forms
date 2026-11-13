extends Node
## Regression check for issue #392: menu title overlap hints.
##
## The in-game menu (InGameMenu, CanvasLayer 10) is drawn BELOW the turn
## HUD (TurnController, CanvasLayer 50), so with the menu open the
## gameplay hints showed through ON TOP of its title: the controls
## window on the left covered the "PAUSED" brand, and the one-line top
## hint floated over the dim. The fix: InGameMenu emits menu_open_changed
## on open/close and the TurnController masks its hint elements while
## the menu is up, restoring them afterwards without touching the
## player's hidden/shown choice for the controls window.
##
## Checks:
##  - Hints are visible while no menu is open.
##  - Opening the menu (the real autoload InGameMenu) hides BOTH hint
##    elements: the controls root (window + "controls" word) and the
##    one-line top hint. The turn banner itself stays untouched — only
##    hints step aside.
##  - Closing the menu restores both.
##  - The player's own closed-window choice survives the pause: after
##    close the "controls" word is back exactly as it was, and reopening
##    the menu still hides it.
##
## Run headless: godot --headless res://tests/test_issue392.tscn
## Exit code 0 = pass.

const ControllerScript := preload("res://TurnController.gd")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE392 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var tc: Node = ControllerScript.new()
	add_child(tc)
	tc.call("_build_ui")
	var root: Control = tc.get("_controls_root")
	var panel: PanelContainer = tc.get("_controls_panel")
	var word: Button = tc.get("_controls_word")
	var hint: Label = tc.get("_hint_label")
	var banner: Label = tc.get("_label")
	# The real autoload menu — the same node gameplay uses.
	var menu: CanvasLayer = get_node("/root/InGameMenu")

	# 1) Baseline: everything visible while the menu is closed.
	_check("controls hint visible while no menu is open", root.visible)
	_check("top one-line hint visible while no menu is open", hint.visible)

	# 2) Opening the menu hides BOTH hint elements — and only them.
	menu.call("_open")
	_check("controls hint (window + word) hidden while the menu is open",
		not root.visible)
	_check("top one-line hint hidden while the menu is open",
		not hint.visible)
	_check("turn banner is NOT a hint — it keeps its own visibility",
		banner.visible)

	# 3) Closing the menu brings the hints back.
	menu.call("_close")
	_check("controls hint restored after the menu closes", root.visible)
	_check("top one-line hint restored after the menu closes", hint.visible)

	# 4) The player's hidden/shown choice survives the pause round-trip:
	#    a closed window (only the "controls" word showing) stays closed
	#    after the menu visit, and the word hides with the menu too.
	tc.set("_controls_hidden", true)
	tc.call("_update_controls_visibility")
	_check("player choice before menu: window closed, word shows",
		not panel.visible and word.visible)
	menu.call("_open")
	_check("menu open hides the word as well (whole controls root)",
		not root.visible and not word.is_visible_in_tree()
		and not panel.is_visible_in_tree())
	menu.call("_close")
	_check("player choice kept after menu: word still shows, window closed",
		word.visible and not panel.visible)

	# The tree must never stay paused after the test.
	if get_tree().paused:
		menu.call("_close")
		_check("test leaves the tree unpaused", false)
	else:
		_check("test leaves the tree unpaused", true)

	if _fails.is_empty():
		print("ISSUE392 ok=true all checks passed")
		get_tree().quit(0)
	else:
		print("ISSUE392 ok=false %d check(s) failed" % _fails.size())
		get_tree().quit(1)
