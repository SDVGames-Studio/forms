class_name CartoonBlast
extends Node2D
## Cartoon EXPLOSION and HIT effects (issue #718, roadmap part 3c —
## "Impact, Explosion & Hit Effects").
##
## Two looks, one node: a big BLAST fireball for every explosion and a
## small comic HIT star for damage landing on a figure — both in the
## same visual language as the redesigned weapons and characters: bold
## dark outlines, flat vivid fills, exaggerated silhouettes. Drawn
## entirely in code — no assets — and shared by every damage source
## through the static pop()/pop_hit() factories, so no weapon ever
## wires its own effect again (issue #718 acceptance: reusable
## components, no per-weapon code duplication).
##
## The blast fireball is deliberately SMALLER at its peak than the true
## blast radius (the BlastRing of issue #150 still draws the exact
## damage circle) and layers over the #368 light flash like the muzzle
## flash does: the glow reads underneath, gameplay information — the
## radius ring, the figures, the terrain — stays readable. Purely
## visual: nothing in the game reads this node, and it frees itself
## when the animation ends.

enum Mode { BLAST, HIT }

## How long the explosion fireball stays on screen (seconds).
const BLAST_TIME := 0.45
## How long a hit star stays on screen (seconds) — short by design.
const HIT_TIME := 0.22
## The shared dark cartoon outline of the weapon/character art (same
## value as MuzzleFlash so every effect rims identically).
const OUTLINE := Color(0.13, 0.10, 0.08, 1.0)
## Flat fill layers: hot orange ring, vivid yellow ring, white core.
const FILL_OUTER := Color(1.0, 0.42, 0.10, 1.0)
const FILL_INNER := Color(1.0, 0.78, 0.16, 1.0)
const CORE := Color(1.0, 0.97, 0.86, 1.0)
## Soft gray smoke wisps that trail the fireball as it burns out.
const SMOKE := Color(0.42, 0.38, 0.35, 1.0)
## Hit star fills: white body with a small yellow inner star.
const HIT_INNER := Color(1.0, 0.80, 0.15, 1.0)

## BLAST: peak fireball radius in px (stays below the blast radius).
## HIT: outer spike reach of the comic star in px.
var size := 60.0

## Which look this node draws.
var mode: int = Mode.BLAST

## Animation progress 0→1, tweened linearly; every visual curve (the
## eased expansion, the fading layers, the debris flight) is derived
## from it inside _draw so each part can ease independently. The
## setter repaints on every step — one tween drives the whole effect.
var progress := 0.0:
	set(v):
		progress = v
		queue_redraw()

## Debris fleck flight angles — random per instance so two blasts in a
## chain reaction never look photocopied.
var _fleck_angles: PackedFloat32Array = []
## Smoke wisp directions — a fan around straight up.
var _smoke_angles: PackedFloat32Array = []

## Issue #720 (part 4b): optional per-weapon HIT palette (fed from the
## WeaponVisuals "flash" registry entry — the same "inner"/"core"
## colors as the weapon's muzzle burst, so a weapon's impacts read in
## its own family). The defaults keep the #718 warm comic star for
## every existing caller.
var hit_inner := HIT_INNER
var hit_core := CORE


func _init() -> void:
	for i in 7:
		_fleck_angles.append(randf() * TAU)
	for i in 4:
		_smoke_angles.append(-PI / 2.0 + randf_range(-0.6, 0.6))


## Pop a cartoon EXPLOSION fireball under `parent` at world position
## `at`. `blast_radius` is the weapon's real blast radius in px — the
## fireball peaks clearly below it so the BlastRing damage circle and
## the figures around it stay readable. The node animates and frees
## itself; nothing else needs to track it.
static func pop(parent: Node, at: Vector2, blast_radius: float) -> CartoonBlast:
	var fx := CartoonBlast.new()
	fx.mode = Mode.BLAST
	fx.size = maxf(blast_radius, 40.0)
	parent.add_child(fx)
	fx.global_position = at
	fx.z_index = 60
	fx._animate(BLAST_TIME)
	return fx


## Pop a small comic HIT star under `parent` at world position `at`.
## `intensity` scales the star — bigger hits read bigger (callers pass
## a damage-derived value). Randomly rotated so repeated grind hits
## never look like a strobing stamp.
static func pop_hit(parent: Node, at: Vector2, intensity := 1.0,
		palette := {}) -> CartoonBlast:
	var fx := CartoonBlast.new()
	fx.mode = Mode.HIT
	fx.size = 11.0 * clampf(intensity, 0.6, 2.0)
	# Issue #720 (part 4b): the per-weapon palette override, when the
	# caller passes one (see Weapon._fire_railgun).
	fx.hit_inner = palette.get("inner", HIT_INNER) as Color
	fx.hit_core = palette.get("core", CORE) as Color
	parent.add_child(fx)
	fx.global_position = at
	fx.z_index = 60
	fx.rotation = randf() * TAU
	fx._animate(HIT_TIME)
	return fx


## Tween the progress to 1, then free. One linear tween — the easing
## of every drawn part happens inside _draw.
func _animate(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, duration)
	tween.tween_callback(queue_free)


func _draw() -> void:
	if mode == Mode.HIT:
		_draw_hit()
	else:
		_draw_blast()


## The explosion: a fireball of stacked flat circles (bold dark rim ->
## orange -> yellow -> a white-hot core that shrinks as it burns out),
## debris flecks flying outward, and smoke wisps trailing on top of the
## fade. All curves come from the linear `progress`.
func _draw_blast() -> void:
	var p := progress
	var eased := 1.0 - pow(1.0 - p, 3.0)
	# Peak radius stays below `size` (the true blast radius) by design.
	var r := size * (0.30 + 0.55 * eased)
	var alpha := pow(1.0 - p, 1.35)
	# Smoke first (behind everything): gray puffs that only exist in
	# the burn-out half and drift outward while fading.
	var smoke_alpha := 0.45 * clampf((p - 0.35) / 0.2, 0.0, 1.0) * (1.0 - p)
	if smoke_alpha > 0.01:
		for ang in _smoke_angles:
			var off := Vector2(cos(ang), sin(ang)) \
					* (r * 0.55 + size * 0.5 * p)
			draw_circle(off, size * (0.10 + 0.16 * p), Color(SMOKE, smoke_alpha))
	# The fireball: each circle is a flat fill; the dark one behind is
	# the bold rim. The white-hot core shrinks as the fireball ages.
	draw_circle(Vector2.ZERO, r, Color(OUTLINE, alpha))
	draw_circle(Vector2.ZERO, r * 0.86, Color(FILL_OUTER, alpha))
	draw_circle(Vector2.ZERO, r * 0.62, Color(FILL_INNER, alpha))
	var core := r * clampf(0.34 - 0.26 * eased, 0.08, 1.0)
	draw_circle(Vector2.ZERO, core, Color(CORE, alpha))
	# Debris last (in front): dark-rimmed diamonds flying outward on a
	# straight (linear) flight, shrinking and fading as they go.
	var fleck_alpha := pow(1.0 - p, 1.2)
	for ang in _fleck_angles:
		var dist := size * (0.5 + 1.1 * p)
		var center := Vector2(cos(ang), sin(ang)) * dist
		var s := size * 0.11 * (1.0 - 0.5 * p)
		_draw_diamond(center, s, Color(OUTLINE, fleck_alpha))
		_draw_diamond(center, s * 0.62, Color(FILL_INNER, fleck_alpha))


## The comic hit star: a sharp jagged "pow" burst — dark outline, white
## body, small yellow inner star — that snaps to full size fast and
## fades out just as quick.
func _draw_hit() -> void:
	var p := progress
	var eased := 1.0 - pow(1.0 - p, 3.0)
	var reach := size * (0.35 + 0.75 * eased)
	var alpha := 1.0 - p
	_draw_starburst(reach, Color(OUTLINE, alpha))
	_draw_starburst(reach * 0.78, Color(hit_core, alpha))
	_draw_starburst(reach * 0.50, Color(hit_inner, alpha))


## One jagged 6-spike starburst (long spike, deep notch, repeated) —
## the sharp comic silhouette, rotated by the node's own rotation.
func _draw_starburst(reach: float, color: Color) -> void:
	var points := PackedVector2Array()
	var spikes := 6
	for i in spikes:
		var a := TAU * i / spikes + rotation
		points.append(Vector2(cos(a), sin(a)) * reach)
		var b := TAU * (i + 0.5) / spikes + rotation
		points.append(Vector2(cos(b), sin(b)) * reach * 0.38)
	draw_colored_polygon(points, color)


## A small diamond (rotated square, slightly wide) used for debris
## flecks — drawn dark-rimmed by stacking a bigger outline diamond
## under a smaller fill.
func _draw_diamond(center: Vector2, s: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s * 0.7, 0),
		center + Vector2(0, s),
		center + Vector2(-s * 0.7, 0),
	])
	draw_colored_polygon(points, color)
