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
##   flash      — per-weapon MUZZLE FLASH data (issue #720, part 4b):
##               {"size": px, optional "outer"/"inner"/"core" Color
##               overrides}. Styles without it keep the #715 default
##               burst (DEFAULT_FLASH_SIZE and the warm starburst
##               palette); Weapon._muzzle_flash feeds the whole dict
##               to MuzzleFlash.pop.
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
## Issue #720 (roadmap part 4b): the pistol and the railgun — the
## remaining FIREARMS migrated to the cartoon art style. The pistol is
## the compact hand gun (small slide/grip sprite, light kick, a small
## hot flash); the railgun is the heavy twin-rail cannon (long low
## sprite, the heaviest kick after the rocket launcher, a big icy
## flash in the beam's own cyan family).
const PISTOL_TEX := preload("res://assets/weapons/pistol.png")
const RAILGUN_TEX := preload("res://assets/weapons/railgun.png")
## Issue #721 (roadmap part 4c): the MELEE weapons — the spear, the
## baseball bat and the entrenching shovel — join the cartoon style.
## Melee holds stay their own animation (the thrust lunge, the swing
## and the dig carry recoil 0), and each "flash" entry is purely a
## HIT-STAR palette (3c CartoonBlast.pop_hit) — melee has no muzzle,
## so nothing pops a muzzle burst; the strike star reads in the
## weapon's own family exactly like the railgun's #720 world hit.
const SPEAR_TEX := preload("res://assets/weapons/spear.png")
const BASEBALL_BAT_TEX := preload("res://assets/weapons/baseball_bat.png")
const SHOVEL_TEX := preload("res://assets/weapons/entrenching_shovel.png")

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
## Issue #720 (roadmap part 4b): the default muzzle-flash data every
## style without its own "flash" entry resolves to — the #715 burst
## exactly as it was (22 px starburst, warm orange/yellow palette).
const DEFAULT_FLASH := {"size": 22.0}

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
	{# 3 spear — issue #721 (roadmap part 4c): the cartoon spear —
	 # slender warm-wood shaft, leather grip wrap, steel pommel and a
	 # light-steel leaf head. MELEE: the thrust lunge is the animation,
	 # no recoil; the drawn height grows 4 -> 8 for the readable
	 # shaft+head silhouette, while size.x stays EXACTLY 40 — the sweep
	 # hitbox reads HELD_STYLES[3]["size"].x (Weapon._spear_sweep_hit),
	 # so the balance is frozen. No anchor override either: the hitbox
	 # rides the SPEAR_TIP_BASE constant tied to the #559 default.
		"size": Vector2(40, 8), "color": Color(0.8, 0.8, 0.9, 1),
		"texture": SPEAR_TEX,
		"lift_keep": 0.3, "drop": 7.0, "recoil": 0.0,
		"flash": {
			"inner": Color(0.55, 0.68, 0.95, 1),
			"core": Color(0.93, 0.97, 1.0, 1),
		}},
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
	{# 7 railgun — issue #720 (roadmap part 4b): the twin-rail cartoon
	 # cannon — steel rails with the dark energy channel, yellow coil
	 # rings and the cyan core/muzzle glow. The long low body rides the
	 # rocket launcher's hold; the recoil stays the part-3 heavy slam
	 # (11 px) and the flash is a BIG icy burst in the beam's colors
	 # (the #715 starburst, re-paletted to cyan/white through the
	 # registry's per-weapon flash data).
		"size": Vector2(48, 16), "color": Color(0.55, 0.85, 1.0, 1),
		"texture": RAILGUN_TEX,
		"anchor": 32.0, "lift_keep": 0.3, "drop": 9.0, "recoil": 11.0,
		"flash": {
			"size": 30.0,
			"outer": Color(0.30, 0.62, 1.0, 1),
			"inner": Color(0.55, 0.78, 1.0, 1),
			"core": Color(0.95, 0.98, 1.0, 1),
		}},
	{# 8 pistol — issue #720 (roadmap part 4b): the compact hand gun —
	 # dark slide, warm wood grip, yellow sight/trigger. The lightest
	 # kick of the firearms (4 px, the part-3 baseline) and a SMALL hot
	 # flash (the #715 palette, just a tighter burst).
		"size": Vector2(24, 16), "color": Color(0.5, 0.55, 0.6, 1),
		"texture": PISTOL_TEX,
		"anchor": 30.0, "lift_keep": 0.35, "drop": 8.0, "recoil": 4.0,
		"flash": {"size": 16.0}},
	{# 9 baseball bat — issue #721 (roadmap part 4c): the cartoon bat —
	 # honey wood with a top highlight following the taper, a dark
	 # taped grip and a round knob, fat barrel toward the strike.
	 # MELEE: the swing lunge is the animation, no recoil; the swing
	 # corridor is the fixed BAT_RANGE constant, so the size change
	 # (30x8 -> 32x10) is visual only.
		"size": Vector2(32, 10), "color": Color(0.85, 0.6, 0.3, 1),
		"texture": BASEBALL_BAT_TEX,
		"anchor": 30.0, "lift_keep": 0.3, "drop": 8.0, "recoil": 0.0,
		"flash": {
			"inner": Color(1.0, 0.55, 0.15, 1),
			"core": Color(1.0, 0.9, 0.7, 1),
		}},
	{"size": Vector2(16, 16), "color": Color(0.75, 0.78, 0.85, 1)},  # circular saw (#570)
	{# 11 entrenching shovel — issue #721 (roadmap part 4c): the
	 # cartoon entrenching spade — warm-wood T-grip, steel tube shaft
	 # and the wide stamped blade with the center rib. MELEE: the dig
	 # swing is the animation, no recoil; the corridor is the fixed
	 # SHOVEL_RANGE constant, so the size change (22x8 -> 26x12) is
	 # visual only. The deepest drop of the three melee weapons — a
	 # digging tool rides lowest on the body.
		"size": Vector2(26, 12), "color": Color(0.55, 0.42, 0.28, 1),
		"texture": SHOVEL_TEX,
		"anchor": 30.0, "lift_keep": 0.3, "drop": 10.0, "recoil": 0.0,
		"flash": {
			"inner": Color(0.72, 0.45, 0.2, 1),
			"core": Color(0.95, 0.82, 0.6, 1),
		}},
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


## Issue #720 (roadmap part 4b): per-weapon MUZZLE FLASH data (entry
## override or the #715 default burst). The dict is fed straight into
## MuzzleFlash.pop — "size" plus optional "outer"/"inner"/"core"
## palette colors.
static func flash_style(idx: int) -> Dictionary:
	return style(idx).get("flash", DEFAULT_FLASH) as Dictionary


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
