class_name ProjectileTrail
extends Node2D
## Cartoon projectile LAUNCH + TRAIL effects (issue #680 roadmap part 3b,
## sub-issue #717 — "Projectile Launch Animations & Trails").
##
## The visual sibling of MuzzleFlash (part 3, PR #715): where the flash
## marks the SHOT, this component gives the projectile itself its
## departure and in-flight character, in the same code-drawn cartoon
## language (flat vivid fills, soft outlines, nothing that needs an
## asset). It owns two jobs, both purely visual:
##
##   * LAUNCH data (STYLES below): every projectile pops out of the
##     muzzle with a short squash-and-stretch — the rocket/pellets
##     stretch ALONG their launch velocity, the grenade leaves the hand
##     with a small pop — and the numbers live in this one table so a
##     weapon's launch feel can be tuned as data (the WeaponVisuals
##     registry pattern, applied to projectiles). Projectile.gd and
##     ProjectileBody.gd read the table and animate their OWN visual
##     child — physics shapes, spawn timing and velocities are never
##     touched (issue acceptance: visuals only).
##
##   * TRAIL follower (follow()): a Node2D that rides along with a
##     flying projectile and stamps soft smoke PUFFS into the level at
##     the style's cadence. Each puff is an independent self-animating
##     node (grows, fades, frees itself), drawn BEHIND the gameplay
##     layer (z_index -1) so a trail never covers a figure, a mine or
##     the terrain edge — it fades cleanly and is gone in under a
##     second (part 3 acceptance: no lingering clutter).
##
## Puffs are stamped at world positions (children of the level, not of
## the projectile), so a trail stays where the flight WAS even after
## the projectile explodes; the follower itself simply frees when its
## target is gone. Nothing in the game reads any node from here.

## Per-projectile visual style, keyed by kind. Consumed by the
## projectile scripts (launch stretch applied to their own visual) and
## by follow() (trail cadence); unknown kinds fall back to no effect.
##   stretch      — visual scale the projectile is BORN at (Vector2;
##                  > 1 along x = motion stretch along the velocity,
##                  uniform < 1 = a pop out of the hand)
##   stretch_time — seconds until the stretch eases back to 1:1
##   tumble       — deg/s the visual spins at FULL flight speed (the
##                  grenade's in-flight character; 0 = no tumble)
##   trail        — true = follow() stamps smoke puffs
##   interval     — seconds between puffs
##   puff_size    — base puff radius in px (±20% hand-drawn jitter)
##   puff_life    — seconds a puff lives (grow + fade)
##   puff_grow    — how much a puff scales up over its life
##   puff_alpha   — starting alpha of the fill
const STYLES := {
	"rocket": {
		"stretch": Vector2(1.8, 0.7), "stretch_time": 0.2,
		"tumble": 0.0,
		"trail": true, "interval": 0.045,
		"puff_size": 7.0, "puff_life": 0.5,
		"puff_grow": 1.8, "puff_alpha": 0.55,
	},
	"grenade": {
		"stretch": Vector2(0.6, 0.6), "stretch_time": 0.15,
		"tumble": 540.0,
		"trail": false,
	},
	"pellet": {
		"stretch": Vector2(1.7, 0.8), "stretch_time": 0.15,
		"tumble": 0.0,
		"trail": false,
	},
	# mine / saw / rock: no entry — the mine must stay dark and stealthy
	# while dormant, the saw/rock are tool-like objects whose landing
	# behaviour (blade spin, crumble) already reads at a glance.
}

## The shared soft smoke tones (flat fills, no hard rim — smoke reads
## soft even in the outlined weapon style, and at 7 px a dark outline
## would turn the stream into a bead chain).
const SMOKE_FILL := Color(0.86, 0.86, 0.92, 1.0)
const SMOKE_HIGHLIGHT := Color(0.97, 0.97, 1.0, 0.85)

## The projectile this follower rides with (invalid → self-free).
var _target: Node2D = null
## Style dictionary (already checked for "trail" by follow()).
var _style: Dictionary = {}
## Seconds accumulated since the last puff.
var _acc := 0.0


## The style entry for a kind ({} when the kind has no entry).
static func style(kind: String) -> Dictionary:
	return STYLES.get(kind, {}) as Dictionary


## Launch data accessors for the projectile scripts (defaults keep a
## plain 1:1 pop when a kind carries no entry).
static func launch_stretch(kind: String) -> Vector2:
	return style(kind).get("stretch", Vector2.ONE) as Vector2


static func launch_stretch_time(kind: String) -> float:
	return maxf(style(kind).get("stretch_time", 0.15) as float, 0.01)


## In-flight tumble rate in rad/s at full speed (0 = no tumble).
static func tumble_rate(kind: String) -> float:
	return deg_to_rad(style(kind).get("tumble", 0.0) as float)


## Attach a trail follower to `target` under `parent` (the level root —
## puffs must live in world space, not on the projectile). Returns null
## when the kind carries no trail (most kinds) — callers may ignore the
## result, the follower animates and frees itself.
static func follow(parent: Node, target: Node2D,
		kind: String) -> ProjectileTrail:
	var s := style(kind)
	if not s.get("trail", false):
		return null
	var trail := ProjectileTrail.new()
	trail._target = target
	trail._style = s
	parent.add_child(trail)
	trail.global_position = target.global_position
	# The stream starts right at the launch point — one puff NOW, then
	# one per interval as the flight covers ground.
	trail._stamp_puff()
	return trail


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		# The projectile died (impact / fuse / lifetime). The puffs it
		# already stamped live on and fade on their own — this follower
		# has nothing left to track.
		queue_free()
		return
	global_position = _target.global_position
	_acc += delta
	# One puff per elapsed interval — while catches up after a long
	# frame without spawning a burst (at most one late puff per frame).
	if _acc >= _style.get("interval", 0.05) as float:
		_acc = 0.0
		_stamp_puff()


## Stamp one smoke puff at the projectile's current world position, as
## a child of the LEVEL (world-space trail), behind the gameplay layer.
func _stamp_puff() -> void:
	if get_parent() == null:
		return
	var puff := Puff.new()
	var base := _style.get("puff_size", 7.0) as float
	puff.radius = base * randf_range(0.8, 1.2)
	puff.life = _style.get("puff_life", 0.5) as float
	puff.grow = _style.get("puff_grow", 1.8) as float
	puff.alpha = _style.get("puff_alpha", 0.55) as float
	puff.fill = Color(ProjectileTrail.SMOKE_FILL.r,
			ProjectileTrail.SMOKE_FILL.g, ProjectileTrail.SMOKE_FILL.b,
			puff.alpha)
	puff.highlight = Color(ProjectileTrail.SMOKE_HIGHLIGHT.r,
			ProjectileTrail.SMOKE_HIGHLIGHT.g,
			ProjectileTrail.SMOKE_HIGHLIGHT.b,
			ProjectileTrail.SMOKE_HIGHLIGHT.a * puff.alpha)
	get_parent().add_child(puff)
	puff.global_position = global_position \
			+ Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	puff._animate()


## One soft smoke puff: a flat light disc with a lighter off-centre
## core, drawn behind the gameplay layer, growing and fading out on its
## own timeline. Self-contained — nobody references it.
class Puff:
	extends Node2D

	var radius := 7.0
	var life := 0.5
	var grow := 1.8
	var alpha := 0.55
	## Resolved fill colors (alpha baked in — see _stamp_puff).
	var fill := Color(0.86, 0.86, 0.92, 0.55)
	var highlight := Color(0.97, 0.97, 1.0, 0.47)

	func _ready() -> void:
		# Behind every default-z sibling: a trail reads through the air
		# but never covers a figure, a mine or a beam (part 3
		# acceptance — trails never obscure gameplay information).
		z_index = -1

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, fill)
		draw_circle(Vector2(-radius * 0.22, -radius * 0.22),
				radius * 0.55, highlight)

	## Grow while fading, then free — one short tween, no loops.
	func _animate() -> void:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "scale",
				Vector2.ONE * grow, life).from(Vector2.ONE * 0.7)
		tween.tween_property(self, "modulate:a", 0.0, life)
		tween.chain().tween_callback(queue_free)
