class_name MuzzleFlash
extends Node2D
## Cartoon MUZZLE FLASH (issue #680, roadmap part 3 — "firing effects").
##
## A bold-outlined starburst that pops where a shot leaves the barrel,
## in the same visual language as the redesigned weapons: thick dark
## outline, flat vivid fills, and an exaggerated forward spike along
## the firing axis. Drawn entirely in code — no assets — and shared by
## every weapon through Weapon._muzzle_flash (the #368 light flash
## stays layered underneath for the glow).
##
## The burst lives FLASH_TIME seconds: it scales up fast, fades out and
## frees itself, so it never lingers over gameplay information (part 3
## acceptance). Purely visual — nothing in the game reads this node.

## How long the burst stays on screen (seconds) — short by design.
const FLASH_TIME := 0.14
## The shared dark cartoon outline color of the weapon art.
const OUTLINE := Color(0.13, 0.10, 0.08, 1.0)
## Flat fill layers: hot orange petals, vivid yellow inner, white core.
const FILL_OUTER := Color(1.0, 0.45, 0.10, 1.0)
const FILL_INNER := Color(1.0, 0.80, 0.15, 1.0)
const CORE := Color(1.0, 0.97, 0.86, 1.0)

## Burst radius in px — the forward spike reaches ~1.4x this.
var size := 22.0
## Issue #720 (roadmap part 4b): per-weapon PALETTE overrides (fed from
## the WeaponVisuals "flash" registry data). The defaults are the #715
## warm starburst; a style may re-palette the whole burst (the railgun's
## icy cyan burst matches its beam) by passing "outer"/"inner"/"core"
## colors through pop(). The dark outline stays shared — every rim in
## the weapon art uses the same dark cartoon line.
var fill_outer := FILL_OUTER
var fill_inner := FILL_INNER
var core_fill := CORE


## Pop a cartoon flash under `parent` at world position `at`, aimed
## along `dir` (the firing direction). The node animates and frees
## itself; nothing else needs to track it. `burst` overrides the
## radius; `palette` (the WeaponVisuals "flash" entry) may override
## the fill colors per weapon (issue #720, part 4b).
static func pop(parent: Node, at: Vector2, dir: Vector2,
		burst := 22.0, palette := {}) -> MuzzleFlash:
	var flash := MuzzleFlash.new()
	flash.size = burst
	flash.fill_outer = palette.get("outer", FILL_OUTER) as Color
	flash.fill_inner = palette.get("inner", FILL_INNER) as Color
	flash.core_fill = palette.get("core", CORE) as Color
	parent.add_child(flash)
	flash.global_position = at
	flash.rotation = dir.angle() if dir.length_squared() > 0.0001 else 0.0
	flash._animate()
	return flash


## Scale up while fading out, then free. One short tween, no loops.
func _animate() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale",
			Vector2.ONE * 1.15, FLASH_TIME).from(Vector2.ONE * 0.55)
	tween.tween_property(self, "modulate:a", 0.0, FLASH_TIME)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	# Three stacked starbursts shrink inward (outline -> orange ->
	# yellow), then a white-hot core circle with its own dark rim: the
	# bold-outline, flat-fill look of the launcher and shotgun art.
	# Issue #720: the fill layers are the per-weapon palette (the railgun
	# pops an icy cyan version); only the outline rim is shared.
	_draw_star(1.0, OUTLINE)
	_draw_star(0.80, fill_outer)
	_draw_star(0.58, fill_inner)
	draw_circle(Vector2.ZERO, size * 0.24, OUTLINE)
	draw_circle(Vector2.ZERO, size * 0.20, core_fill)


## One starburst layer: 8 spikes whose reach stretches along the +X
## firing axis (the cos bias — the forward spike is the longest, the
## backward one the shortest), with round notches between them.
func _draw_star(scale: float, color: Color) -> void:
	var points := PackedVector2Array()
	var spikes := 8
	for i in spikes:
		var a := TAU * i / spikes
		var reach := size * scale * (1.0 + 0.4 * cos(a))
		points.append(Vector2(cos(a), sin(a)) * reach)
		var b := a + PI / spikes
		var notch := size * scale * 0.42
		points.append(Vector2(cos(b), sin(b)) * notch)
	draw_colored_polygon(points, color)
