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

@export var eyebrow_style: EyebrowStyle = EyebrowStyle.RAISED:
	set(value):
		eyebrow_style = value
		queue_redraw()

@export var eyebrow_color := Color(0.12, 0.08, 0.16, 1.0):
	set(value):
		eyebrow_color = value
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
	var radius := s.x * (0.10 if eye_style == EyeStyle.WIDE else 0.08)
	if eye_style == EyeStyle.HAPPY:
		# Closed happy eye: an upward arch (^) per eye.
		for side in [-1.0, 1.0]:
			var center := Vector2(s.x * 0.5 + side * s.x * 0.15, eye_y)
			draw_arc(center, radius * 0.85, PI, TAU, 16, pupil_color, 2.2 * u)
		return
	for side in [-1.0, 1.0]:
		var center := Vector2(s.x * 0.5 + side * s.x * 0.15, eye_y)
		# Issue #558: the animated pupil glance offset (fraction of the
		# eye radius, zero when the face is not animated).
		var shift := pupil_shift * radius
		draw_circle(center + shift, radius, eye_white)
		draw_circle(center + Vector2(0.0, radius * 0.25) + shift,
				radius * 0.45, pupil_color)
		# Issue #558: the animated blink — a body-colored lid slides over
		# the eye from the top (eye_open = 1 draws no lid at all).
		if eye_open < 0.999:
			var lid_h := radius * 2.0 * (1.0 - eye_open)
			draw_rect(Rect2(center.x - radius * 1.15, center.y - radius,
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
	var y := s.y * 0.44 + off - s.y * 0.16
	var length := s.x * 0.15
	var width := 0.055 * s.x
	var tilt := s.y * 0.035
	for side in [-1.0, 1.0]:
		var x: float = s.x * 0.5 + side * s.x * 0.15
		# inner end = towards the face center, outer end = away from it.
		var inner := Vector2(x - side * length * 0.5, y)
		var outer := Vector2(x + side * length * 0.5, y)
		match eyebrow_style:
			EyebrowStyle.ANGRY:
				inner.y += tilt
				outer.y -= tilt
			EyebrowStyle.RAISED:
				# Surprised arch above the eye.
				draw_arc(Vector2(x, y), length * 0.6, PI, TAU, 16,
						eyebrow_color, width)
				continue
			EyebrowStyle.WORRIED:
				inner.y -= tilt
				outer.y += tilt
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
