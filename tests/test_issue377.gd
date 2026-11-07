extends Node
## Regression check for issue #377: the controls hint was reworked.
##  - The player-turn controls list no longer lives in the one-line top
##    hint; the top hint is empty during the player's turn.
##  - A compact window sits at the center of the left side of the screen:
##    a PanelContainer with a 90% transparent white background, one list
##    item per line, and a ✕ button in its top left corner.
##  - ✕ hides the window; only the backgroundless flat word "controls"
##    remains (same spot) and clicking it brings the window back.
##  - The window itself ignores the mouse so gameplay clicks pass through;
##    neither button can steal keyboard focus from the game.
##
## Run headless: godot --headless res://tests/test_issue377.tscn
## Exit code 0 = pass.

const ControllerScript := preload("res://TurnController.gd")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE377 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var tc: Node = ControllerScript.new()
	add_child(tc)
	tc.call("_build_ui")
	var panel: PanelContainer = tc.get("_controls_panel")
	var word: Button = tc.get("_controls_word")
	var layer: CanvasLayer = tc.get("_layer")

	# 1) Structure: window + word on the UI layer, ✕ first in the window.
	_check("controls window exists on the UI layer",
		panel != null and panel.get_parent() == layer)
	_check("\"controls\" word exists on the UI layer",
		word != null and word.get_parent() == layer)
	var rows: VBoxContainer = panel.get_node_or_null("Rows")
	_check("window body is a VBox", rows is VBoxContainer)
	var close := panel.get_node_or_null("Rows/CloseButton") as Button
	_check("✕ close button sits first, in the window's top left corner",
		close is Button and rows.get_child(0) == close)
	_check("✕ button is flat (no background bar)", close.flat)
	_check("✕ button cannot steal keyboard focus",
		close.focus_mode == Control.FOCUS_NONE)
	_check("\"controls\" word is flat — no background", word.flat)
	_check("\"controls\" word cannot steal keyboard focus",
		word.focus_mode == Control.FOCUS_NONE)

	# 2) One list item per line — every CONTROL_LINES entry is its own
	#    Label row under the ✕, compact 12 px font, nothing else.
	var labels: Array = []
	for child in rows.get_children():
		if child is Label:
			labels.append(child)
	var lines: Array = ControllerScript.CONTROL_LINES
	_check("one Label per list item (move, jump, aim, ... on new lines)",
		labels.size() == lines.size())
	var per_line_ok := labels.size() == lines.size()
	for i in labels.size():
		if labels[i].text != lines[i]:
			per_line_ok = false
	_check("line texts match the controls list, no \\n inside a line",
		per_line_ok and labels.size() > 0)
	_check("compact font (12 px)", labels.size() > 0
		and labels[0].get_theme_font_size("font_size") == 12)

	# 3) Window look: 90% transparent white, left-center placement.
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	_check("90% transparent white background",
		style is StyleBoxFlat
		and is_equal_approx(style.bg_color.r, 1.0)
		and is_equal_approx(style.bg_color.g, 1.0)
		and is_equal_approx(style.bg_color.b, 1.0)
		and is_equal_approx(style.bg_color.a, 0.1))
	_check("anchored to the center of the left side",
		is_equal_approx(panel.anchor_left, 0.0)
		and is_equal_approx(panel.anchor_right, 0.0)
		and is_equal_approx(panel.anchor_top, 0.5)
		and is_equal_approx(panel.anchor_bottom, 0.5))
	_check("window ignores the mouse (gameplay clicks pass through)",
		panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# Wait a layout pass, then check the on-screen placement.
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	var panel_rect := panel.get_global_rect()
	_check("window hugs the left edge (small left margin)",
		panel_rect.position.x >= 0.0 and panel_rect.position.x < 40.0)
	_check("window is vertically centered",
		absf(panel_rect.get_center().y - vp.get_center().y) < 20.0)

	# 4) Visibility: the window shows only while the player may act.
	tc.set("game_over", true)
	tc.call("_update_controls_visibility")
	_check("hidden after game over", not panel.visible and not word.visible)
	tc.set("game_over", false)
	tc.set("active_team", ControllerScript.TEAM_ENEMY)
	tc.call("_update_controls_visibility")
	_check("hidden during the enemy turn", not panel.visible and not word.visible)
	tc.set("active_team", ControllerScript.TEAM_PLAYER)
	tc.call("_update_controls_visibility")
	_check("shown during the player's turn", panel.visible and not word.visible)

	# 5) ✕ hides the window, the bare "controls" word appears in its
	#    place, and clicking the word brings the window back.
	tc.call("_on_controls_close_pressed")
	_check("✕ hides the window, only the word remains",
		not panel.visible and word.visible)
	tc.call("_on_controls_word_pressed")
	_check("clicking \"controls\" shows the window again",
		panel.visible and not word.visible)

	# 6) The top one-line hint no longer carries the controls list.
	tc.set("_switching", false)
	tc.call("_update_hint")
	var hint: Label = tc.get("_hint_label")
	_check("top hint is empty during the player's turn",
		hint != null and hint.text == "")

	if _fails.is_empty():
		print("ISSUE377 ALL OK")
		get_tree().quit(0)
	else:
		print("ISSUE377 FAILED: %d" % _fails.size())
		get_tree().quit(1)
