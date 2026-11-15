extends Control
## Issue #557: reusable modular character VISUAL — a geometric body with
## a bold cartoon outline and expressive facial features (eyes, eyebrows,
## mouth), drawn procedurally like ShapeVisual (no sprites, no assets).
##
## Purely visual: no collision, no physics, no gameplay code. Embed it
## under a CharacterBody2D the way ShapeVisual bodies are embedded
## (Player/Npc _apply_team_shape), or use it standalone in menus. The
## square is the first example (scenes/characters/SquareCharacter.tscn);
## the body drawer knows every ShapeVisual silhouette (square, circle,
## triangle, star, ellipse) so other geometric characters reuse this one
## component.
##
## Everything is configurable from the Inspector or from code (property
## setters redraw); no look change requires editing the scene.

## Body silhouette, one of: square, circle, triangle, star, ellipse
## (same names and polygons as ShapeVisual).
@export var body_shape := "square":
	set(value):
		body_shape = value
		queue_redraw()

## Fill of the geometric body — the team color.
@export var body_color := Color(1, 0.84, 0.2, 1):
	set(value):
		body_color = value
		queue_redraw()

## Bold cartoon outline around the body.
@export var outline_color := Color(0.12, 0.08, 0.16, 1.0):
	set(value):
		outline_color = value
		queue_redraw()

## Outline thickness in px at the reference 64 px body — thick on purpose
## (cartoon-bold, see the issue references).
@export var outline_width := 5.0:
	set(value):
		outline_width = maxf(value, 0.0)
		queue_redraw()

## Facial features — each is styled independently of the others.
enum EyeStyle { NONE, NORMAL, WIDE, SLEEPY, HAPPY }
enum EyebrowStyle { NONE, FLAT, ANGRY, RAISED, WORRIED }
enum MouthStyle { NONE, NEUTRAL, SMILE, FROWN, OPEN }

## Issue #559: whole-face EXPRESSIONS — a named mood composed from an
## eye, an eyebrow and a mouth configuration (the feature enums above).
## Setting `expression` (or calling set_expression) applies the whole
## composition at once; each feature stays independently settable
## afterwards for fine-tuning. The weapon system is a SEPARATE sibling
## node and never reads or moves the face — expressions and weapons do
## not affect each other (see Weapon.HELD_ANCHOR for the face-clear
## weapon anchor).
enum ExpressionType { NEUTRAL, ANGRY, FRIENDLY, CONFIDENT, SLEEPY, SCARED, SURPRISED }

## The feature composition of every expression: which eye, eyebrow and
## mouth style each mood is made of. Faces are BUILT from these three
## parts, exactly as the issue asks — no per-expression sprites.
const EXPRESSION_FEATURES := {
	ExpressionType.NEUTRAL: {
		"eye": EyeStyle.NORMAL, "brow": EyebrowStyle.FLAT,
		"mouth": MouthStyle.NEUTRAL,
	},
	ExpressionType.ANGRY: {
		"eye": EyeStyle.NORMAL, "brow": EyebrowStyle.ANGRY,
		"mouth": MouthStyle.FROWN,
	},
	ExpressionType.FRIENDLY: {
		"eye": EyeStyle.HAPPY, "brow": EyebrowStyle.RAISED,
		"mouth": MouthStyle.SMILE,
	},
	ExpressionType.CONFIDENT: {
		"eye": EyeStyle.SLEEPY, "brow": EyebrowStyle.FLAT,
		"mouth": MouthStyle.SMILE,
	},
	## Issue #585: the SLEEPY mood the issue lists among its six — a
	## droopy-eyed face that is NOT the confident smirk (flat mouth,
	## heavy lids) so a drowsy character reads at a glance.
	ExpressionType.SLEEPY: {
		"eye": EyeStyle.SLEEPY, "brow": EyebrowStyle.FLAT,
		"mouth": MouthStyle.NEUTRAL,
	},
	ExpressionType.SCARED: {
		"eye": EyeStyle.WIDE, "brow": EyebrowStyle.WORRIED,
		"mouth": MouthStyle.OPEN,
	},
	ExpressionType.SURPRISED: {
		"eye": EyeStyle.WIDE, "brow": EyebrowStyle.RAISED,
		"mouth": MouthStyle.OPEN,
	},
}

## Issue #559: the character's current mood. The property setter IS the
## simple API — `visual.expression = ExpressionType.ANGRY` restyles the whole
## face in one assignment (see also set_expression for name-based calls).
@export var expression: ExpressionType = ExpressionType.NEUTRAL:
	set(value):
		var key := expression_key(value)
		if key < 0:
			return
		expression = key
		apply_expression_features(key)

@export var eye_style: EyeStyle = EyeStyle.NORMAL:
	set(value):
		eye_style = value
		queue_redraw()

## Whites of the eyes.
@export var eye_white := Color.WHITE:
	set(value):
		eye_white = value
		queue_redraw()

## Pupils (and the closed-eye line of the HAPPY eyes).
@export var pupil_color := Color(0.12, 0.08, 0.16, 1.0):
	set(value):
		pupil_color = value
		queue_redraw()

## Issue #558: animation hooks, driven by CharacterAnimator (harmless
## on their own). eye_open < 1 draws a lid closing over the eye
## (0 = fully closed — the blink); pupil_shift moves both pupils by a
## fraction of the eye radius (small idle glances).
@export_range(0.0, 1.0, 0.01) var eye_open := 1.0:
	set(value):
		eye_open = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var pupil_shift := Vector2.ZERO:
	set(value):
		pupil_shift = value
		queue_redraw()

## Issue #585: INDEPENDENT pupils — per-eye gaze offsets on top of the
## shared glance (same unit: a fraction of the eye radius). The left
## eye can look left while the right looks at the target, a wall-eyed
## or focused gaze; 0 keeps the eye on the shared pupil_shift line.
@export var pupil_shift_left := Vector2.ZERO:
	set(value):
		pupil_shift_left = value
		queue_redraw()

@export var pupil_shift_right := Vector2.ZERO:
	set(value):
		pupil_shift_right = value
		queue_redraw()

## Issue #585: eye SIZE — a scale multiplier on the eye (whites,
## pupils, glints and lids all derive from the radius, so they scale
## together). 1.0 keeps the authored cartoon proportions; pairs with
## the eyebrow_lift/tilt exports to fine-tune a bigger-eyed look.
@export_range(0.5, 1.6, 0.01) var eye_size := 1.0:
	set(value):
		eye_size = value
		queue_redraw()

@export var eyebrow_style: EyebrowStyle = EyebrowStyle.RAISED:
	set(value):
		eyebrow_style = value
		queue_redraw()

@export var eyebrow_color := Color(0.12, 0.08, 0.16, 1.0):
	set(value):
		eyebrow_color = value
		queue_redraw()

## Issue #586: eyebrow POSITION offset — extra lift as a fraction of
## the body height (positive = higher, negative = lower). 0 keeps the
## style's authored spot; it composes with every eyebrow style.
@export var eyebrow_lift := 0.0:
	set(value):
		eyebrow_lift = value
		queue_redraw()

## Issue #586: eyebrow ROTATION offset — extra degrees BOTH brows turn
## by around their own centers (positive = clockwise). 0 keeps the
## style's authored angle; compose with the lift to fine-tune any mood.
@export var eyebrow_tilt_deg := 0.0:
	set(value):
		eyebrow_tilt_deg = value
		queue_redraw()

@export var mouth_style: MouthStyle = MouthStyle.SMILE:
	set(value):
		mouth_style = value
		queue_redraw()

@export var mouth_color := Color(0.12, 0.08, 0.16, 1.0):
	set(value):
		mouth_color = value
		queue_redraw()

## All face metrics are fractions of the control size, so the face
## scales with the body. Reference body = 64 px.
const REF_SIZE := 64.0

## Horizontal centers of the eyes and the eyebrows, as a fraction of
## the body width — one shared constant keeps the brows tracking the
## eyes when the face proportions are retuned (issue #586).
const EYE_SPAN := 0.16

func _draw() -> void:
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		return
	var u := minf(s.x, s.y) / REF_SIZE
	# 1) Body: bold outline pass first (behind), the fill on top of it.
	var outline_scale := 1.0 + 2.0 * outline_width * u / minf(s.x, s.y)
	_draw_body(s, outline_color, outline_scale)
	_draw_body(s, body_color, 1.0)
	# 2) Face on top of the body fill.
	_draw_face(s, u)


## Convenience for future wiring into Player/Npc/TeamMenu: apply a team
## look in one call (same arguments ShapeVisual consumers pass today).
func set_team_look(color: Color, shape: String) -> void:
	body_color = color
	body_shape = shape


## Issue #556: ShapeVisual API parity — Player/Npc embed this component
## as the gameplay body visual exactly where the old ShapeVisual sat
## (FigurePose.is_body_child, the damage hit flashes and the Npc body
## tint all speak the set_shape/set_shape_color protocol).
func set_shape(value: String) -> void:
	body_shape = value


func set_shape_color(value: Color) -> void:
	body_color = value


## Issue #556: per-figure resting PERSONALITIES — a stable member index
## picks a mood so one team reads as several characters (the confident
## one, the friendly one, the grumpy one...), not identical clones.
const PERSONALITIES := [
	ExpressionType.NEUTRAL, ExpressionType.FRIENDLY,
	ExpressionType.CONFIDENT, ExpressionType.ANGRY,
	ExpressionType.SLEEPY,
]


static func personality_for_index(index: int) -> ExpressionType:
	return PERSONALITIES[absi(index) % PERSONALITIES.size()]


## Issue #556: full team look in one call — body color, silhouette and
## the member's resting personality (a stable member index; the mood is
## the RESTING face, gameplay still overrides it — charge focus, damage
## flinch and the airborne face all win, see CharacterAnimator).
func apply_team_look(color: Color, shape: String, member_index := 0) -> void:
	set_team_look(color, shape)
	set_expression(personality_for_index(member_index))


## Issue #559 simple API: set the whole face in one call. Accepts an
## Expression enum value or its name in any letter case ("angry",
## "Scared", "SURPRISED"). An unknown name changes NOTHING — the face
## keeps its current look — so gameplay code can feed names straight
## from data tables without a crash risk.
func set_expression(value: Variant) -> void:
	var key := expression_key(value)
	if key >= 0:
		expression = key


## Apply the feature composition of one expression (an Expression key).
## Publishing point of the expression system: everything routes here.
func apply_expression_features(key: int) -> void:
	if not EXPRESSION_FEATURES.has(key):
		return
	var features: Dictionary = EXPRESSION_FEATURES[key]
	eye_style = features["eye"]
	eyebrow_style = features["brow"]
	mouth_style = features["mouth"]
	_expression_authored = true


## Normalize anything a call site offers — an Expression enum value or
## its name in any letter case — to the enum key. -1 = unknown value.
static func expression_key(value: Variant) -> int:
	if value is int:
		return value if EXPRESSION_FEATURES.has(value) else -1
	if value is float:
		var as_int := int(value)
		return as_int if EXPRESSION_FEATURES.has(as_int) else -1
	var key: Variant = ExpressionType.get(String(value).to_upper())
	return int(key) if key != null else -1


## True once an expression has been applied — CharacterAnimator shows
## the expression's face on the ground instead of the authored trio
## (authored #557 faces keep their authored look until then).
func has_expression() -> bool:
	return _expression_authored


## Set by apply_expression_features (see has_expression).
var _expression_authored := false


## Same silhouette drawer as ShapeVisual (kept identical so every
## existing team shape can become a modular character unchanged):
## a scaled silhouette drawn behind the fill acts as the outline.
func _draw_body(s: Vector2, color: Color, scale_f: float) -> void:
	var c := s / 2.0
	match body_shape:
		"circle", "ellipse":
			var y_scale := 1.0 if body_shape == "circle" else s.y / s.x
			draw_set_transform(c, 0.0, Vector2(scale_f, y_scale * scale_f))
			draw_circle(Vector2.ZERO, s.x / 2.0, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"triangle":
			draw_colored_polygon(_scaled(PackedVector2Array([
				Vector2(c.x, s.y * 0.06), Vector2(s.x * 0.96, s.y * 0.94),
				Vector2(s.x * 0.04, s.y * 0.94)
			]), c, scale_f), color)
		"star":
			var points := PackedVector2Array()
			var outer := s.x / 2.0
			var inner := outer * 0.45
			for i in 10:
				var angle := -PI / 2.0 + TAU * i / 10.0
				var radius := outer if i % 2 == 0 else inner
				points.append(c + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(_scaled(points, c, scale_f), color)
		_:
			# Square: plain filled rect (same look as the authored ColorRect).
			var half := s * 0.5 * scale_f
			draw_rect(Rect2(c - half, half * 2.0), color)


func _scaled(points: PackedVector2Array, c: Vector2, scale_f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(c + (p - c) * scale_f)
	return out


## Pointed silhouettes (triangle, star) get no body area at the top, so
## their face sits a bit lower to stay inside the fill.
func _face_y_offset(s: Vector2) -> float:
	if body_shape == "triangle" or body_shape == "star":
		return s.y * 0.06
	return 0.0


func _draw_face(s: Vector2, u: float) -> void:
	var off := _face_y_offset(s)
	_draw_eyes(s, off, u)
	_draw_eyebrows(s, off, u)
	_draw_mouth(s, off)


func _draw_eyes(s: Vector2, off: float, u: float) -> void:
	if eye_style == EyeStyle.NONE:
		return
	var eye_y := s.y * 0.44 + off
	# Issue #586: bigger cartoon eyes — the proportion refinement that
	# makes the face read as a character, not an emoji sticker.
	# Issue #585: eye_size scales the whole eye (shape AND size stay
	# configurable, per the issue's expressive-eyes section).
	var radius := s.x * (0.115 if eye_style == EyeStyle.WIDE else 0.10) * eye_size
	if eye_style == EyeStyle.HAPPY:
		# Closed happy eye: an upward arch (^) per eye.
		for side in [-1.0, 1.0]:
			var center := Vector2(s.x * 0.5 + side * s.x * EYE_SPAN, eye_y)
			draw_arc(center, radius * 0.85, PI, TAU, 16, pupil_color, 2.2 * u)
		return
	for side in [-1.0, 1.0]:
		var center := Vector2(s.x * 0.5 + side * s.x * EYE_SPAN, eye_y)
		# Issue #558: the animated pupil glance offset (fraction of the
		# eye radius, zero when the face is not animated).
		# Issue #585: the per-eye gaze composes with the shared glance —
		# each pupil can also move on its own (independent gaze).
		var shift := (pupil_shift \
				+ (pupil_shift_left if side < 0.0 else pupil_shift_right)) \
				* radius
		var pupil_center := center + Vector2(0.0, radius * 0.25) + shift
		var pupil_r := radius * 0.45
		draw_circle(center + shift, radius, eye_white)
		draw_circle(pupil_center, pupil_r, pupil_color)
		# Issue #586: pupil highlight — the small white glint that makes
		# the eye read as glossy. It moves with the pupil and sits UNDER
		# the blink/sleepy lids, so a closing lid covers it naturally.
		draw_circle(pupil_center + Vector2(-0.35, -0.35) * pupil_r,
				pupil_r * 0.32, eye_white)
		# Issue #558: the animated blink — a body-colored lid slides over
		# the eye from the top (eye_open = 1 draws no lid at all). It
		# follows the eye's own shift so an independently glancing pupil
		# stays covered too (issue #585).
		if eye_open < 0.999:
			var lid_h := radius * 2.0 * (1.0 - eye_open)
			draw_rect(Rect2(center.x + shift.x - radius * 1.15,
					center.y + shift.y - radius,
					radius * 2.3, lid_h), body_color)
		if eye_style == EyeStyle.SLEEPY:
			# Half-closed lid: body-colored cover over the eye's top plus
			# a dark edge line where the lid ends.
			var lid_top := center.y - radius * 1.3
			var lid_h := radius * 1.55
			draw_rect(Rect2(center.x - radius * 1.15, lid_top,
					radius * 2.3, lid_h), body_color)
			draw_line(Vector2(center.x - radius * 0.9, lid_top + lid_h),
					Vector2(center.x + radius * 0.9, lid_top + lid_h),
					pupil_color, 1.6 * u)


func _draw_eyebrows(s: Vector2, off: float, u: float) -> void:
	if eyebrow_style == EyebrowStyle.NONE:
		return
	# Issue #586: the configurable POSITION — eyebrow_lift raises/lowers
	# both brows on top of the style's authored height.
	var y := s.y * 0.44 + off - s.y * 0.16 - eyebrow_lift * s.y
	var length := s.x * 0.15
	var width := 0.055 * s.x
	var tilt := s.y * 0.035
	# Issue #586: the configurable ROTATION — both brows turn by the
	# same extra angle around their own centers.
	var rot := deg_to_rad(eyebrow_tilt_deg)
	for side in [-1.0, 1.0]:
		var x: float = s.x * 0.5 + side * s.x * EYE_SPAN
		var brow_center := Vector2(x, y)
		# inner end = towards the face center, outer end = away from it.
		var inner := Vector2(x - side * length * 0.5, y)
		var outer := Vector2(x + side * length * 0.5, y)
		match eyebrow_style:
			EyebrowStyle.ANGRY:
				inner.y += tilt
				outer.y -= tilt
			EyebrowStyle.RAISED:
				# Surprised arch above the eye (turns with the tilt config).
				if rot == 0.0:
					draw_arc(brow_center, length * 0.6, PI, TAU, 16,
						eyebrow_color, width)
				else:
					draw_set_transform(brow_center, rot)
					draw_arc(Vector2.ZERO, length * 0.6, PI, TAU, 16,
						eyebrow_color, width)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				continue
			EyebrowStyle.WORRIED:
				inner.y -= tilt
				outer.y += tilt
		if rot != 0.0:
			inner = brow_center + (inner - brow_center).rotated(rot)
			outer = brow_center + (outer - brow_center).rotated(rot)
		draw_line(inner, outer, eyebrow_color, width)


func _draw_mouth(s: Vector2, off: float) -> void:
	if mouth_style == MouthStyle.NONE:
		return
	var width := 0.055 * s.x
	var cx := s.x * 0.5
	match mouth_style:
		MouthStyle.NEUTRAL:
			draw_line(Vector2(cx - s.x * 0.11, s.y * 0.68 + off),
					Vector2(cx + s.x * 0.11, s.y * 0.68 + off),
					mouth_color, width)
		MouthStyle.SMILE:
			# Arc below the center point bulges down: a smile.
			draw_arc(Vector2(cx, s.y * 0.64 + off), s.x * 0.13,
					0.12 * PI, 0.88 * PI, 24, mouth_color, width)
		MouthStyle.FROWN:
			# Arc above the center point bulges up: a frown.
			draw_arc(Vector2(cx, s.y * 0.74 + off), s.x * 0.13,
					1.12 * PI, 1.88 * PI, 24, mouth_color, width)
		MouthStyle.OPEN:
			draw_set_transform(Vector2(cx, s.y * 0.67 + off), 0.0,
					Vector2(1.0, 0.75))
			draw_circle(Vector2.ZERO, s.x * 0.085, mouth_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
