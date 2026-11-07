class_name SpeechBubble
extends Control
## Issue #335: a comics-style balloon with a character's line.
##
## The three classic balloon types from the issue's reference image are
## all implemented:
##   SPEECH — rounded bubble with a tail pointing at the speaker,
##   THOUGHT — cloud of bumps with little trailing bubbles,
##   SHOUT — spiky starburst.
## Everything is drawn in code (white fill, black outline — no assets),
## like the rest of the figure visuals. The bubble is added as a HUD
## child of the speaking figure, so HudPose keeps it upright in whatever
## frame the current view shows (issue #311). It appears for SHOW_TIME
## (3 s, per the issue) and then frees itself.

enum Kind { SPEECH, THOUGHT, SHOUT }

## Issue #335: "character line appears for three second".
const SHOW_TIME := 3.0
## Width the text wraps at, and the padding inside the balloon.
const MAX_TEXT_WIDTH := 140.0
const PADDING := Vector2(12.0, 10.0)
## Issue #335 rework (owner 2026-11-06): the fallback font leaves more
## air under the last line than above the first, so the text read high
## in the balloon — drop it a little and grow the box to match.
const TEXT_DROP := 4.0
const FONT_SIZE := 13
## Distance from the figure's origin to the balloon's bottom edge —
## clear above the name label (-62..-46) and health bar.
const RISE := 100.0
const FILL := Color(1.0, 1.0, 1.0, 0.96)
const OUTLINE := Color(0.05, 0.05, 0.05, 1.0)
const TEXT_COLOR := Color(0.1, 0.1, 0.12, 1.0)
## Issue #383: the THOUGHT cloud reads wrong — its middle must be
## filled white (the bump circles only fringe the border, so the text
## floated over the world behind), and its text sits a little lower
## than in the flat balloons (the cloud adds visual height above).
const THOUGHT_TEXT_DROP := 4.0
const BORDER := 3.0
## Thought-cloud bump radius and the trailing bubbles' radii.
const BUMP := 9.0
const TRAIL := [8.0, 6.0, 4.0]

var kind: int = Kind.SPEECH

var _age := 0.0
var _line := ""


## Issue #335: pop `line` above `figure` — the one door characters speak
## through (CharacterLines.say). One balloon per figure: an older one is
## replaced.
static func speak(figure: Node, line: String, bubble_kind: int = Kind.SPEECH) -> void:
	if figure == null or not is_instance_valid(figure):
		return
	var old := figure.get_node_or_null(NodePath("SpeechBubble"))
	if old != null:
		# Detach at once: a merely queue_free()d balloon still owns its
		# name until the end of the frame, and a same-named sibling would
		# be auto-renamed (breaking later lookups).
		figure.remove_child(old)
		old.queue_free()
	var bubble := SpeechBubble.new()
	bubble.kind = bubble_kind
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure.add_child(bubble)
	bubble._setup(line)


func _setup(line: String) -> void:
	name = "SpeechBubble"
	_line = line
	var font := ThemeDB.fallback_font
	var text_size := font.get_multiline_string_size(_line,
			HORIZONTAL_ALIGNMENT_CENTER, MAX_TEXT_WIDTH, FONT_SIZE)
	var width := text_size.x + PADDING.x * 2.0
	var height := text_size.y + PADDING.y * 2.0 + TEXT_DROP
	if kind == Kind.THOUGHT:
		height += THOUGHT_TEXT_DROP
	offset_left = -width / 2.0
	offset_right = width / 2.0
	offset_top = -RISE - height
	offset_bottom = -RISE
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= SHOW_TIME:
		queue_free()
		return
	# Quick fade over the last stretch so lines leave softly.
	modulate.a = clampf((SHOW_TIME - _age) / 0.3, 0.0, 1.0)


func _draw() -> void:
	match kind:
		Kind.SPEECH:
			_draw_speech()
		Kind.THOUGHT:
			_draw_thought()
		_:
			_draw_shout()


## SPEECH: rounded rectangle with a tail down to the speaker.
func _draw_speech() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = FILL
	box.set_border_width_all(BORDER)
	box.border_color = OUTLINE
	box.set_corner_radius_all(14.0)
	box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	# Tail: an outline triangle tucked under the border, then the fill on
	# top — the balloon's mouth opens where the tail meets the body.
	var cx := size.x / 2.0
	_poly([Vector2(cx - 11.0, size.y - BORDER), Vector2(cx + 11.0, size.y - BORDER),
			Vector2(cx, size.y + 14.0)], OUTLINE)
	_poly([Vector2(cx - 8.0, size.y - BORDER - 1.0), Vector2(cx + 8.0, size.y - BORDER - 1.0),
			Vector2(cx, size.y + 11.0)], FILL)
	_draw_text()


## THOUGHT: a cloud of bumps around the text with small bubbles trailing
## down to the thinker.
func _draw_thought() -> void:
	var a := size.x / 2.0 - BUMP * 0.3
	var b := size.y / 2.0 - BUMP * 0.3
	var center := size / 2.0
	var steps := maxi(8, int(TAU * maxf(a, b) / (BUMP * 1.3)))
	# Trail bubble centres: from the cloud's bottom edge toward the figure.
	var trail: Array[Vector2] = [Vector2(center.x, size.y - 2.0)]
	for i in TRAIL.size():
		var r: float = TRAIL[i]
		var next_r: float = TRAIL[i + 1] if i + 1 < TRAIL.size() else r * 0.7
		trail.append(trail.back() + Vector2(4.0, (r + next_r) * 0.9))
	# Two passes: outline first, fill second — the fills cover the
	# outlines where shapes overlap, leaving a scalloped border around
	# the cloud and a clean white interior (trail dots included).
	for pass_color in [OUTLINE, FILL]:
		var outline_pass: bool = pass_color == OUTLINE
		if not outline_pass:
			# Issue #383: fill the cloud's middle. The bump circles only
			# reach BUMP deep from the ellipse curve, so a wide, low cloud
			# had a see-through middle; a filled ellipse on the bump ring's
			# footprint closes it (the bumps still cap its edge).
			var cloud := PackedVector2Array()
			for i in 24:
				var fill_angle := TAU * i / 24.0
				cloud.append(center + Vector2(cos(fill_angle) * a, sin(fill_angle) * b))
			draw_colored_polygon(cloud, FILL)
		for i in steps:
			var angle := TAU * i / steps
			var p := center + Vector2(cos(angle) * a, sin(angle) * b)
			draw_circle(p, BUMP + (BORDER if outline_pass else 0.0), pass_color)
		for i in TRAIL.size():
			draw_circle(trail[i + 1], TRAIL[i]
					+ (BORDER if outline_pass else 0.0), pass_color)
	_draw_text()


## SHOUT: spiky starburst around the text.
func _draw_shout() -> void:
	var center := size / 2.0
	var inner := size / 2.0 + Vector2(4.0, 4.0)
	var points := PackedVector2Array()
	var spikes := 14
	for i in spikes * 2:
		var angle := TAU * i / (spikes * 2.0) - PI / 2.0
		# Outer spikes jitter a little (deterministic per index) for a
		# hand-drawn feel; inner points hug the text block.
		var jitter := 1.0 + 0.18 * float((i * 7) % 5 - 2)
		var radius := inner + Vector2(16.0, 18.0) * jitter if i % 2 == 0 else inner
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, FILL)
	points.append(points[0])
	draw_polyline(points, OUTLINE, BORDER, true)
	_draw_text()


func _draw_text() -> void:
	# Issue #383: the thought cloud's text sits a little lower.
	var extra_drop := THOUGHT_TEXT_DROP if kind == Kind.THOUGHT else 0.0
	var font := ThemeDB.fallback_font
	draw_multiline_string(font, Vector2(PADDING.x, PADDING.y + TEXT_DROP + extra_drop), _line,
			HORIZONTAL_ALIGNMENT_CENTER, size.x - PADDING.x * 2.0,
			FONT_SIZE, -1, TEXT_COLOR)


## Filled triangle (a tiny polygon helper for the speech tail).
func _poly(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
