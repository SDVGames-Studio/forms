extends Node
## Regression check for issue #393: "Debug mode" / "Gravity field" switch
## text jumps LEFT when the cursor hovers them while the switch is ON.
##
## Root cause (Godot 4.7.2 text-resource parser quirk): MenuTheme.tres used
## to carry a 7-line `##` comment block INSIDE the btn_hover_pressed
## [sub_resource] section. The VariantParser silently DROPPED the property
## line that immediately followed the comment block — content_margin_left
## = 22.0 — so the stylebox loaded with content_margin_left = -1 (unset).
## A CHECKED CheckButton hovered by the cursor draws in the
## DRAW_HOVER_PRESSED state, i.e. with that broken hover_pressed stylebox:
## its left inset collapsed from 22 px to the ~0 px border-derived default
## and the label visibly slid left. Unchecked hovers (DRAW_HOVER) were
## unaffected — exactly the reported "moves only with the switch on".
## (History: that comment block was added by the #384 rework; the same
## parser quirk is also why plain comments must not sit inside .tres
## sub_resource/resource sections in this project — keep explanations in
## tests/commit messages instead.)
##
## - Every Button state stylebox in MenuTheme.tres must keep its intended
##   22/12 px content margins after a load (the parser may silently skip
##   properties, so assert on a freshly loaded Theme, not the editor's).
## - The live DebugMenu path is checked too: %DebugCheck must resolve the
##   hover_pressed stylebox with the same margins, so a hovered checked
##   switch lays out its text exactly like every other state.
##
## Run headless: godot --headless res://tests/test_issue393.tscn
## Exit code 0 = pass.

const DebugMenuScene := preload("res://scenes/menus/DebugMenu.tscn")

const STATE_ITEMS := ["normal", "hover", "pressed", "hover_pressed", "disabled"]


func _ready() -> void:
	var ok := true

	# --- 1. Fresh load of the theme file -------------------------------
	var theme: Theme = load("res://scenes/menus/MenuTheme.tres")
	for item in STATE_ITEMS:
		var sb: StyleBoxFlat = theme.get_stylebox(item, "Button")
		if sb == null or not (sb is StyleBoxFlat):
			push_error("state '%s': expected a StyleBoxFlat" % item)
			ok = false
			continue
		if sb.content_margin_left != 22.0 or sb.content_margin_right != 22.0 \
				or sb.content_margin_top != 12.0 or sb.content_margin_bottom != 12.0:
			push_error("state '%s': margins L/R/T/B = %.1f/%.1f/%.1f/%.1f, expected 22/22/12/12 (a dropped property after a .tres comment line reproduces issue #393)" % [
				item, sb.content_margin_left, sb.content_margin_right,
				sb.content_margin_top, sb.content_margin_bottom])
			ok = false
	print("theme state margins: ", "OK" if ok else "BROKEN")

	# --- 2. Live scene path (DebugMenu -> %DebugCheck) ------------------
	var menu := DebugMenuScene.instantiate()
	add_child(menu)
	var check: CheckButton = menu.get_node("%DebugCheck")
	var hp: StyleBoxFlat = check.get_theme_stylebox("hover_pressed")
	var normal: StyleBoxFlat = check.get_theme_stylebox("normal")
	if hp == null or not (hp is StyleBoxFlat) or normal == null:
		push_error("DebugCheck: hover_pressed/normal stylebox missing")
		ok = false
	elif absf(hp.content_margin_left - normal.content_margin_left) > 0.01:
		push_error("DebugCheck: hover_pressed left margin %.1f != normal %.1f — the checked-hover text shift of issue #393" % [
			hp.content_margin_left, normal.content_margin_left])
		ok = false
	print("live DebugCheck hover_pressed layout: ", "OK" if ok else "BROKEN")
	menu.queue_free()

	if ok:
		print("test_issue393: PASS")
		get_tree().quit(0)
	else:
		print("test_issue393: FAIL")
		get_tree().quit(1)
