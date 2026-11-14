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
##
## Issue #395 (night regime): a bubble in the world canvas would be
## blacked out by the night mask, so while a NightRegime is active the
## balloon is added to the regime's CharacterLinesLayer (in front of
## the mask, below the OSD) instead and follows the speaker's on-screen
## position every frame. Teammates' balloons stay visible all night;
## an ENEMY's balloon shows exactly while its speaker is seen — inside
## a teammate's vision wedge or lit by a light source (NightRegime.is_lit).

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

## Issue #395: the speaker this balloon belongs to while the night
## regime is on (kept only as a weak reference — checked live).
var figure: Node = null

## The active night regime, or null in a normal (lit) level.
var _night: NightRegime = null
## Registry key of `figure` in _live (see speak).
var _speaker_id := 0

var _age := 0.0
var _line := ""

## Issue #395: figure instance id -> its live balloon. One balloon per
## figure, whichever canvas the bubble sits in (on the figure by day, in
## the CharacterLinesLayer at night) — a new line replaces the old one.
static var _live := {}


## Issue #335: pop `line` above `figure` — the one door characters speak
## through (CharacterLines.say). One balloon per figure: an older one is
## replaced.
static func speak(figure: Node, line: String, bubble_kind: int = Kind.SPEECH) -> void:
	if figure == null or not is_instance_valid(figure):
		return
	var key := figure.get_instance_id()
	if _live.has(key):
		# Issue #541: fetch the stored balloon UNTYPED. An expired
		# balloon can leave a freed instance behind in _live (see the
		# _speaker_id note below), and assigning a freed instance to a
		# typed var is itself the "Trying to assign invalid previously
		# freed instance" error — is_instance_valid() below then skips
		# it safely and a fresh balloon is built instead.
		var old = _live[key]
		if old != null and is_instance_valid(old):
			# Detach at once: a merely queue_free()d balloon still owns its
			# name until the end of the frame, and a same-named sibling would
			# be auto-renamed (breaking later lookups).
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.queue_free()
		_live.erase(key)
	var bubble := SpeechBubble.new()
	bubble.kind = bubble_kind
	# Issue #541: register the speaker in BOTH modes. A day-mode balloon
	# never had _speaker_id set, so when it expired (queue_free in
	# _process) the _exit_tree cleanup skipped it and left a FREED
	# instance in _live; the figure's next line then crashed in speak()
	# when rapid hits re-triggered it.
	bubble._speaker_id = key
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var night: NightRegime = null
	var tree := figure.get_tree()
	if tree != null:
		night = tree.get_first_node_in_group("night_regime") as NightRegime
	if night != null and night.lines_layer() != null:
		# Issue #395: the night regime is on — the balloon must not sit in
		# the world canvas (the mask would black it out). It lives in the
		# character-lines layer, follows the speaker on screen, and hides
		# for unseen enemies (see _process).
		night.lines_layer().add_child(bubble)
		bubble.figure = figure
		bubble._night = night
	else:
		figure.add_child(bubble)
	_live[key] = bubble
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
	if _night != null:
		# Issue #395: be right on the very first drawn frame — placed on
		# the speaker and gated by the speaker's visibility already.
		_follow_speaker()
		_update_seen()


func _process(delta: float) -> void:
	# Issue #541: the night regime may already be freed (level teardown
	# during rapid training resets) — drop the stale reference instead
	# of calling into a freed instance.
	if _night != null and not is_instance_valid(_night):
		_night = null
	if _night != null:
		# Issue #395: keep the balloon on the speaker and hide an enemy's
		# line while its speaker is not seen through the mask.
		_follow_speaker()
		_update_seen()
	_age += delta
	if _age >= SHOW_TIME:
		queue_free()
		return
	# Quick fade over the last stretch so lines leave softly.
	modulate.a = clampf((SHOW_TIME - _age) / 0.3, 0.0, 1.0)


## Issue #395: the balloon lives in the night CharacterLinesLayer, so
## it must track the speaker's on-screen position itself (that layer is
## not moved by the camera).
func _follow_speaker() -> void:
	if figure == null or not is_instance_valid(figure) \
			or not figure is CanvasItem:
		return
	position = (figure as CanvasItem).get_global_transform_with_canvas().origin


## Issue #395: teammates' lines stay readable all night; an enemy's line
## is visible exactly while the enemy is seen (vision wedge or light).
func _update_seen() -> void:
	if figure == null or not is_instance_valid(figure):
		visible = false
		return
	if figure.is_in_group("player_team"):
		visible = true
		return
	if figure is Node2D:
		visible = _night.is_lit((figure as Node2D).global_position)


func _exit_tree() -> void:
	# Issue #541/395: drop the balloon from the one-per-figure registry
	# (the figure may speak again later and must not find a stale entry).
	# _speaker_id is now set in BOTH day and night modes, so every
	# balloon cleans itself up when it expires or its parent is freed.
	if _speaker_id != 0 and _live.get(_speaker_id, null) == self:
		_live.erase(_speaker_id)


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
