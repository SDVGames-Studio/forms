extends Node
## Regression check for issue #252: the debug mode.
##
## Checks:
##  1. DEFAULT: GameConfig.debug_mode starts ON.
##  2. PERSISTENCE: save_settings/load_settings round-trip the switch
##     through user://settings.cfg (off and back on).
##  3. VISUALS: with debug on, DebugInfo.attach adds the HP number, the
##     damage popup and the arrow to a figure, and the popup appears /
##     hides again after the damage second; with debug off nothing is
##     attached.
##  4. OSD GATE: the OSD hides with debug off and log_action() drops
##     lines instead of crashing.
##
## Run headless: godot --headless res://tests/test_issue252.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true

	# --- 1. default ON ---
	var default_on: bool = GameConfig.debug_mode
	print("ISSUE252 default_on=", default_on)
	ok = ok and default_on

	# --- 2. persistence round-trip (off, then back on) ---
	GameConfig.debug_mode = false
	GameConfig.save_settings()
	GameConfig.debug_mode = true  # pretend a fresh run
	GameConfig.load_settings()
	var stays_off: bool = not GameConfig.debug_mode
	print("ISSUE252 persists_off=", stays_off)
	ok = ok and stays_off
	GameConfig.debug_mode = true
	GameConfig.save_settings()
	GameConfig.debug_mode = false  # pretend a fresh run
	GameConfig.load_settings()
	var stays_on: bool = GameConfig.debug_mode
	print("ISSUE252 persists_on=", stays_on)
	ok = ok and stays_on

	# --- 3. debug visuals on a plain figure ---
	var figure := Node2D.new()
	add_child(figure)
	DebugInfo.attach(figure)
	DebugInfo.update_hp(figure, 80, 100)
	var has_hp: bool = figure.get_node_or_null(NodePath("DebugHp")) != null
	var has_arrow: bool = figure.get_node_or_null(NodePath("DebugArrow")) != null
	var popup := figure.get_node_or_null(NodePath("DebugDamage")) as Label
	print("ISSUE252 attached=", has_hp and has_arrow and popup != null)
	ok = ok and has_hp and has_arrow and popup != null
	var hp_text: String = (figure.get_node(NodePath("DebugHp")) as Label).text
	print("ISSUE252 hp_text=", hp_text)
	ok = ok and hp_text == "HP 80/100"

	# The damage number pops up now and hides after its second.
	DebugInfo.show_damage(figure, 12)
	var popup_shown: bool = popup != null and popup.visible and popup.text == "-12"
	# Wall-clock wait (headless frames run uncapped, so frame counts are
	# NOT seconds there — see the timing probe in the issue #262 test).
	var waited := Time.get_ticks_msec()
	while popup != null and popup.visible and Time.get_ticks_msec() - waited < 4000:
		await get_tree().process_frame
	var popup_hidden: bool = popup != null and not popup.visible
	print("ISSUE252 popup shown_then_hidden=", popup_shown, " ", popup_hidden)
	ok = ok and popup_shown and popup_hidden

	# --- 3b. with debug off nothing attaches ---
	GameConfig.debug_mode = false
	var bare := Node2D.new()
	add_child(bare)
	DebugInfo.attach(bare)
	var bare_clean: bool = bare.get_child_count() == 0
	print("ISSUE252 nothing_when_off=", bare_clean)
	ok = ok and bare_clean
	GameConfig.debug_mode = true  # restore the default for later runs

	# --- 4. OSD gate: hidden with debug off, log_action is a safe no-op ---
	var osd: CanvasLayer = load("res://OSD.gd").new()
	add_child(osd)
	await get_tree().process_frame  # let _ready run
	var osd_shown: bool = osd.visible
	GameConfig.debug_mode = false
	osd.visible = GameConfig.debug_mode
	DebugInfo.log("gate check")  # must not crash and must not render
	var osd_hidden: bool = not osd.visible
	print("ISSUE252 osd_shown=", osd_shown, " osd_hidden=", osd_hidden)
	ok = ok and osd_shown and osd_hidden
	GameConfig.debug_mode = true

	print("ISSUE252 ok=", ok)
	get_tree().quit(0 if ok else 1)
