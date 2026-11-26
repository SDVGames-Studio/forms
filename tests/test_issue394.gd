extends Node
## Regression check for issue #394: in the team customization menu the
## character figure must sit in the CENTER of its square button — both
## in the members row (56x56 figure on an 80x80 plate, the #394 rework
## sizing) and in the shape picker (56x56 figure on an 88x88 button).
##
## Root cause (round 1): the visuals were placed with
## set_anchors_preset(PRESET_CENTER) AFTER setting .size, which moves
## the anchors to 0.5 but keeps the stale offsets — the figure's
## top-left landed on the button's center and the figure spilled out
## of the square toward the bottom right (center off by (36, 36)).
## The fix uses set_anchors_and_offsets_preset(PRESET_CENTER,
## PRESET_MODE_KEEP_SIZE), which recenters while keeping the size.
##
## Rework v3 (owner 2026-11-26): the < > arrows sit LEFT and RIGHT of
## the character strip (a tscn child-order bug had parked BOTH arrows
## left of the characters), share the character square's height and
## top edge, and scroll the row once the team outgrows it; the "+"
## plate is PINNED right of the scroller so it is ALWAYS present,
## exactly a member plate's size, and only gives up at the game's hard
## member bound (GameConfig.MAX_LEVEL_TEAM_MEMBERS).
##
##  1. MEMBER CARDS: every figure button in %MembersRow centers its
##     ModularCharacterVisual on the button's own center, keeps the
##     56x56 size, and stays fully inside the button rect;
##  2. SHAPE PICKER: every shape button in %ShapePicker does the same
##     with its 56x56 visual;
##  3. REWORK V3: the strip reads [<][characters][+][>]; the arrows
##     share the square's height and top edge; the pinned + stays live
##     past five members and matches the member plate size; it only
##     gives up at the 64-member bound; a long team engages the arrows
##     at the desktop width and a press scrolls by a plate; a squeezed
##     viewport does the same with the + pinned on screen.
##
## Run headless: godot --headless res://tests/test_issue394.tscn
## The printed ok=true/false verdict is authoritative.

const MENU_SCENE := preload("res://scenes/menus/TeamMenu.tscn")
const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")

const EPSILON := 0.5

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)

func _figure_in(button: Control) -> Control:
	for child in button.get_children():
		if child is Control and child.get_script() == VisualScript:
			return child
	return null


func _check_centered(button: Control, expected_size: Vector2, label: String) -> void:
	var figure := _figure_in(button)
	if figure == null:
		failures += 1
		push_error("FAIL: %s has no ModularCharacterVisual child" % label)
		return
	var delta: Vector2 = (figure.position + figure.size * 0.5) - button.size * 0.5
	_check(delta.length() <= EPSILON,
		"%s figure center off by %s (button %s, figure rect %s..%s)"
		% [label, delta, button.size, figure.position, figure.position + figure.size])
	_check(figure.size.distance_to(expected_size) <= EPSILON,
		"%s figure size %s != expected %s" % [label, figure.size, expected_size])
	_check(figure.position.x >= -EPSILON and figure.position.y >= -EPSILON
			and figure.position.x + figure.size.x <= button.size.x + EPSILON
			and figure.position.y + figure.size.y <= button.size.y + EPSILON,
		"%s figure rect %s..%s spills outside the %s button"
		% [label, figure.position, figure.position + figure.size, button.size])


func _ready() -> void:
	# The headless window is tiny (64x64) — the menu must lay out at the
	# desktop width (1152x648, the default game window) for the row
	# geometry checks to mean anything, so it runs inside a SubViewport
	# of exactly that size.
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1152, 648)
	add_child(canvas)
	var menu: Control = MENU_SCENE.instantiate()
	canvas.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- 1) member cards ------------------------------------------------
	var members_row: HBoxContainer = menu.get_node("%MembersRow")
	var member_buttons := 0
	for card in members_row.get_children():
		for child in card.get_children():
			if child is Button and _figure_in(child) != null:
				member_buttons += 1
				_check_centered(child, Vector2(56, 56),
					"member figure %d" % member_buttons)
	_check(member_buttons > 0, "no member figure buttons found in %MembersRow")

	# --- 2) shape picker --------------------------------------------------
	var picker: HBoxContainer = menu.get_node("%ShapePicker")
	var shape_buttons := 0
	for button in picker.get_children():
		if button is Button and _figure_in(button) != null:
			shape_buttons += 1
			_check_centered(button, Vector2(56, 56), "shape button %d" % shape_buttons)
	_check(shape_buttons > 0, "no shape buttons found in %ShapePicker")

	# --- 3) rework v3: [<] characters [+] [>] — arrows flank, + pinned ---
	var scroll: ScrollContainer = menu.get_node("%MembersScroll")
	var arrow_left: Button = menu.get_node("%ScrollLeft")
	var arrow_right: Button = menu.get_node("%ScrollRight")
	var plus_button: Button = menu.get_node("%PlusButton")
	var plus_card: VBoxContainer = menu.get_node("%PlusCard")
	var strip: HBoxContainer = menu.get_node("%MembersScrollRow")

	# The strip order IS the fix: the owner saw BOTH arrows parked left
	# of the characters (tscn child order), so [<][chars][+][>] is the
	# layout under test, and the + is pinned OUTSIDE the scroller.
	var order: Array[String] = []
	for child in strip.get_children():
		order.append(str(child.name))
	_check(order == ["ScrollLeft", "MembersScroll", "PlusCard", "ScrollRight"],
			"strip order must be [<][characters][+][>] (got %s)" % str(order))
	_check(plus_card.get_parent() == strip,
			"the + plate is pinned outside the scroller (parent %s)" % plus_card.get_parent().name)

	# A five-member team (the owner's case): five member plates, the
	# pinned + live right of the strip — exactly a member plate's size —
	# and the arrows sharing the character square's height and top edge.
	menu._team()["names"] = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
	menu._rebuild_members()
	await get_tree().process_frame
	await get_tree().process_frame
	var member_cards: Array = []
	for card in members_row.get_children():
		if card.get_child_count() == 2 and card.get_child(1) is LineEdit:
			member_cards.append(card)
	_check(member_cards.size() == 5,
			"a five-member team fields 5 plates (got %d)" % member_cards.size())
	_check(not plus_button.disabled,
			"the pinned + stays live at five members (the old menu cap)")
	if not member_cards.is_empty():
		var square: Button = member_cards[0].get_child(0)
		_check(plus_card.size.distance_to(member_cards[0].size) <= EPSILON,
				"+ plate size %s != member plate size %s"
				% [plus_card.size, member_cards[0].size])
		_check(absf(arrow_left.size.y - square.size.y) <= EPSILON,
				"left arrow height %s != character square height %s"
				% [arrow_left.size.y, square.size.y])
		_check(absf(arrow_right.size.y - square.size.y) <= EPSILON,
				"right arrow height %s != character square height %s"
				% [arrow_right.size.y, square.size.y])
		_check(absf(arrow_left.global_position.y - square.global_position.y) <= 1.0,
				"left arrow top %s != character square top %s"
				% [arrow_left.global_position.y, square.global_position.y])
		_check(absf(arrow_right.global_position.y - square.global_position.y) <= 1.0,
				"right arrow top %s != character square top %s"
				% [arrow_right.global_position.y, square.global_position.y])
		# < left of the characters, > right of the + plate.
		_check(arrow_left.position.x + arrow_left.size.x <= scroll.position.x + EPSILON,
				"the left arrow must end before the characters start")
		_check(plus_card.position.x >= scroll.position.x + scroll.size.x - EPSILON,
				"the + plate sits right of the character strip")
		_check(arrow_right.position.x >= plus_card.position.x + plus_card.size.x - EPSILON,
				"the right arrow sits right of the + plate")

	# The + keeps adding past five — the bound is the GAME's, not a menu
	# cap (owner: "+ always lets you add a new teammate").
	menu._on_add_member()
	await get_tree().process_frame
	_check((menu._team()["names"] as Array).size() == 6,
			"+ grows a five-member team to six")
	# The hard bound: at 64 members the + stays visible but gives up.
	var full: Array = []
	for i in range(GameConfig.MAX_LEVEL_TEAM_MEMBERS):
		full.append("Mate %d" % (i + 1))
	menu._team()["names"] = full
	menu._rebuild_members()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(plus_button.disabled, "the + gives up at the 64-member game bound")
	menu._on_add_member()
	await get_tree().process_frame
	_check((menu._team()["names"] as Array).size() == GameConfig.MAX_LEVEL_TEAM_MEMBERS,
			"no member lands past MAX_LEVEL_TEAM_MEMBERS")

	# A long team at the DESKTOP width: the arrows engage (the owner's
	# "arrows don't work" — five plates never overflowed the old row)
	# and one press scrolls the row by a plate.
	var many: Array = []
	for i in range(20):
		many.append("Runner %d" % (i + 1))
	menu._team()["names"] = many
	menu._rebuild_members()
	await get_tree().process_frame
	await get_tree().process_frame
	print("DIAG column=%s scroll=%s content=%s hbar max=%s page=%s scrollpos=%s" % [
		menu.get_node("Layout/Columns/Column").size.x,
		scroll.size,
		members_row.size.x,
		scroll.get_h_scroll_bar().max_value,
		scroll.get_h_scroll_bar().page,
		scroll.scroll_horizontal])
	_check(not arrow_right.disabled, "right arrow engages when the team overflows the row")
	_check(arrow_left.disabled, "left arrow idle at the row's left edge")
	menu._scroll_members(1)
	await get_tree().process_frame
	_check(scroll.scroll_horizontal > 0,
			"one arrow press scrolls the row (%d)" % scroll.scroll_horizontal)
	_check(not arrow_left.disabled, "left arrow engages after scrolling right")
	menu._scroll_members(-1)
	await get_tree().process_frame
	_check(scroll.scroll_horizontal == 0, "scrolling back lands on the row start")
	_check(arrow_left.disabled, "left arrow idle again at the row start")

	# Squeeze the scroller (compact-viewport stand-in): the arrows keep
	# working and the pinned + stays on screen and live.
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.custom_minimum_size = Vector2(240, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not arrow_right.disabled, "right arrow engages when the row is squeezed")
	_check(not plus_button.disabled, "the pinned + stays live while the row overflows")
	_check(plus_card.visible, "the pinned + plate stays on screen")
	menu._scroll_members(1)
	await get_tree().process_frame
	_check(scroll.scroll_horizontal > 0,
			"one arrow press scrolls the squeezed row (%d)" % scroll.scroll_horizontal)
	menu._scroll_members(-1)
	await get_tree().process_frame
	_check(scroll.scroll_horizontal == 0, "scrolling back lands on the squeezed row start")
	_check(arrow_left.disabled, "left arrow idle again at the squeezed row start")

	var ok := failures == 0
	print("issue394: member_buttons=%d shape_buttons=%d failures=%d ok=%s"
		% [member_buttons, shape_buttons, failures, ok])
	get_tree().quit(0 if ok else 1)
