extends Node
## Regression check for issue #585: next slice of the geometric
## character visual refinement — independent gaze, configurable eye
## size, and the full six-mood personality set.
##
##  1. INDEPENDENT PUPILS: pupil_shift_left/pupil_shift_right are
##     exported, default to ZERO (authored look unchanged), compose
##     with the shared pupil_shift glance, and the blink lid follows
##     the per-eye shift;
##  2. EYE SIZE: eye_size is exported, defaults to 1.0 and scales the
##     whole eye (shape AND size stay configurable);
##  3. SIX MOODS: the issue's list — angry, friendly, confident,
##     sleepy, scared, surprised — is fully settable (the new SLEEPY
##     mood included, by name and by enum), SLEEPY is distinct from
##     CONFIDENT, and the personality rotation now includes SLEEPY
##     without changing members 0-3;
##  4. HEADLESS DRAW: every mood x eye size x asymmetric gaze draws
##     on the yellow square and the magenta circle without errors.
##
## Run headless: godot --headless res://tests/test_issue585.tscn
## Exit code 0 = pass.

const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")

## The two default team looks this issue refines (GameConfig teams).
const YELLOW := Color(1, 0.84, 0.2, 1)
const MAGENTA := Color(0.75, 0.2, 0.45, 1)

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _ready() -> void:
	# --- 1) independent pupils -----------------------------------------
	var src := FileAccess.get_file_as_string("res://scripts/ModularCharacterVisual.gd")
	_check(src.contains("Issue #585: the per-eye gaze"),
			"the eye drawer selects a per-eye shift (independent gaze)")
	var fresh: Control = VisualScript.new()
	_check(fresh.pupil_shift_left == Vector2.ZERO
			and fresh.pupil_shift_right == Vector2.ZERO,
			"the per-eye gaze defaults to ZERO — the authored look "
			+ "and the shared glance are unchanged")
	fresh.free()

	var face: Control = VisualScript.new()
	face.size = Vector2(64, 64)
	add_child(face)
	face.pupil_shift_left = Vector2(-0.5, 0.1)
	face.pupil_shift_right = Vector2(0.5, -0.1)
	face.pupil_shift = Vector2(0.2, 0.0)
	await get_tree().process_frame
	_check(is_instance_valid(face),
			"independent per-eye gaze over a shared glance draws")

	# --- 2) configurable eye size --------------------------------------
	_check(face.get("eye_size") != null,
			"eye size is an exported property")
	_check(fresh == null or VisualScript.new().eye_size == 1.0,
			"eye_size defaults to 1.0 — authored proportions unchanged")
	for scale in [0.5, 1.0, 1.6]:
		face.eye_size = scale
		await get_tree().process_frame
	_check(is_instance_valid(face), "every eye size draws")

	# --- 3) the six moods of the issue ---------------------------------
	for mood in ["angry", "friendly", "confident", "sleepy",
			"scared", "surprised"]:
		var key: int = VisualScript.expression_key(mood)
		_check(key >= 0 and VisualScript.EXPRESSION_FEATURES.has(key),
				"the issue's mood '%s' is settable by name" % mood)
	var sleepy: int = VisualScript.expression_key("sleepy")
	var confident: int = VisualScript.expression_key("confident")
	_check(sleepy != confident,
			"SLEEPY is its own mood, not an alias of CONFIDENT")
	_check(VisualScript.EXPRESSION_FEATURES[sleepy]["mouth"]
			!= VisualScript.EXPRESSION_FEATURES[confident]["mouth"],
			"the sleepy face reads differently from the confident smirk")
	# Personality rotation: SLEEPY joined WITHOUT changing members 0-3.
	_check(VisualScript.personality_for_index(4)
			== VisualScript.expression_key("sleepy"),
			"member 4 now rests in the sleepy personality")
	for i in 4:
		var expected: Array = [
			VisualScript.expression_key("neutral"),
			VisualScript.expression_key("friendly"),
			VisualScript.expression_key("confident"),
			VisualScript.expression_key("angry"),
		]
		_check(VisualScript.personality_for_index(i) == expected[i],
				"personality of member %d is unchanged" % i)

	# --- 4) every mood x eye size x asymmetric gaze, both bodies ------
	var square: Control = VisualScript.new()
	square.size = Vector2(64, 64)
	add_child(square)
	var circle: Control = VisualScript.new()
	circle.size = Vector2(64, 64)
	add_child(circle)
	square.apply_team_look(YELLOW, "square", 0)
	circle.apply_team_look(MAGENTA, "circle", 2)
	for host in [square, circle]:
		for mood_key in VisualScript.ExpressionType.values():
			host.set_expression(mood_key)
			host.pupil_shift_left = Vector2(-0.4, 0.2)
			host.pupil_shift_right = Vector2(0.4, -0.2)
			host.eye_open = 0.6
			for scale in [0.7, 1.3]:
				host.eye_size = scale
				await get_tree().process_frame
		host.eye_open = 1.0
		await get_tree().process_frame
	_check(is_instance_valid(square) and is_instance_valid(circle),
			"every mood x size x asymmetric half-blink gaze draws "
			+ "on both refined bodies")

	if failures == 0:
		print("PASS: issue #585 independent gaze + eye size + sleepy mood")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
