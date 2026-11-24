extends Node
## Regression check for issue #394: in the team customization menu the
## character figure must sit in the CENTER of its square button — both
## in the members row (56x56 figure on an 84x84 plate, the #394 rework
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
## Rework (owner 2026-11-24): the row grows to FIVE members with
## compact plates, < > arrows scroll it when it overflows, and the
## "+" plate mirrors a member plate's size exactly.
##
##  1. MEMBER CARDS: every figure button in %MembersRow centers its
##     ModularCharacterVisual on the button's own center, keeps the
##     56x56 size, and stays fully inside the button rect;
##  2. SHAPE PICKER: every shape button in %ShapePicker does the same
##     with its 56x56 visual;
##  3. REWORK: a five-member team fields five plates that all FIT the
##     scroller at the desktop width (no overflow, both arrows idle);
##     the "+" card matches the member card size; a sixth member is
##     refused; and when the row does overflow, the arrows scroll it.
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
	# desktop width (1152x648, the default game window) for the "five
	# plates fit the row" checks to mean anything, so it runs inside a
	# SubViewport of exactly that size.
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

	# --- 3) rework: five plates fit, + plate matches, arrows scroll ------
	var scroll: ScrollContainer = menu.get_node("%MembersScroll")
	var arrow_left: Button = menu.get_node("%ScrollLeft")
	var arrow_right: Button = menu.get_node("%ScrollRight")

	# A five-member team: five plates, no sixth, and no overflow at the
	# desktop width — the owner's "fit 5 characters in the row".
	menu._team()["names"] = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
	menu._rebuild_members()
	await get_tree().process_frame
	await get_tree().process_frame
	var member_cards: Array = []
	var plus_cards: Array = []
	for card in members_row.get_children():
		if card.get_child_count() == 2 and card.get_child(1) is LineEdit:
			member_cards.append(card)
		elif card.get_child_count() == 2 and card.get_child(0) is Button \
				and card.get_child(0).text == "+":
			plus_cards.append(card)
	_check(member_cards.size() == 5,
			"a five-member team fields 5 plates (got %d)" % member_cards.size())
	_check(plus_cards.is_empty(),
			"no + plate at the five-member cap (got %d)" % plus_cards.size())
	print("DIAG column=%s scroll=%s content=%s hbar max=%s page=%s scrollpos=%s" % [
		menu.get_node("Layout/Columns/Column").size.x,
		scroll.size,
		members_row.size.x,
		scroll.get_h_scroll_bar().max_value,
		scroll.get_h_scroll_bar().page,
		scroll.scroll_horizontal])
	_check(scroll.get_h_scroll_bar().max_value - scroll.get_h_scroll_bar().page <= 0.5,
			"five member plates fit the row without scrolling (content %s vs viewport %s)"
			% [members_row.size.x, scroll.size])
	_check(arrow_left.disabled and arrow_right.disabled,
			"both arrows idle while the whole row is visible (left=%s right=%s max=%s scroll=%s)"
			% [arrow_left.disabled, arrow_right.disabled,
				scroll.get_h_scroll_bar().max_value, scroll.scroll_horizontal])

	# Four members: the + plate appears and is EXACTLY a member plate's
	# size (the owner's "+ plate size the same as the character's").
	menu._team()["names"] = ["Alpha", "Beta", "Gamma", "Delta"]
	menu._rebuild_members()
	await get_tree().process_frame
	await get_tree().process_frame
	member_cards.clear()
	plus_cards.clear()
	for card in members_row.get_children():
		if card.get_child_count() == 2 and card.get_child(1) is LineEdit:
			member_cards.append(card)
		elif card.get_child_count() == 2 and card.get_child(0) is Button \
				and card.get_child(0).text == "+":
			plus_cards.append(card)
	_check(plus_cards.size() == 1,
			"the + plate shows below the cap (got %d)" % plus_cards.size())
	if not member_cards.is_empty() and not plus_cards.is_empty():
		var member_size: Vector2 = member_cards[0].size
		_check(plus_cards[0].size.distance_to(member_size) <= EPSILON,
			"+ plate size %s != member plate size %s"
			% [plus_cards[0].size, member_size])

	# The + click grows the team to five; a sixth member is refused.
	menu._on_add_member()
	await get_tree().process_frame
	_check((menu._team()["names"] as Array).size() == 5,
			"+ grows the team to five")
	menu._on_add_member()
	await get_tree().process_frame
	_check((menu._team()["names"] as Array).size() == 5,
			"the team menu cap stays at five")

	# Overflow: squeeze the scroller (compact-viewport stand-in) — the
	# right arrow engages, one press scrolls by a plate, the left then
	# engages, and back-to-zero disables the left again.
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.custom_minimum_size = Vector2(240, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not arrow_right.disabled, "right arrow engages when the row overflows")
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

	var ok := failures == 0
	print("issue394: member_buttons=%d shape_buttons=%d failures=%d ok=%s"
		% [member_buttons, shape_buttons, failures, ok])
	get_tree().quit(0 if ok else 1)
