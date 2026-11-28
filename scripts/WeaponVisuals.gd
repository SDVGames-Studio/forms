extends RefCounted
## Reusable weapon VISUAL registry (issue #680, roadmap part 2 —
## "Implement a Reusable Weapon Visual System").
##
## Every held-weapon VISUAL now lives here, as data: which sprite (or
## plain rectangle fill) each weapon draws, at which in-game size, and
## HOW it is held (per-weapon positioning). Weapon.gd — the logic that
## fires, damages, budgets and hands turns over — only CONSUMES this
## table, so a weapon's artwork can be swapped, tuned or added without
## touching any weapon logic (part 2 acceptance), and every gameplay
## number stays where it always was (frozen by the issue).
##
## Attachment convention (shared by sprites and rectangles alike):
##   * the visual's CENTRE floats `anchor` px from the body CENTRE
##     along the AIM axis (default DEFAULT_ANCHOR, the #559 value that
##     keeps the weapon clear of the modular face zone);
##   * the visual ROTATES with the aim (rotation = aim angle);
##   * a textured style additionally rides lower on the body: its
##     height along the wielder's stance-gravity axis is
##     lift * lift_keep - drop (the #680 "held at the waist" hold —
##     see Weapon.gd's _physics_process), and flip_v keeps the grip
##     below the barrel once the aim swings past vertical.
##
## Entry keys (all optional except size):
##   size      — in-game px the visual is drawn at (Vector2)
##   color     — plain rectangle fill (styles without a texture)
##   texture   — renders the style as a centered Sprite2D instead of
##               the rectangle, scaled to `size`
##   anchor    — per-weapon anchor along the aim (default DEFAULT_ANCHOR)
##   lift_keep — per-weapon lift damping for textured styles
##               (default DEFAULT_LIFT_KEEP)
##   drop      — per-weapon fixed drop along the stance-gravity axis
##               (default DEFAULT_DROP)
##   recoil    — per-weapon RECOIL kick-back in px along the aim on a
##               committed shot (issue #680 part 3, visual only;
##               default DEFAULT_RECOIL, 0 for the melee styles whose
##               own lunge/swing IS the animation)
##
## Slot order is Weapon.gd's WEAPON order (see _held_style_index there):
## shotgun, rocket, grenade, spear, then the rock TOOL, mine,
## jackhammer, railgun, pistol, baseball bat, circular saw, shovel.

const ROCKET_LAUNCHER_TEX := preload(
		"res://assets/weapons/rocket_launcher.png")
const SHOTGUN_TEX := preload("res://assets/weapons/shotgun.png")
## Issue #719 (roadmap part 4a): the grenade and the mine — the first
## THROWN & PLACED weapons migrated to the cartoon art style. The same
## textures serve both sides: the HELD weapon in hands (STYLES below)
## and the rigid body in flight / at rest (PROJECTILE_SPRITES, consumed
## by ProjectileBody).
const GRENADE_TEX := preload("res://assets/weapons/grenade.png")
const MINE_TEX := preload("res://assets/weapons/mine.png")

## Issue #559: default distance from the body CENTRE along the aim axis
## — the 64 px reference body's EDGE (32 px), outside the modular
## character's face zone, so the weapon anchor never sits over a facial
## feature. Plain rectangle styles use exactly this; a textured style
## may carry its own `anchor`.
const DEFAULT_ANCHOR := 32.0
## Issue #680: default "held at the waist" tuning for textured styles —
## the fraction of the anchor's lift kept (the rest is damped toward the
## body's vertical middle) and the fixed drop below the mid line along
## the wielder's stance-gravity axis. The rework of 2026-11-24 (owner:
## "move weapon a little lower") tightened both from the 2026-11-23
## values (0.4 / 6) for the rocket launcher's own entry below.
const DEFAULT_LIFT_KEEP := 0.3
const DEFAULT_DROP := 9.0
## Issue #680 (part 3): default recoil kick-back in px along the aim
## axis — the small jolt every plain rectangle weapon takes on a
## committed shot. Textured/heavy weapons override it upward; the melee
## styles (whose lunge or swing is already the animation) carry 0.
const DEFAULT_RECOIL := 5.0

const STYLES: Array = [
	{# 0 shotgun — #680 part 2: the second cartoon weapon, proving the
	 # system: its own sprite, its own (shorter, slightly higher) hold.
	 # Part 3: a solid pump-gun kick.
		"size": Vector2(40, 16), "color": Color(0.95, 0.85, 0.3, 1),
		"texture": SHOTGUN_TEX,
		"anchor": 30.0, "lift_keep": 0.35, "drop": 8.0, "recoil": 9.0},
	{# 1 rocket launcher — the part 1 prototype. 2026-11-24 rework
	 # ("a little lower"): lift_keep 0.4 -> 0.3, drop 6 -> 9. Part 3:
	 # the heaviest kick of the arsenal — a full tube launch slams the
	 # wielder's arms back.
		"size": Vector2(52, 20), "color": Color(0.9, 0.35, 0.15, 1),
		"texture": ROCKET_LAUNCHER_TEX,
		"anchor": 32.0, "lift_keep": 0.3, "drop": 9.0, "recoil": 12.0},
	{# 2 grenade — issue #719 (roadmap part 4a): the round pineapple
	 # bomb with the steel cap and pin. A small lobbed weapon rides the
	 # same waist hold as the guns; the throw itself kicks the arm back
	 # slightly (recoil 6).
		"size": Vector2(16, 16), "color": Color(0.3, 0.7, 0.3, 1),
		"texture": GRENADE_TEX,
		"anchor": 30.0, "lift_keep": 0.3, "drop": 8.0, "recoil": 6.0},
	{# 3 spear — melee: the thrust lunge is the animation, no recoil.
		"size": Vector2(40, 4), "color": Color(0.8, 0.8, 0.9, 1),
		"recoil": 0.0},
	{"size": Vector2(14, 14), "color": Color(0.55, 0.5, 0.45, 1)},  # rock (tool)
	{# 5 mine — issue #719 (roadmap part 4a): the naval contact mine —
	 # dark navy hull with a stud ring that reads at ANY rotation (the
	 # placed body rests at arbitrary angles). The dormant mine stays
	 # stealthy (#717): dark fills only — the armed fuse blink tints the
	 # whole sprite red through modulate in ProjectileBody.
		"size": Vector2(18, 18), "color": Color(0.22, 0.24, 0.3, 1),
		"texture": MINE_TEX,
		"anchor": 30.0, "lift_keep": 0.3, "drop": 8.0, "recoil": 6.0},
	{# 6 jackhammer — the drill shake is the animation, no recoil.
		"size": Vector2(10, 18), "color": Color(0.85, 0.85, 0.95, 1),
		"recoil": 0.0},  # jackhammer (#307)
	{# 7 railgun — part 3: a heavy hitscan slam, second only to the
	 # rocket launcher.
		"size": Vector2(46, 4), "color": Color(0.55, 0.85, 1.0, 1),
		"recoil": 11.0},  # railgun (#359)
	{"size": Vector2(18, 6), "color": Color(0.5, 0.55, 0.6, 1),   # pistol (#526)
		"recoil": 4.0},
	{# 9 baseball bat — melee: the swing is the animation, no recoil.
		"size": Vector2(30, 8), "color": Color(0.85, 0.6, 0.3, 1),
		"recoil": 0.0},  # baseball bat (#527)
	{"size": Vector2(16, 16), "color": Color(0.75, 0.78, 0.85, 1)},  # circular saw (#570)
	{# 11 entrenching shovel — melee: the dig swing is the animation.
		"size": Vector2(22, 8), "color": Color(0.55, 0.42, 0.28, 1),
		"recoil": 0.0},  # entrenching shovel (#656)
]


## The style entry for a HELD_STYLES index (clamped: a bad index falls
## back to the nearest real entry, never a crash).
static func style(idx: int) -> Dictionary:
	return STYLES[clampi(idx, 0, STYLES.size() - 1)]


## True while the entry renders through its Sprite2D (has a texture).
static func textured(idx: int) -> bool:
	return style(idx).has("texture")


## Per-weapon anchor along the aim axis (entry override or the #559
## default shared by the plain rectangle weapons).
static func anchor(idx: int) -> float:
	var s := style(idx)
	return s.get("anchor", DEFAULT_ANCHOR) as float


## Per-weapon lift damping for textured styles (entry override or the
## registry default).
static func lift_keep(idx: int) -> float:
	var s := style(idx)
	return s.get("lift_keep", DEFAULT_LIFT_KEEP) as float


## Per-weapon fixed drop along the stance-gravity axis for textured
## styles (entry override or the registry default).
static func drop(idx: int) -> float:
	var s := style(idx)
	return s.get("drop", DEFAULT_DROP) as float


## Issue #680 (part 3): per-weapon recoil kick-back in px along the aim
## axis on a committed shot (entry override or the registry default;
## the melee styles carry an explicit 0).
static func recoil(idx: int) -> float:
	var s := style(idx)
	return s.get("recoil", DEFAULT_RECOIL) as float


## Issue #719 (roadmap part 4a): the THROWN and PLACED sides of the two
## lobbed weapons — the sprite and drawn size their RIGID BODIES render
## in flight and at rest (ProjectileBody's grenade/mine kinds), keyed
## by kind name, so the in-world art comes from this registry too
## instead of a second table. The drawn sizes sit a touch above the
## 14 px physics rectangles so the silhouettes stay readable at
## gameplay scale; hitboxes and every gameplay number are frozen by
## the #680 constraints.
const PROJECTILE_SPRITES := {
	"grenade": {"texture": GRENADE_TEX, "size": Vector2(16, 16)},
	"mine": {"texture": MINE_TEX, "size": Vector2(18, 18)},
}


## The projectile-sprite entry for a kind name ({} when the kind keeps
## its code-drawn visual — the saw, the rock, the rocket body).
static func projectile_sprite(kind_name: String) -> Dictionary:
	return PROJECTILE_SPRITES.get(kind_name, {}) as Dictionary
