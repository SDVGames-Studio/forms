extends Node
## Regression check for issue #394: in the team customization menu the
## character figure must sit in the CENTER of its square button — both
## in the members row (72x72 figure on a 100x100 button) and in the
## shape picker (56x56 figure on an 88x88 button).
##
## Root cause: the visuals were placed with
## set_anchors_preset(PRESET_CENTER) AFTER setting .size, which moves
## the anchors to 0.5 but keeps the stale offsets — the figure's
## top-left landed on the button's center and the figure spilled out
## of the square toward the bottom right (center off by (36, 36)).
## The fix uses set_anchors_and_offsets_preset(PRESET_CENTER,
## PRESET_MODE_KEEP_SIZE), which recenters while keeping the size.
##
##  1. MEMBER CARDS: every figure button in %MembersRow centers its
##     ModularCharacterVisual on the button's own center, keeps the
##     72x72 size, and stays fully inside the button rect;
##  2. SHAPE PICKER: every shape button in %ShapePicker does the same
##     with its 56x56 visual.
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
	var menu: Control = MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- 1) member cards ------------------------------------------------
	var members_row: HBoxContainer = menu.get_node("%MembersRow")
	var member_buttons := 0
	for card in members_row.get_children():
		for child in card.get_children():
			if child is Button and _figure_in(child) != null:
				member_buttons += 1
				_check_centered(child, Vector2(72, 72),
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

	var ok := failures == 0
	print("issue394: member_buttons=%d shape_buttons=%d failures=%d ok=%s"
		% [member_buttons, shape_buttons, failures, ok])
	get_tree().quit(0 if ok else 1)
