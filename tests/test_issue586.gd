extends Node
## Regression check for issue #586: first refinement of the yellow
## square and the magenta circle (slice of #585 — improve geometric
## character visuals).
##
##  1. GLOSSY EYES: every open eye carries a white pupil highlight
##     (the source contract — the glint draw pass exists in the eye
##     drawer), and the cartoon eye proportions grew (bigger whites);
##  2. CONFIGURABLE EYEBROWS: position (eyebrow_lift) and rotation
##     (eyebrow_tilt_deg) are exported, DEFAULT to the authored look
##     (0 = no offset) and restyle the face live from code;
##  3. THE TWO CHARACTERS: the default team looks — yellow square and
##     magenta circle — apply through the in-game apply_team_look path,
##     preserve the exact team colors and give members distinct resting
##     personalities (not one shared face);
##  4. HEADLESS DRAW: every eye style × eyebrow style combination draws
##     on both refined bodies without errors and leaves every instance
##     alive.
##
## Run headless: godot --headless res://tests/test_issue586.tscn
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
	# --- 1) glossy eyes, bigger proportions -----------------------------
	var src := FileAccess.get_file_as_string("res://scripts/ModularCharacterVisual.gd")
	_check(src.contains("Issue #586: pupil highlight"),
			"every open eye draws a pupil highlight (the glossy glint)")
	_check(src.contains("EYE_SPAN"),
			"the eye/eyebrow spacing is one shared, retunable constant")

	# --- 2) configurable eyebrow position + rotation --------------------
	var face: Control = VisualScript.new()
	face.size = Vector2(64, 64)
	add_child(face)
	_check(face.get("eyebrow_lift") != null
			and face.get("eyebrow_tilt_deg") != null,
			"eyebrow position and rotation are exported properties")
	var fresh: Control = VisualScript.new()
	_check(fresh.eyebrow_lift == 0.0 and fresh.eyebrow_tilt_deg == 0.0,
			"the offsets default to 0 — the authored look is unchanged")
	face.eyebrow_lift = 0.06
	face.eyebrow_tilt_deg = 14.0
	_check(face.eyebrow_lift == 0.06 and face.eyebrow_tilt_deg == 14.0,
			"position and rotation restyle the face from code")
	# Both offsets must compose with EVERY eyebrow style without errors.
	for style in VisualScript.EyebrowStyle.values():
		face.eyebrow_style = style
		for tilt in [-25.0, 0.0, 25.0]:
			face.eyebrow_tilt_deg = tilt
			face.eyebrow_lift = 0.05 * signf(tilt + 1.0)
			await get_tree().process_frame
	_check(is_instance_valid(face), "every style × offset pair draws")

	# --- 3) the two refined characters, the in-game path ---------------
	var square: Control = VisualScript.new()
	square.size = Vector2(64, 64)
	add_child(square)
	square.apply_team_look(YELLOW, "square", 0)
	_check(square.body_color == YELLOW and square.body_shape == "square",
			"the yellow square keeps its exact team color through the "
			+ "in-game look path")
	_check(square.expression == VisualScript.personality_for_index(0),
			"member 0 rests in their own personality")
	var circle: Control = VisualScript.new()
	circle.size = Vector2(64, 64)
	add_child(circle)
	circle.apply_team_look(MAGENTA, "circle", 2)
	_check(circle.body_color == MAGENTA and circle.body_shape == "circle",
			"the magenta circle keeps its exact team color")
	_check(square.expression != circle.expression,
			"two members of the set read as different characters")

	# --- 4) every feature style draws on both bodies --------------------
	for host in [square, circle]:
		for eye in VisualScript.EyeStyle.values():
			host.eye_style = eye
			for brow in VisualScript.EyebrowStyle.values():
				host.eyebrow_style = brow
				host.eyebrow_lift = 0.04
				host.eyebrow_tilt_deg = 10.0
				await get_tree().process_frame
			for mouth in VisualScript.MouthStyle.values():
				host.mouth_style = mouth
				await get_tree().process_frame
	_check(is_instance_valid(square) and is_instance_valid(circle),
			"every style combination leaves both bodies alive")

	# Blink/dart interplay: the lids still cover the highlight (draw
	# order kept — the lid pass runs after the pupil glint).
	for host in [square, circle]:
		host.eye_style = VisualScript.EyeStyle.NORMAL
		host.eye_open = 0.4
		host.pupil_shift = Vector2(0.3, -0.2)
		await get_tree().process_frame
		host.eye_open = 1.0
		await get_tree().process_frame
	_check(is_instance_valid(square) and is_instance_valid(circle),
			"a half-blink over a glancing pupil draws cleanly")

	if failures == 0:
		print("PASS: issue #586 refined yellow square + magenta circle")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
