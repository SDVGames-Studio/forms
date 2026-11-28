extends Node2D
## Weapon handling for every team member (issue #3, reworked in #49).
##
## Five standard weapons, selectable through the WeaponInventory HUD
## (keys 1–4 and 9, HUD on the right side of the screen). The controlled
## member fires with the "shoot" action (F). Each weapon has different
## physics:
##  1 Shotgun       — spread of 5 fast pellets, mid range (450 px,
##                    issue #430), low damage each
##  2 Rocket        — fast rocket that keeps its launch speed but arcs
##                    under the level's gravity (issue #245), big blast
##  3 Grenade       — lobbed arc with gravity, explodes on fuse or impact
##  4 Melee spear   — thrust that damages along the whole spearhead
##                     trajectory (out and back), not one instant check.
##                     #721 rework (owner 2026-11-28): charged like the
##                     rocket — hold F to pick the strike power; the
##                     spear pulls BACK before the lunge and the thrust
##                     reach scales with the power (damage frozen)
##  5 Mine (key 9)  — thrown like a grenade, then lies dormant until a
##                    character steps near it — 2-second fuse, boom
##                    (issue #246); it persists across turns
##  6 Jackhammer (key 0) — hold F to charge, release to drill: the wielder
##                    is pushed along the AIM direction for 1–3 s
##                    (scaled by the charge), carving destructible ground
##                    ahead. A figure the drill meets is PUSHED along the
##                    aim and ground down for 10 damage per second while
##                    the contact lasts (issue #307; issue #316: any aim
##                    direction, max 3 s, steerable mid-drill with the aim
##                    keys, no cancel; issue #363: push + grind, no burst)
##  7 Railgun (key R) — hold F to charge, release to fire an INSTANT
##                    hitscan beam (60 dmg on a tap, up to 150 at full
##                    charge when the line turns white; a tap keeps the
##                    iridescent rainbow). Infinite range, no falloff;
##                    the line lingers 1 s. Charging slows the wielder
##                    and shakes the sight. ONE use per team per round
##                    (issue #359)
##  8 Pistol (key P)  — three shots per turn: ONE bullet straight along
##                    the aim (no spread — more accurate than the
##                    shotgun's 5-pellet cone), less damage per shot
##                    than the shotgun volley (issue #526)
##  9 Baseball bat (key B) — hold F to charge, release to swing
##                    (issue #527 rework: the swing power is chosen
##                    like a rocket launch) — a melee swing along the
##                    aim: the hit not only damages the figure it
##                    reaches, it LAUNCHES them like a projectile
##                    (issue #549) — one initial impulse along the shot
##                    direction with a guaranteed lift, after which the
##                    level's gravity bends the flight into an arc until
##                    the victim lands. #721 rework (owner 2026-11-28):
##                    the bat RESTS ON THE OPPOSITE SIDE of the wielder
##                    (back carry) and the swing is a WIND-UP FIRST —
##                    the bat pulls back behind the body (amplitude and
##                    duration scale with the strike power) and only the
##                    forward sweep's peak lands the hit
## 10 Circular saw (key C) — issue #570: thrown like a mine (hold F to
##                    charge the lob). On landing the blade SPINS for a
##                    few seconds, SUCKING IN every nearby figure (a
##                    steady pull toward the blade, either team) and
##                    grinding the ones it reaches for damage per
##                    second — then it stops and disappears.
## 11 Entrenching shovel (key E) — issue #656: a MELEE weapon with LESS
##                    range than the spear. Every swing damages the
##                    figures the short swing reaches for 20% of the
##                    spear's damage AND carves an upright ellipse out
##                    of destructible ground in front of the wielder
##                    (one diameter = the figure's height, the other =
##                    half its width). Five swings per turn, ENDLESS
##                    uses (never on the team budget, like the spear).
##                    #721 rework (owner 2026-11-28): charged too —
##                    hold F to pick the swing power; the swing winds up
##                    first (power-scaled) and the strike's carve scale
##                    grows with the power (a stronger swing re-carves
##                    the same bore deeper, damage frozen)
## Held-weapon visuals are data-driven: plain rectangles for the tools
## and melee shapes, hand-drawn cartoon sprites for the redesigned
## weapons (registry: scripts/WeaponVisuals.gd, issue #680).

const ProjectileScript := preload("res://scripts/Projectile.gd")
## Issue #114: rockets and grenades spawn as real rigid bodies.
const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")
## Issue #549: the bat's ballistic knockback integrates the figures'
## shared gravity constant — figures are NOT rigid bodies, their own
## scripts apply Stats.GRAVITY along the level's gravity field, so the
## bat's flight must integrate the very same gravity.
const Stats := preload("res://scripts/CharacterStats.gd")

## Owner task 2026-11-11 (godot-sound-work skill): the shot sound —
## preloaded once, never loaded per shot at runtime.
const SHOT_SOUND := preload("res://assets/audio/weapons/shot.wav")
## Issue #495: the jackhammer's ground-drilling loop — the drill IS the
## weapon's sound: played for the drill's whole run (started by
## _start_jackhammer, stopped by _end_jackhammer). The 0.8 s asset is
## looped at runtime (see _ready) so it covers the 1–3 s drill.
const JACKHAMMER_SOUND := preload("res://assets/audio/weapons/jackhammer.wav")
## One AudioStreamPlayer per sound category, on the SFX bus.
var _shot_player: AudioStreamPlayer
## Issue #495: the jackhammer drill loop player (weapons/tools category,
## SFX bus) — the firing shot bang is skipped for the jackhammer in _fire.
var _drill_player: AudioStreamPlayer

const COOLDOWN := 0.3

## Issue #101: shots each weapon allows during ONE turn (index = weapon:
## shotgun 2, rocket 1, grenade 1, spear 2, mine 1, jackhammer 1, railgun 1,
## pistol 3, baseball bat 1 — issues #526, #527; entrenching shovel 5,
## issue #656) and the 3-second delay after every shot during which the
## character cannot shoot.
const SHOTS_PER_TURN: Array = [2, 1, 1, 2, 1, 1, 1, 3, 1, 1, 5]
const SHOT_DELAY := 3.0

const PELLET_SPEED := 900.0
## Issue #430: pellet flight time raised 0.35 s -> 0.5 s, so a pellet
## now covers 900 px/s * 0.5 s = 450 px (was 315) — the whole Npc.gd
## shotgun band (issue #66 said 360 while pellets only flew 315) and
## beyond, still the shortest ranged shot after the melee spear.
const PELLET_LIFETIME := 0.5
const PELLET_DAMAGE := 6
const ROCKET_SPEED := 700.0
const ROCKET_DAMAGE := 35
const ROCKET_BLAST := 90.0
const ROCKET_LIFETIME := 3.0
const GRENADE_SPEED := 550.0
const GRENADE_DAMAGE := 40
const GRENADE_BLAST := 100.0
## Issue #117: the grenade fuse is 3 seconds.
const GRENADE_FUSE := 3.0
const SPEAR_RANGE := 70.0
const SPEAR_DAMAGE := 25
## Issue #246: the mine — thrown with the grenade's arc, explodes with a
## grenade-sized blast once a character steps on it (see ProjectileBody).
const MINE_SPEED := 480.0
const MINE_DAMAGE := 40
const MINE_BLAST := 100.0
const MINE_MASS := 0.8
## Issue #114: charged shots. Holding F charges a rocket/grenade launch —
## the longer the hold, the faster it flies (from MIN_SHOT_POWER up to the
## full base speed after MAX_CHARGE_TIME seconds).
const MIN_SHOT_POWER := 0.4
const MAX_CHARGE_TIME := 1.5
const ROCKET_MASS := 1.0
const GRENADE_MASS := 0.6
## Issue #722 rework (owner 2026-11-28): the POWERING animation — the
## jackhammer and the circular saw REV in the wielder's hands while F
## is held (the charge builds the throw/drill power, and the animation
## must show it): a tremble whose amplitude grows with the charge
## fraction, the jackhammer's bit chattering along the aim (the
## pneumatic pulse) and the saw blade juddering in angle as its motor
## spins it up — the #721 wind-up's power scaling mirrored on the
## CHARGE side, before the release. The jackhammer's full level equals
## the running drill's own shake, so the rev eases straight into the
## drilling tremble at the release. Purely visual: no gameplay
## calculation reads any of it, and every frozen #680 number stays
## untouched (see powering_jitter / powering_wobble).
const JACKHAMMER_REV_JITTER := 2.0
const JACKHAMMER_REV_CHATTER := 1.6
const JACKHAMMER_REV_HZ := 11.0
const SAW_REV_JITTER := 1.5
const SAW_REV_HZ := 13.0
const SAW_REV_WOBBLE := 0.12
## Issue #227: the Rock tool projectile is a touch heavier than a grenade.
const ROCK_MASS := 0.8
## Issue #307: the jackhammer — hold F to charge (the shared charge
## meter), release to drill. Issue #316 rework: the wielder is pushed
## along the AIM direction (any direction the character directs, not
## just down) for MIN..MAX seconds scaled by the charge, carving
## destructible ground ahead in a tunnel of JACKHAMMER_RADIUS.
## The drill direction is re-sampled from the LIVE aim at every tick:
## the aim keys steer a running drill (it cannot be cancelled — it runs
## its full time or stalls), and on radial arenas the aim frame rides
## the level gravity, so the tunnel still bends around the core.
## Issue #363 rework: a character the drill MEETS is pushed along the
## aim direction at the drill speed and ground down at
## JACKHAMMER_PUSH_DPS per second while the contact lasts.
const JACKHAMMER_MIN_TIME := 1.0
const JACKHAMMER_MAX_TIME := 3.0
const JACKHAMMER_SPEED := 130.0
## Issue #307 rework: the tunnel radius must EXCEED the figure's
## half-width — every figure is a capsule of radius 24 (Player scenes,
## Npc.gd), 48 px wide. The original 16 px tunnel (32 px wide) was
## NARROWER than the driller: the wielder wedged into their own fresh
## tunnel, made no progress and the stall timer killed the drill almost
## immediately — no real tunnel, no travelling, no damage. 32 px leaves
## 8 px of clearance on each side of the body.
const JACKHAMMER_RADIUS := 32.0
## Carve a fresh tunnel circle only after the wielder advanced this many
## pixels (bounds the recursive chunk splitting) — and a drill that made
## no progress for JACKHAMMER_STALL_TIME seconds hit indestructible
## ground: it grinds to a halt early.
const JACKHAMMER_CARVE_STEP := 6.0
const JACKHAMMER_STALL_TIME := 0.3
## Issue #363 rework: the drill no longer burst-damages a met figure —
## it PUSHES them along the aim direction at the wielder's drill speed
## (JACKHAMMER_SPEED) and grinds them for this many damage per second
## for as long as the contact lasts (a full 3 s charge grinds ~30 —
## the old one-shot value — but streamed tick by tick).
const JACKHAMMER_PUSH_DPS := 10.0
## Issue #316 rework: how far AHEAD of the wielder the drill's damage
## corridor reaches. Two figure capsules (radius 24) TOUCH at 48 px
## centre-to-centre — the old forward window (`along < 40`) ended
## BEFORE body contact, so a drill aimed at an adjacent enemy (any aim
## that is not into the ground) ground against their body and dealt NO
## damage. The reach covers the farthest touching pair (pole to pole,
## 32 + 32 = 64) so every figure the drill presses against is hit.
const JACKHAMMER_REACH := 64.0
## Issue #359: the railgun — an instant hitscan beam along the aim.
## Damage scales with the held-F charge: 60 on an instant tap, up to 150
## at full charge, while the beam's iridescent rainbow lerps to pure
## white. Infinite range, no damage falloff; the thick line lingers one
## second, then disappears. ONE use per team per round (the team budget
## lives in WeaponInventory). Charging slows the wielder to half speed
## and shakes the sight (Player._physics_process reads the accessors
## below).
const RAILGUN_MIN_DAMAGE := 60
const RAILGUN_MAX_DAMAGE := 150
## The beam lingers this long before it disappears (issue text: 1 s).
const RAILGUN_BEAM_TIME := 1.0
const RAILGUN_BEAM_WIDTH := 8.0
## Walk-speed fraction while charging the railgun (issue #359).
const RAILGUN_CHARGE_SLOWDOWN := 0.5
## Sight wobble per physics tick while charging, in radians (issue #359).
const RAILGUN_SIGHT_SHAKE := 0.035
## "Infinite" range — far beyond any level, but keeps the ray finite.
const RAILGUN_RANGE := 20000.0
## Issue #526: the pistol — three single-bullet shots per turn, each
## dead straight along the aim (NO spread — more accurate than the
## shotgun's 5-pellet ±8° cone) and cheaper in damage: 10 per bullet vs
## the shotgun's 30-damage volley (5 × PELLET_DAMAGE). The bullet flies
## at the pellet speed but outlives it: 900 px/s × 0.6 s = 540 px.
const PISTOL_SPEED := 900.0
const PISTOL_LIFETIME := 0.6
const PISTOL_DAMAGE := 10
## Issue #527: the baseball bat — a MELEE swing along the aim (a corridor
## check in front of the wielder, like the spear's thrust). The hit not
## only damages the figure it reaches, it LAUNCHES them (issue #549):
## ONE initial impulse along the shot direction at BAT_KNOCKBACK_SPEED,
## after which they fly like a projectile — the level's gravity bends
## the flight into an arc until they land (the velocity write + body
## shove the jackhammer drill proved in #363 — an idle figure's physics
## clamp eats a one-shot tangential velocity write, so the flight ticks
## like the drill does, integrating gravity every tick). Damage sits
## between the spear (25) and the rocket (35).
const BAT_RANGE := 90.0
const BAT_DAMAGE := 30
## How wide the swing's corridor is sideways of the aim axis — a figure
## capsule is 48 px wide, so 24 catches every figure whose centre is up
## to half a body off the aim line.
const BAT_LATERAL := 24.0
## Issue #549: the LAUNCH speed — the magnitude of the initial impulse
## along the shot direction (scaled by the #527 charge).
const BAT_KNOCKBACK_SPEED := 700.0
## Issue #549: a flat swing would pin the victim to the floor, so every
## launch carries at least this fraction of the launch speed as LIFT
## against gravity — the victim always becomes airborne and gravity
## gets to bend a real arc (a Worms-style pop-up off the bat).
const BAT_MIN_LIFT := 0.4
## Issue #549: safety cap on the ballistic flight — the flight ends
## when every victim lands, but a figure knocked into a bottomless pit
## never would, so the flight force-ends after this many seconds and
## the turn-effect gate releases (TurnController's own 30 s effects
## safety timer backs this up).
const BAT_FLIGHT_CAP := 5.0
## Issue #570: the circular saw — thrown with the mine's lobbed arc and
## aiming. It never explodes: on landing the blade spins (all spin
## behaviour constants live in ProjectileBody next to the mine's, see
## Kind.SAW), sucking in nearby figures and grinding the contact ones
## for damage per second, then it stops and disappears. One saw per turn,
## the standard 5 uses per team per round (WeaponInventory).
const SAW_SPEED := 480.0
const SAW_MASS := 0.8
## Issue #656: the entrenching shovel — a MELEE weapon with LESS range
## than the spear (55 < 70): a short swing that damages every figure it
## reaches for 20% of the spear's shot damage (5 of 25) and digs an
## upright ellipse out of destructible ground in front of the wielder.
## Five swings per turn, ENDLESS uses (WeaponInventory never budgets it,
## like the spear).
const SHOVEL_RANGE := 55.0
const SHOVEL_DAMAGE := 5
## The dig ellipse's diameters: the figure's HEIGHT and the figure's
## FULL WIDTH (the 64 px reference body, CharacterStats.BODY_SIZE).
## The long axis rides the character's VERTICAL (the gravity frame's
## up, _frame_up) wherever the aim points — the dig stays upright in
## the wielder's own frame. Rework #2: the first delivery took the
## issue text's "half of character's width" (32) as the horizontal
## diameter, but the figure's collider is a 48 px wide capsule — that
## hole could NEVER admit the body, so the dug "tunnel" was a notch
## the character just bumped into (the owner's screenshot). The
## horizontal diameter is the FULL body width: the capsule fits with
## 8 px of clearance per side and the figure walks straight in.
const SHOVEL_DIG_HEIGHT := 64.0
const SHOVEL_DIG_WIDTH := 64.0
## Rework #3 (the owner's screenshot): how far ahead of the body
## CENTRE the dig ellipse sits. The rework-#2 value (64: the
## ellipse's near tip at the 64 px reference body's edge) still left
## the figure OUTSIDE the hole — an intact lip of ground stood ahead
## of the 48 px collider capsule, and even past that lip the bore's
## curved mouth is a head-height BROW the capsule can never climb
## over: a 64 px tall bore only admits the 57.6 px tall capsule while
## the bore's centre stays within sqrt(32^2 - 28.8^2) = ~13.9 px of
## the body centre. So the dig must open ON the wielder: the ellipse
## rides a touch AHEAD of the body centre, carving the ground from
## around the figure itself — the capsule sits inside its own fresh
## bore (3 px of margin) and walks straight through the tunnel.
const SHOVEL_DIG_OFFSET := 12.0
## Issue #656 rework: the dig spot is ANCHORED — the first swing of a
## dig fixes the ellipse (centre + upright) in WORLD space, and while
## the wielder stays within this distance of that stance every further
## swing re-carves the SAME ellipse. The first delivery re-centred the
## dig on the live aim every swing, so re-aiming between the five
## swings dragged the hole into a ragged trench — the owner's rework:
## the removed ground must remain an ellipse. Rework #3: the threshold
## is one STEP of the dig chain — the figure walks ~this far into the
## bore and the next swing opens the next ellipse (overlapping ~64-wide
## bores 12 px apart leave a >= 58 px pinch the capsule fits through),
## so the tunnel extends instead of dead-ending; a smaller stance
## jitter still keeps the one anchored ellipse.
const SHOVEL_DIG_REANCHOR := 12.0
## Issue #721 rework (owner 2026-11-28): MELEE STRIKE POWER + WIND-UP.
## The spear and the shovel join the charged weapons (hold F, release)
## and every melee strike now WINDS UP before it lands: the weapon
## pulls back behind the wielder and then lunges/swings forward. The
## wind-up AMPLITUDE and DURATION scale with the strike power —
## SPEAR_PULLBACK / BAT_WINDUP / SHOVEL_WINDUP are the per-weapon
## pull-back amplitudes at FULL power, MELEE_WINDUP_MIN..+RANGE the
## wind-up duration window from a tap to the full hold. Damage stays
## frozen everywhere: the spear's power scales its thrust REACH, the
## shovel's scales the dig carve, the bat keeps its knockback scaling.
const SPEAR_PULLBACK := 22.0
const BAT_WINDUP := 30.0
const SHOVEL_WINDUP := 24.0
const MELEE_WINDUP_MIN := 0.08
const MELEE_WINDUP_RANGE := 0.14
## Issue #721 rework: the strike sweep's out/return phase lengths (the
## historic #257/#527/#656 shapes — fast strike, slower return).
const BAT_SWING_OUT := 0.1
const BAT_SWING_BACK := 0.3
const SHOVEL_SWING_OUT := 0.1
const SHOVEL_SWING_BACK := 0.3

var _facing := 1.0
var _cooldown_left := 0.0
## Issue #101: shots already made this turn by this member, per weapon
## (issue #116: the quota is per weapon so switching after a shot keeps
## the newly selected weapon's own quota).
var _shots_used := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

## Issue #101: seconds left before the character may shoot again.
var _shot_delay_left := 0.0
## Issue #114: charge state for the rocket/grenade charged launch.
var _charging := false
var _charge_time := 0.0
var _charge_bar: ColorRect
## Issue #722 rework (owner 2026-11-28): the POWERING rev clock —
## advances only while the jackhammer or the circular saw is charging
## (the visual block's powering animation reads it: the bit chatter and
## the blade judder oscillate on this clock), reset whenever the rev
## stops, so every charge starts its rev from phase zero.
var _rev_t := 0.0
## Issue #133 (rework): the melee spear uses the HELD spear itself — no
## separate projectile rectangle is spawned. _thrust_t animates a quick
## forward lunge along the aim axis followed by a slow return to the hand.
var _thrust_t := -1.0
## Issue #257: bodies already damaged by the CURRENT thrust — each target
## on the spearhead's path takes the spear hit at most once per thrust.
var _thrust_hit: Array = []
## Issue #721 rework (owner 2026-11-28): the charged strike power
## (0..1) of the melee strike currently animating — set by the release
## (or the NPC's default full power), read by the wind-up amplitude,
## the spear's thrust reach and the shovel's dig carve.
var _melee_power := 1.0
## Issue #721 rework: this tick's melee offsets along the aim axis —
## the spear's thrust and the bat/shovel swing, computed by _tick_melee
## (the strike state machine) and mirrored onto the held visual below.
## Gameplay timing, not just visuals: the values advance for EVERY
## wielder, the visual block only reads them.
var _melee_thrust := 0.0
var _melee_swing := 0.0
var _melee_shovel_swing := 0.0
## Issue #527 rework: the bat is a CHARGED weapon like the rocket
## (issue #114) — hold F, release to swing. The charge picks the swing
## power: the launch speed scales from 40% (a tap) to the full
## BAT_KNOCKBACK_SPEED at the MAX_CHARGE_TIME hold, so the player
## chooses how far the victim flies (damage stays fixed).
var _bat_push_speed := BAT_KNOCKBACK_SPEED

## Issue #527: the baseball bat swing — a quick lunge of the held bat
## along the aim axis (visual only; the hit itself is instant, see
## _swing_bat), plus the knockback state. Issue #549: every hit figure
## flies BALLISTICALLY — _bat_push holds one flight record per victim
## ({body, vel, air}: the figure, its CURRENT flight velocity, and
## whether it has left the floor at least once — only an airborne body
## can "land"), _bat_push_left is the BAT_FLIGHT_CAP countdown, and
## _bat_effect is the turn-effect gate node that keeps the post-shot
## handover waiting while they fly (ticked from _physics_process like
## the drill).
var _bat_swing_t := -1.0
var _bat_push: Array = []
var _bat_push_dir := Vector2.ZERO
var _bat_push_left := 0.0
var _bat_effect: Node = null
## Issue #721 rework: false while a running bat swing still owes its
## corridor strike — the wind-up plays first and the hit lands at the
## forward sweep's peak (see the swing tick in _physics_process).
var _bat_strike_done := true
## Issue #656: the shovel swing timer — the bat's quick swipe shape on
## the shovel's own (shorter) reach; the hit itself is instant, see
## _swing_shovel.
var _shovel_swing_t := -1.0
## Issue #721 rework: same as the bat — false while the shovel's
## wind-up still owes the corridor hit + dig (they land at the forward
## sweep's peak, see _shovel_strike).
var _shovel_strike_done := true
## Issue #656 rework: the anchored dig of the current stance — the
## ellipse centre/up fixed in world space by the first swing there,
## the wielder's position when it was fixed, and whether that exact
## ellipse has been carved already (re-carving an empty hole is a
## no-op, so later swings cost nothing). See SHOVEL_DIG_REANCHOR.
var _shovel_dig_anchor := Vector2.INF
var _shovel_dig_up := Vector2.ZERO
var _shovel_dig_body := Vector2.INF
## Issue #721 rework: the power scale already carved at the current
## dig anchor (-1 = nothing yet) — a STRONGER swing re-carves the bore
## deeper, an equal or weaker one is the historic no-op.
var _shovel_dig_power := -1.0
## Issue #307: jackhammer drill state — seconds left, drill direction
## (re-sampled from the live aim every tick so the aim keys steer a
## running drill, #316), the per-body accrued grind damage of THIS
## drill (#363), the last carve centre, the stall probe position/timer,
## and the turn-effect gate node that keeps the post-shot handover
## waiting while the drill runs.
var _drill_left := 0.0
var _drill_dir := Vector2.DOWN
var _drill_push: Dictionary = {}
var _drill_carve_at := Vector2.INF
var _drill_last_pos := Vector2.ZERO
var _drill_stall := 0.0
var _drill_effect: Node = null
## Issue #722 (part 4d): the drill's 3c feedback-star cooldowns — the
## steel-spark stars are throttled: the grind chunks land every ~0.1 s
## (PUSH_DPS 10) and the bore circles every ~0.05 s (CARVE_STEP 6 at
## SPEED 130), a star each would strobe (the Character's own damage
## star runs a similar 380 ms limit, #718).
var _drill_dust_cd := 0.0
var _drill_grind_cd := 0.0
## Issue #722 (part 4d): seconds between the drill's feedback stars.
const DRILL_STAR_INTERVAL := 0.3

## Issue #99: when an NPC fires a grenade, the weapon lobs it ballistically
## at this target (cleared after one shot). Player grenades keep the
## hand-aimed arc.
var npc_target: Node2D = null

## Issue #67: current aim direction of the wielder (view angle applied).
func _aim() -> Vector2:
	var parent := get_parent() as CharacterBody2D
	if parent != null and parent.has_method("aim_dir"):
		# Issue #293: the legacy gravity-sign argument is call compatibility
		# only (aim_dir ignores it) — the authored gravity sign is gone.
		return parent.aim_dir(_facing, 1.0)
	return Vector2(_facing, 0.0)


## Issue #367 (rework): the wielder's facing sign — the night-regime
## vision wedges aim along the same live aim the held weapon shows.
func facing_sign() -> float:
	return _facing

## Issue #277 rework: the "up" of the wielder's current gravity frame —
## lobbed throws arc away from the floor in the same frame the weapon
## aims in.
func _frame_up() -> Vector2:
	var parent := get_parent() as CharacterBody2D
	if parent != null and parent.has_method("current_gravity"):
		var grav: Vector2 = parent.current_gravity()
		if grav.length_squared() > 0.5:
			return -grav
	return Vector2.UP

## Issue #277 rework: launch velocity of a LOBBED throw — straight along
## the aim the weapon INDICATES plus the lob away from the floor. The old
## construction mirrored the speed by the facing and rotated it by the
## aim angle; with the aim pointing left (|angle| > 90°) that rotation
## flipped the whole velocity 180°: the weapon indicated up-left while
## the grenade/mine/rock launched down-right, into the ground beside the
## shooter. Facing right on flat ground reproduces the exact legacy arc
## (speed along the aim, 320·strength lob upward).
static func lobbed_velocity(aim: Vector2, up: Vector2, speed: float,
		strength: float) -> Vector2:
	return aim * speed + up * 320.0 * strength

## Issue #114: the weapon slots fired through the hold-F charge meter —
## pressing shoot starts the charge, releasing it fires with the power
## scaled by the hold time (rocket, grenade, mine, jackhammer, railgun,
## baseball bat — and the armed rock, handled by its own flag at the
## call site). Issue #570 rework (owner, 2026-11-16): the circular saw
## (slot 9) joins them — holding the shot key must change the power of
## the shot. It was missing from the gate, so the saw fired at full
## power on the press instead of charging.
static func is_charged_weapon(slot: int) -> bool:
	# Issue #721 rework (owner 2026-11-28): the spear (3) and the
	# entrenching shovel (10) join the charged set — hold F to pick the
	# strike power (the thrust reach / the dig carve). Only the shotgun
	# and the pistol keep the instant press-fire.
	return slot == 1 or slot == 2 or slot == 3 or slot == 4 or slot == 5 \
			or slot == 6 or slot == 8 or slot == 9 or slot == 10

## Issue #68: visual of the weapon currently held "in hands".
var _held: ColorRect
var _held_style := -1
## Issue #680: the sprite-rendered held weapon (a textured registry
## style — the rocket launcher and the shotgun). One shared node,
## configured per style in _update_held, positioned and rotated by the
## aim in _physics_process just like the rectangle above.
var _held_sprite: Sprite2D
## Issue #680 (part 3): recoil animation clock — < 0 idle, else seconds
## since the committed shot that kicked the held visual back along the
## aim (ticked with the held-weapon visual in _physics_process). The
## kick MAGNITUDE is per-weapon data (WeaponVisuals.recoil).
var _recoil_t := -1.0
## Issue #680 (part 3): how long the recoil takes to ease back to the
## hold position (seconds). Visual only — the kick never touches a
## gameplay number, corridor or hitbox.
const RECOIL_TIME := 0.28
## Issue #716 (roadmap part 3a — idle & aim motion): idle breathing bob
## of the held weapon — amplitude in px along the wielder's
## stance-gravity axis, and its period in seconds. Deliberately subtle:
## the weapon should feel alive between shots, never bouncy.
const IDLE_AMPLITUDE := 1.5
const IDLE_PERIOD := 2.6
## Issue #716: seconds the wielder must stand still (no walk command, no
## re-aim, no busy weapon animation) before the breathing settles in —
## the "settle" of the idle motion: right after a move or a swing the
## weapon tracks the aim exactly, then relaxes into the bob.
const IDLE_SETTLE_DELAY := 1.5
## Issue #716: seconds the bob's amplitude takes to travel 0 -> 1 (or
## back) — the breathing fades in and out, it never pops.
const IDLE_FADE_TIME := 0.8
## Issue #716: follow-through easing rate for the DRAWN weapon angle
## (1/s; time constant ~1/16 s) — a swung aim leaves a slight barrel
## trail that settles behind the swing. The LIVE aim stays
## pixel-accurate: _aim() and every gameplay calculation keep the true
## aim; only the drawn rotation lags.
const AIM_FOLLOW_RATE := 16.0

## Issue #716: idle-motion phase clock — advanced every physics tick
## the held visual runs; the APPLIED amplitude is gated by _idle_amount,
## so the phase never stalls and the bob stays a pure bounded sine (no
## jitter, no accumulated drift).
var _idle_t := 0.0
## Issue #716: eased 0..1 amplitude of the breathing bob — 1 only while
## the wielder stands settled (see IDLE_SETTLE_DELAY), eased back to 0
## the moment they walk, re-aim or run a weapon animation.
var _idle_amount := 0.0
## Issue #716: seconds since the wielder last walked, re-aimed or ran a
## weapon animation — the settle clock the bob fades in on.
var _still_for := 0.0
## Issue #716: the angle the weapon is currently DRAWN at — eases toward
## the live aim angle for the follow-through (snapped on the first tick
## so a freshly held weapon never swings in from angle 0).
var _drawn_aim_angle := NAN
## Issue #716: the TRUE aim angle of the previous tick — a change beyond
## a small epsilon is a re-aim, which resets the idle settle clock.
var _last_aim_angle := NAN

## Issue #354: true while THIS member is the one acting — the active
## member of the currently running turn. Only that figure takes a
## weapon in hands; idle characters (waiting teammates, the enemy team
## between its turns, every figure during the first-team roll and after
## the game ends — TurnController clears active_team/active_member then)
## stand empty-handed. The check deliberately covers the post-shot
## handover too: TurnController keeps active_member until the next turn
## begins, so the shooter keeps the weapon while its projectile flies
## and a running jackhammer drill (#316) or spear thrust keeps its
## visual until the effect finishes.
func _is_acting() -> bool:
	var parent := get_parent()
	return TurnController.active_team != "" \
			and parent != null and TurnController.active_member == parent


## Issue #234: true while THIS member carries the armed rock tool — the
## rock replaces the weapon in hands and the shoot input throws it with
## the grenade's aiming mechanics instead of firing the weapon. Only
## during the player team's turn: an armed rock left over when the turn
## ended never passes to an NPC (ToolInventory.reset_turn clears it at
## the start of the NEXT player turn).
func _rock_armed() -> bool:
	var parent := get_parent()
	return ToolInventory.armed_tool == ToolInventory.TOOL_ROCK \
			and parent != null and TurnController.active_member == parent \
			and TurnController.is_player_team(TurnController.active_team)


## Issue #234: HELD_STYLES index shown in hands — the rock (4) while the
## rock tool is armed for this member, otherwise the selected weapon.
## Issue #307: explicit mapping — the mine (weapon 4) and jackhammer
## (weapon 5) sit AFTER the rock style in HELD_STYLES, and the old
## `return selected_weapon` fallback showed the ROCK boulder for the
## mine (style 5 was unreachable). Weapons 0-3 keep the identity map.
func _held_style_index() -> int:
	if _rock_armed():
		return 4
	if selected_weapon == 4:
		return 5  # mine
	if selected_weapon == 5:
		return 6  # jackhammer
	if selected_weapon == 6:
		return 7  # railgun (#359)
	if selected_weapon == 7:
		return 8  # pistol (#526)
	if selected_weapon == 8:
		return 9  # baseball bat (#527)
	if selected_weapon == 9:
		return 10  # circular saw (#570)
	if selected_weapon == 10:
		return 11  # entrenching shovel (#656)
	return selected_weapon

## Held-weapon VISUALS live in the WeaponVisuals registry (issue #680,
## roadmap part 2): per-weapon sprite/rectangle, size and hold position as
## data — see scripts/WeaponVisuals.gd. This file only CONSUMES the table.
const WeaponVisuals := preload("res://scripts/WeaponVisuals.gd")
## Issue #68/#680: size, color, sprite and per-weapon hold config per
## selected weapon index — the WeaponVisuals table (aliased here under the
## historic name the code and tests use).
const HELD_STYLES: Array = WeaponVisuals.STYLES

## Currently selected weapon index (0..5), shared through the inventory HUD.
var selected_weapon := 0

## Issue #559: how far from the body CENTRE the held weapon floats,
## along the aim axis — the 64 px reference body's EDGE (32 px), outside
## the modular character's face zone (eyes and mouth span the middle
## ±16 px of the body), so the weapon anchor itself never sits over a
## facial feature. The weapon stays what it always was: a handless
## rectangle pinned to the AIM alone — positioned and rotated by the
## aim, never by the body visual or the face (a separate sibling node,
## see ModularCharacterVisual), so expressions and weapons never affect
## each other.
## Issue #680 (roadmap part 2): this is the shared DEFAULT anchor — the
## registry entry of a weapon may override it (WeaponVisuals.anchor).
const HELD_ANCHOR: float = WeaponVisuals.DEFAULT_ANCHOR
## Issue #559: the spearhead position the DAMAGE corridor uses stays at
## its authored reach — weapon mechanics are frozen by this issue (no
## damage, firing or balance changes). The drawn spear now floats
## further out (HELD_ANCHOR above), so the visible tip may overhang the
## damage tip by a few px — the hit NEVER reaches beyond what the player
## sees (the conservative direction).
const SPEAR_TIP_BASE := 26.0


func _ready() -> void:
	_held = ColorRect.new()
	_held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_held)
	# Issue #680: the sprite counterpart for textured registry styles
	# (rocket launcher, shotgun) — configured by the _update_held call
	# below.
	_held_sprite = Sprite2D.new()
	_held_sprite.visible = false
	add_child(_held_sprite)
	# Issue #114: charge meter shown above the wielder while holding F.
	_charge_bar = ColorRect.new()
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_bar.visible = false
	_charge_bar.color = Color(1.0, 0.6, 0.1, 0.9)
	_charge_bar.offset_top = -56.0
	_charge_bar.offset_bottom = -52.0
	add_child(_charge_bar)
	_update_held()
	# Issue #354: start EMPTY-HANDED — the weapon enters the hands only
	# when this member becomes the acting one (see _is_acting).
	_held.visible = _is_acting() and not _held_textured()
	_held_sprite.visible = _is_acting() and _held_textured()
	# Owner task 2026-11-11: shot SFX player on the SFX bus (default 0 dB;
	# volume tweaks only if a sound measures out of line — see the skill).
	_shot_player = AudioStreamPlayer.new()
	_shot_player.stream = SHOT_SOUND
	_shot_player.bus = "SFX"
	add_child(_shot_player)
	# Issue #495: the drill loop player — created once with the weapon,
	# played per drill. The stream is a per-instance DUPLICATE with the
	# loop set in code: Godot 4.7's headless wav import does not honor
	# edit/loop_mode sidecar pins (verified — compress pins apply, loop
	# pins do not), and each Weapon instance must own its loop points.
	var drill_stream: AudioStreamWAV = JACKHAMMER_SOUND.duplicate()
	drill_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	drill_stream.loop_begin = 0
	drill_stream.loop_end = drill_stream.data.size() / 2  # 16-bit mono
	_drill_player = AudioStreamPlayer.new()
	_drill_player.stream = drill_stream
	_drill_player.bus = "SFX"
	add_child(_drill_player)


## Issue #597: the turn-effect gate nodes (the bat knockback and the
## jackhammer drill) are re-parented to the LEVEL, not kept under this
## weapon — but their ticking lives in THIS node's _physics_process.
## When the wielder DIES mid-flight/mid-drill, the corpse is freed with
## this weapon attached: the ticking stops while the gate node stays in
## the turn_effects group FOREVER. Every later handover then stalls on
## "waiting for the projectiles" until the 30 s safety timer forces the
## turn — on the owner's web run (Level 4, the shooter died to a mine
## right after his bat swing) the game looked crashed from that shot on.
## Free the gates as the weapon leaves the tree so the handover the gate
## was holding open can complete. Safe at a level change too: the gates
## belong to the level that is going away with this weapon.
func _exit_tree() -> void:
	_end_bat_push()
	_end_jackhammer()


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	# Issue #101: tick the between-shots delay.
	_shot_delay_left = maxf(0.0, _shot_delay_left - delta)
	# Issue #307: an ACTIVE jackhammer drill ticks before the input logic —
	# it must keep running while the post-shot handover freezes input (the
	# drill IS the effect the handover waits for, see _drill_effect).
	if _drill_left > 0.0:
		_tick_jackhammer(delta)
	# Issue #527: the baseball bat's knockback ticks the same way — the
	# hit figures keep flying after the shot handed the turn over.
	if _bat_push_left > 0.0:
		_tick_bat_push(delta)
	# Issue #721 rework (owner 2026-11-28): the MELEE STRIKE state
	# machine — wind-up, sweep, strike, return — advances here, for
	# EVERY wielder: the strike's timing is gameplay now (the hit lands
	# at the forward sweep's peak, after the power-scaled wind-up), so
	# it must tick even when the held VISUAL below is skipped (a
	# stand-in shooter without the aim_dir accessor). The offsets it
	# computes feed the held visual's positions.
	_tick_melee(delta)

	var parent := get_parent() as CharacterBody2D
	var new_facing := _facing
	# Issue #277: facing follows the walk direction ALONG THE SURFACE (the
	# gravity frame's tangent), not the world x axis — beside a disc's rim
	# the tangent is vertical in world space and velocity.x never flipped
	# the facing. Flat and center-line levels: the tangent IS the x axis,
	# so the behavior there is unchanged.
	# Issue #277 rework: the tangent comes from the FIGURE (current_tangent),
	# which orients it by continuity — the local fallback stays only for
	# parents that predate that accessor.
	if parent != null:
		var tangent := Vector2(1.0, 0.0)
		if parent.has_method("current_tangent"):
			tangent = parent.current_tangent()
		elif parent.has_method("current_gravity"):
			# Issue #518 rework: the same LOCAL-frame tangent the figures use
			# (the character's own +x) — no world-x flip.
			var grav: Vector2 = parent.current_gravity()
			if grav.length_squared() > 0.5:
				tangent = Vector2(grav.y, -grav.x)
		# Issue #700: the walk direction is the brain's COMMAND
		# (walk_command — the clamped axis move() received), not the raw
		# velocity. On curved ground the slide after releasing the walk
		# key leaves a one-tick BACKWARDS tangential velocity
		# (move_and_slide converts the leftover along-gravity component
		# into tangent motion on a tilted floor) and the figure turned on
		# its own the moment D/A was released. The ground's shape must
		# never flip a figure — only a player/computer walk order may.
		# Parents without the accessor (plain test bodies) keep the
		# velocity fallback below.
		var walk := parent.velocity.dot(tangent)
		if parent.has_method("walk_command"):
			walk = float(parent.walk_command())
		if walk != 0.0:
			new_facing = signf(walk)
	# Issue #293: no authored gravity sign to track anymore — the aim frame
	# itself (current_gravity/current_tangent) already follows the terrain.
	if new_facing != _facing:
		_facing = new_facing
		_update_held()

	# Issue #33: only the controlled team member fires on input, and only
	# during the player team's turn (issue #65).
	var controlled: bool = parent != null and parent.get("controlled") == true \
			and TurnController.is_player_team(TurnController.active_team)
	if controlled:
		# Issue #327: a weapon with no uses left never enters the hand —
		# the sync resolves the panel selection against the TEAM budget
		# and falls back to the infinite spear.
		# Issue #316 rework: a member LOCKED to its weapon (it already fired
		# this turn) KEEPS that weapon in hands — even when the shot just
		# spent the team's LAST use of it. The jackhammer drill must not
		# morph into the spear mid-run: the wielder drills with the
		# jackhammer it activated, and only when the next player turn begins
		# does the panel advance to the next weapon the team can still pay
		# for (WeaponInventory.unlock_all).
		if not WeaponInventory.is_locked_for(get_parent()):
			selected_weapon = WeaponInventory.held_weapon_for(
					TurnController.team_id_of(get_parent()))
	# Issue #101 bugfix: ONLY the controlled member may fire on input —
	# every character has a Weapon node, so an unguarded Input check made
	# all characters holding the same weapon fire together.
	var can_shoot: bool = _shots_used[clampi(selected_weapon, 0, _shots_used.size() - 1)] < _shot_limit() \
			and _shot_delay_left == 0.0 and _cooldown_left == 0.0 \
			and not ToolInventory.has_used_tool(get_parent())
	# Issue #114: rocket (1), grenade (2) are CHARGED — pressing F starts
	# the charge, releasing F fires with power scaled by the hold time.
	# Issue #721 rework (owner 2026-11-28): the spear (3) and the shovel
	# (10) are charged too — the F hold picks the melee strike power.
	# Shotgun and pistol keep their instant press-fire behavior.
	# Issue #234: an armed rock is charged too — same F mechanic as the
	# grenade; releasing F throws the rock instead of firing the weapon.
	# Issue #246: the mine (4) is charged too — it is thrown like a grenade.
	# Issue #570 rework (owner, 2026-11-16): the circular saw (9) is
	# charged too — holding the shot key changes the power of the throw
	# (it used to fire at full power on the press).
	# Issue #244: while the handover waits for effects (after a shot or
	# when the timer ran out) the character is BLOCKED — no new charge, no
	# throw/fire; a charge in progress is cancelled without spending
	# anything (the not-can_act branch below).
	var frozen: bool = TurnController.is_input_frozen()
	var rock_armed := _rock_armed()
	# Issue #359: the railgun; issue #527 rework: the baseball bat;
	# issue #570 rework: the circular saw.
	var charged: bool = rock_armed or is_charged_weapon(selected_weapon)
	var can_act: bool = (rock_armed or can_shoot) and not frozen
	if controlled and can_act and not _charging \
			and Input.is_action_just_pressed("shoot"):
		if charged:
			_charging = true
			_charge_time = 0.0
		else:
			_fire()
	if controlled and _charging:
		if rock_armed and not can_act:
			# Issue #234: the rock left this member's hand without a throw
			# (disarmed, member switched, turn ended) — cancel the charge,
			# no quota spent, nothing thrown.
			_charging = false
		elif Input.is_action_just_released("shoot") or not can_act:
			_charging = false
			var power := clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
			if rock_armed:
				throw_rock(power)
			else:
				_fire(power)
		else:
			_charge_time = minf(_charge_time + delta, MAX_CHARGE_TIME)
			_charge_bar.visible = true
			var charge_width := 40.0 + 30.0 * (_charge_time / MAX_CHARGE_TIME)
			_charge_bar.offset_left = -charge_width / 2.0
			_charge_bar.offset_right = charge_width / 2.0
			# Issue #322: re-aim the bar into the view frame EVERY tick — the
			# offsets (and the camera ease) move under it while it is up.
			_align_charge_bar_to_view()
	if not _charging and _charge_bar.visible:
		_charge_bar.visible = false

	# Issue #68: keep the held weapon in sync with selection and facing.
	# Issue #234: an armed rock replaces the held weapon visual.
	if _held_style_index() != _held_style:
		_update_held()
	# Issue #354: an IDLE character carries no weapon — only the acting
	# member holds one in hands (see _is_acting); everyone else stands
	# empty-handed until their own turn comes. Issue #680: a textured
	# style carries its Sprite2D instead of the plain ColorRect.
	var show_held := _is_acting()
	_held.visible = show_held and not _held_textured()
	_held_sprite.visible = show_held and _held_textured()
	# Issue #67: keep the held weapon aligned with the character's view.
	if _held != null and parent != null and parent.has_method("aim_dir"):
		var aim: Vector2 = parent.aim_dir(_facing, 1.0)
		# Issue #307: while the drill runs the jackhammer points along the
		# drill direction instead of along the aim.
		if _drill_left > 0.0:
			aim = _drill_dir
		# Issue #716 (part 3a — follow-through): the DRAWN weapon angle
		# eases toward the live aim instead of snapping, so a swung aim
		# leaves a slight barrel trail that settles behind the swing.
		# VISUAL ONLY — the hold POSITION below still rides the TRUE aim
		# axis, and _aim(), corridors, hitboxes and every spawn calculation
		# keep the live aim: aiming stays pixel-accurate (part 3a
		# acceptance); only the drawn rotation lags.
		var aim_angle := aim.angle()
		if is_nan(_drawn_aim_angle) or is_nan(_last_aim_angle):
			_drawn_aim_angle = aim_angle
			_last_aim_angle = aim_angle
		else:
			# A re-aim beyond a small epsilon resets the idle settle clock
			# (wrap-safe across the ±PI seam).
			if absf(wrapf(aim_angle - _last_aim_angle, -PI, PI)) > 0.02:
				_still_for = 0.0
			_drawn_aim_angle = lerp_angle(_drawn_aim_angle, aim_angle,
					1.0 - exp(-AIM_FOLLOW_RATE * delta))
			_last_aim_angle = aim_angle
		# Issue #716 (part 3a — idle breathing): the bob fades in only
		# while the wielder stands SETTLED — no walk command, a steady aim
		# and no busy weapon animation — and eases back out the moment any
		# of that changes, so it never pops.
		var settled_input := true
		if _thrust_t >= 0.0 or _bat_swing_t >= 0.0 or _shovel_swing_t >= 0.0 \
				or _drill_left > 0.0 or _charging:
			settled_input = false
		elif parent.has_method("walk_command") \
				and parent.walk_command() != 0.0:
			# Issue #700's walk command (0.0 = planted) is the same signal the
			# facing follows — the character is only "standing still" when the
			# brain commands no walk.
			settled_input = false
		if settled_input:
			_still_for += delta
		else:
			_still_for = 0.0
		_idle_amount = move_toward(_idle_amount,
				1.0 if _still_for >= IDLE_SETTLE_DELAY else 0.0,
			delta / IDLE_FADE_TIME)
		var style: Dictionary = HELD_STYLES[_held_style_index()]
		# Issue #680 (part 2): per-weapon anchor from the registry (plain
		# styles resolve to the historic #559 default). Issue #721 rework:
		# a back-carry style (the bat) flips the anchor to the OPPOSITE
		# side of the aim — the weapon rests BEHIND the wielder.
		var style_anchor := _carry_anchor()
		_held.position = aim * style_anchor - style["size"] / 2.0
		# Issue #133: the spear (and every held weapon) rotates to the aim
		# axis instead of staying parallel to the ground.
		_held.pivot_offset = style["size"] / 2.0
		# Issue #716: the drawn angle is the eased follow-through angle
		# (see above), not the raw aim — visual only.
		_held.rotation = _drawn_aim_angle
		# Issue #721 rework: this tick's melee offsets — the thrust and
		# swing math lives in _tick_melee (gameplay timing: wind-up,
		# sweep, strike at the peak, return; see the state machine's
		# doc there). The visual only mirrors the offsets along the aim.
		_held.position += aim * _melee_thrust
		_held.position += aim * _melee_swing
		_held.position += aim * _melee_shovel_swing
		# Issue #680 (part 3): RECOIL — the held visual snaps back along
		# the aim on a committed shot and eases back to the hold position
		# over RECOIL_TIME seconds (a squared ease-out: the kick is a
		# jolt, the recovery is smooth). Magnitude is per-weapon data
		# (WeaponVisuals.recoil, 0 for melee styles). VISUAL ONLY — this
		# offset feeds the drawn _held/_held_sprite and nothing else; no
		# corridor, hitbox or gameplay calculation reads it.
		var recoil := 0.0
		if _recoil_t >= 0.0:
			_recoil_t += delta
			if _recoil_t <= RECOIL_TIME:
				var k := 1.0 - _recoil_t / RECOIL_TIME
				recoil = WeaponVisuals.recoil(_held_style) * k * k
			else:
				_recoil_t = -1.0
		_held.position -= aim * recoil
		# Issue #307: the drilling jackhammer shakes in the wielder's hands.
		if _drill_left > 0.0:
			_held.position += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		# Issue #359: so does a CHARGING railgun — the held weapon rattles
		# while the charge builds (the aim itself wobbles via sight_shake).
		if is_charging_railgun():
			_held.position += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		# Issue #722 rework (owner 2026-11-28): POWERING the contact
		# weapons — while F is held the jackhammer and the circular saw
		# REV in the wielder's hands: the tremble amplitude grows with the
		# charge fraction (a fresh press is calm, the full hold revs at the
		# running drill's own shake level — the rev eases straight into
		# the drilling tremble at the release), the jackhammer's bit
		# chatters along the aim and the saw blade judders in angle as
		# its motor spins it up. The #721 wind-up scaled with the strike
		# power AFTER the release; this is the same scaling on the charge
		# side, BEFORE it — the tool visibly powers up while the player
		# holds F. Visual only: these offsets feed the drawn
		# _held/_held_sprite and nothing else — no corridor, hitbox or
		# damage calculation reads them, and every #680-frozen number
		# stays untouched. A charged ROCK (the armed tool) never plays it
		# (rock_armed: the rock, not the weapon, is being powered).
		if _charging and not rock_armed \
				and (selected_weapon == 5 or selected_weapon == 9):
			_rev_t += delta
			var charge := clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
			var jitter: float = powering_jitter(selected_weapon, charge)
			_held.position += Vector2(randf_range(-jitter, jitter),
					randf_range(-jitter, jitter))
			if selected_weapon == 5:
				_held.position += aim * sin(_rev_t * TAU * JACKHAMMER_REV_HZ) \
						* JACKHAMMER_REV_CHATTER * charge
			else:
				_held.rotation += sin(_rev_t * TAU * SAW_REV_HZ) \
						* powering_wobble(selected_weapon, charge)
		# Issue #680: a textured style mirrors the very same anchor,
		# rotation and thrust/swing/shake offsets on its Sprite2D
		# (visual only). flip_v keeps the grip below the tube once the
		# aim swings past vertical — a plain rectangle fill is symmetric
		# and never had that problem, a drawn sprite is not.
		# Issue #680 rework (owner 2026-11-23): a textured style starts
		# from the same shared anchor, then moves LOWER and closer to the
		# body's vertical middle — the launcher's height along the stance
		# gravity axis becomes lift * LIFT_KEEP - DROP instead of the raw
		# aim lift. Issue #680 part 2: the hold values are PER WEAPON in
		# the registry (WeaponVisuals.lift_keep/drop); the 2026-11-24
		# owner rework ("a little lower") tightened the launcher's entry
		# (lift_keep 0.4 -> 0.3, drop 6 -> 9). Flat gravity keeps the
		# fallback DOWN so the math stays defined before the first tick.
		if _held_textured():
			var sprite_pos: Vector2 = _held.position + style["size"] / 2.0
			var grav := Vector2.DOWN
			if parent.has_method("current_gravity"):
				grav = parent.current_gravity()
			if grav.length_squared() > 0.5:
				grav = grav.normalized()
				var lift := -sprite_pos.dot(grav)
				sprite_pos += grav \
						* (lift * (1.0 - WeaponVisuals.lift_keep(_held_style)) \
						+ WeaponVisuals.drop(_held_style))
			_held_sprite.position = sprite_pos
			_held_sprite.rotation = _held.rotation
			_held_sprite.flip_v = absf(_held.rotation) > PI / 2.0
		# Issue #716 (part 3a — idle breathing): the settled bob — a slow
		# pure sine along the wielder's STANCE-GRAVITY axis (the body's up),
		# so the weapon gently rises and settles with the holder in every
		# stance, flat, tilted or radial. Applied LAST, on top of the
		# anchor/thrust/swing/recoil math and to BOTH render nodes, so it
		# composes with the recoil instead of fighting it (part 3a keeps
		# #715's kick untouched). A pure sine of the phase clock: bounded
		# by IDLE_AMPLITUDE forever (no drift) and exactly zero unless the
		# wielder is settled. VISUAL ONLY — no gameplay calculation reads
		# the drawn position.
		_idle_t += delta
		var bob := sin(TAU * _idle_t / IDLE_PERIOD) * IDLE_AMPLITUDE \
				* _idle_amount
		if bob != 0.0:
			var idle_axis := Vector2.DOWN
			if parent.has_method("current_gravity"):
				var stance: Vector2 = parent.current_gravity()
				if stance.length_squared() > 0.5:
					idle_axis = stance.normalized()
			_held.position += idle_axis * bob
			if _held_textured():
				_held_sprite.position += idle_axis * bob


## Issue #322: the charge bar (the power indicator) is authored above
## the wielder in the WEAPON's local frame, but the weapon rides the
## figure's gravity frame — on a flipped level (or beside a disc rim)
## the bar rendered BELOW the wielder, upside-down, while charging. Same
## treatment as the figure HUD (HudPose, issue #311): rotate the bar
## around the wielder's origin into the coordinate system the CURRENT
## view shows, so it renders upright above the wielder in both camera
## types. Called every physics tick the charge is up, so it rides the
## camera ease like HudPose does.
func _align_charge_bar_to_view() -> void:
	var viewport := get_viewport()
	var camera := viewport.get_camera_2d() if viewport != null else null
	var view_rotation := camera.rotation if camera != null else 0.0
	# A Control rotates around `pivot_offset`; with the pivot at
	# -position the fixed point is the wielder's origin (the weapon node
	# sits on it), so the bar orbits the figure exactly like the HUD.
	_charge_bar.pivot_offset = -_charge_bar.position
	_charge_bar.rotation = view_rotation - global_rotation


## Issue #680: true while the CURRENT held style renders through the
## Sprite2D (a textured HELD_STYLES entry — the rocket launcher
## prototype) instead of the plain ColorRect fill.
func _held_textured() -> bool:
	return _held_style >= 0 and _held_style < HELD_STYLES.size() \
			and HELD_STYLES[_held_style].has("texture")


## Issue #68: draw the currently selected weapon in front of the wielder.
func _update_held() -> void:
	if _held == null:
		return
	_held_style = _held_style_index()
	var style: Dictionary = HELD_STYLES[_held_style]
	var size: Vector2 = style["size"]
	# Issue #680: the textured style draws the sprite at the style's
	# in-game size; the ColorRect stays hidden. Everything downstream
	# (anchor, aim rotation, thrust/swing offsets) is shared with the
	# rectangle weapons in _physics_process.
	# Issue #680 part 2: the hold position is PER WEAPON (registry
	# anchor/drop), not the shared #559 constants.
	if style.has("texture"):
		_held.visible = false
		_held_sprite.visible = _is_acting()
		var tex: Texture2D = style["texture"]
		_held_sprite.texture = tex
		_held_sprite.scale = size / Vector2(
				tex.get_width(), tex.get_height())
		_held_sprite.position = Vector2(
				_facing * WeaponVisuals.anchor(_held_style),
				WeaponVisuals.drop(_held_style))
		return
	_held.visible = true
	_held.size = size
	_held.position = Vector2(_facing * WeaponVisuals.anchor(_held_style),
			0.0) - size / 2.0
	_held.color = style["color"]


func _shot_limit() -> int:
	return SHOTS_PER_TURN[clampi(selected_weapon, 0, SHOTS_PER_TURN.size() - 1)]


## Issue #101: called by TurnController at the start of every turn —
## restores the full shot quota for this character.
func reset_shots() -> void:
	for i in _shots_used.size():
		_shots_used[i] = 0
	_shot_delay_left = 0.0


## Issue #221: true while a fresh shot is still impossible (muzzle
## cooldown or the between-shots pause). The NPC AI uses this so its
## "nothing useful left to do" watchdog does not end a turn mid-reload.
func is_busy() -> bool:
	return _cooldown_left > 0.0 or _shot_delay_left > 0.0


## Issue #316: true while this wielder's jackhammer drill is running —
## Player.gd keeps the aim keys steering the drill (and the drill's
## velocity intact) through the frozen-input handover.
func is_drilling() -> bool:
	return _drill_left > 0.0


## Issue #559: true while this weapon is charging a shot (hold F on a
## charged weapon). Read-only query for the character animator's angry
## charge-focus face — no mechanics, no behavior change.
func is_charging() -> bool:
	return _charging


func _fire(power := 1.0) -> void:
	# Issue #207: a character that used a tool this turn can't also fire —
	# tool OR weapon per character per turn, never both.
	if ToolInventory.has_used_tool(get_parent()):
		return
	# Issue #305: the team's use budget for this weapon is spent — the
	# weapon no longer fires (the spear is the exception: infinite uses).
	var team_id := TurnController.team_id_of(get_parent())
	if not WeaponInventory.can_spend_weapon(team_id, selected_weapon):
		return
	# Issue #131, reworked in #143: the FIRST shot of the turn locks the
	# weapon selection — for THIS character only (the constraint is per
	# character, not per player).
	var shots_before := 0
	for used in _shots_used:
		shots_before += used
	if shots_before == 0:
		# Fix (#144 run): `parent` was out of scope here — use get_parent().
		WeaponInventory.lock_for(get_parent())
	_cooldown_left = COOLDOWN
	_shots_used[clampi(selected_weapon, 0, _shots_used.size() - 1)] += 1
	# Issue #305: one use of this weapon leaves the team's budget.
	WeaponInventory.spend_weapon(team_id, selected_weapon)
	# Issue #101: 3-second pause before the next shot of the same turn.
	_shot_delay_left = SHOT_DELAY
	# Issue #680 (part 3): every committed shot kicks the held weapon
	# back along the aim (per-weapon magnitude in WeaponVisuals.recoil;
	# melee styles carry 0 — their own lunge/swing is the animation).
	_recoil_t = 0.0
	# Issue #252: debug action log — every shot names its wielder.
	var shooter := get_parent()
	var who: Variant = "?"
	if shooter != null and shooter.get("display_name") != null:
		who = shooter.get("display_name")
	DebugInfo.log("%s fires %s" % [str(who),
			WeaponInventory.WEAPONS[clampi(selected_weapon, 0,
				WeaponInventory.WEAPONS.size() - 1)]])
	# Owner task 2026-11-11: the shot sound fires through the shared
	# player on every committed shot (all weapons, player and NPC alike).
	# Issue #495: EXCEPT the jackhammer (weapon 5) — firing it starts the
	# drill loop instead (see _start_jackhammer), no gunshot bang on top.
	if selected_weapon != 5:
		_play_shot_sound()
	match selected_weapon:
		0: _fire_shotgun()
		1: _fire_rocket(power)
		2: _fire_grenade(power)
		3: _thrust_spear(power)
		4: _throw_mine(power)
		5: _start_jackhammer(power)
		6: _fire_railgun(power)
		7: _fire_pistol()
		8: _swing_bat(power)
		9: _throw_saw(power)
		10: _swing_shovel(power)
	# Issue #101+#65: only the LAST shot of the turn hands the turn over;
	# with quota remaining the character keeps acting after the pause.
	if _shots_used[clampi(selected_weapon, 0, _shots_used.size() - 1)] >= _shot_limit():
		TurnController.notify_shot()


## Owner task 2026-11-11 (godot-sound-work skill): play the shot sound.
## The small random pitch (0.95–1.05) keeps rapid fire from fatiguing.
func _play_shot_sound() -> void:
	_shot_player.pitch_scale = randf_range(0.95, 1.05)
	_shot_player.play()


## Issue #66: NPC entry point — the enemy AI fires through the same weapon
## (same cooldown, same projectiles, same shooter pass-through).
## Issue #481: returns whether a shot really committed — _fire() can
## still refuse (a tool already used this turn, the team budget spent),
## and the caller locks its weapon choice only on a real shot.
func npc_fire() -> bool:
	if _cooldown_left > 0.0 or _shot_delay_left > 0.0 \
			or _shots_used[clampi(selected_weapon, 0, _shots_used.size() - 1)] >= _shot_limit():
		return false
	var before := _total_shots_used()
	_fire()
	return _total_shots_used() > before


## Issue #481: every committed shot of this turn, across ALL weapons —
## the committed-shot signal npc_fire() reports to the NPC AI (whose
## own fire gate cannot see inside _fire's early returns).
func _total_shots_used() -> int:
	var total := 0
	for used in _shots_used:
		total += used
	return total


## Issue #368: brief muzzle flash where a shot leaves the barrel — a
## hot point of light that fades in ~0.1 s.
## Issue #680 (part 3): the flash is a CARTOON starburst now too — a
## bold dark outline, vivid flat fills and an exaggerated forward
## spike along the firing direction (MuzzleFlash), layered on top of
## the light so the shot reads in the weapon art style everywhere.
func _muzzle_flash(at: Vector2, dir := Vector2.RIGHT) -> void:
	var level_root := get_parent().get_parent()
	if level_root == null:
		return
	ShotLight.flash(level_root, at, Color(1.0, 0.85, 0.45), 110.0, 2.6, 0.12)
	# Issue #720 (part 4b): the registry's per-weapon flash data — size
	# and palette — feeds straight into MuzzleFlash.pop. Styles without a
	# "flash" entry resolve to the #715 default burst (the warm 22 px
	# starburst), so every earlier weapon reads exactly as before; the
	# railgun pops its big icy burst in the beam's own colors and the
	# pistol a small hot one.
	var flash := WeaponVisuals.flash_style(_held_style_index())
	MuzzleFlash.pop(level_root, at, dir,
			flash.get("size", 22.0) as float, flash)


## Issue #721 (roadmap part 4c): melee hit feedback — the shared 3c
## comic hit star (CartoonBlast.pop_hit) popped at a strike point in
## the weapon's own palette (the registry "flash" entry, the same
## route the railgun's #720 world strike takes). Issue #722 (part 4d):
## the CONTACT weapons reuse it for their grind/bore feedback (the
## jackhammer's grind chunks and bore dust). Callers pass WORLD
## positions; the star rides the level root so it never rotates with
## the gravity frame and never dies with a figure. Purely visual — no
## gameplay calculation reads it.
func _pop_melee_hit(at: Vector2, intensity: float) -> void:
	var parent := get_parent()
	if parent == null or parent.get_parent() == null:
		return
	CartoonBlast.pop_hit(parent.get_parent(), at, intensity,
			WeaponVisuals.flash_style(_held_style_index()))


func _spawn_projectile(type: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float = 0.0,
		pop_flash := true) -> Area2D:
	var projectile := Area2D.new()
	projectile.set_script(ProjectileScript)
	projectile.setup(type, velocity, damage, lifetime, size, color, blast_radius)
	# Issue #57: remember the wielder so shots pass through them.
	projectile.shooter = get_parent()
	projectile.global_position = global_position + _aim() * 36.0
	get_parent().get_parent().add_child(projectile)
	# Issue #368: muzzle flash where the shot leaves the barrel.
	# Issue #680 (part 3): aimed along the shot's own velocity; the
	# shotgun suppresses it per pellet (one flash per volley, see
	# _fire_shotgun).
	if pop_flash:
		_muzzle_flash(projectile.global_position, velocity.normalized())
	return projectile


func _fire_shotgun() -> void:
	var aim := _aim()
	# Issue #680 (part 3): the volley pops ONE cartoon flash for the
	# whole fan — five starbursts stacked at the same muzzle would only
	# smear into a blob. It aims dead along the barrel (the fan spreads
	# from there).
	_muzzle_flash(global_position + aim * 36.0, aim)
	for i in 5:
		var spread := deg_to_rad(-8.0 + 4.0 * i)
		var velocity := aim.rotated(spread) * PELLET_SPEED
		_spawn_projectile(Projectile.Type.PELLET, velocity, PELLET_DAMAGE,
			PELLET_LIFETIME, Vector2(10, 4), Color(0.95, 0.85, 0.3, 1),
			0.0, false)


## Issue #526: the pistol shot — ONE bullet straight along the aim (the
## whole point: no shotgun spread), less damage per shot than the volley.
func _fire_pistol() -> void:
	var velocity := _aim() * PISTOL_SPEED
	_spawn_projectile(Projectile.Type.PELLET, velocity, PISTOL_DAMAGE,
		PISTOL_LIFETIME, Vector2(10, 4), Color(0.5, 0.55, 0.6, 1))


## Issue #527: the baseball bat swing — an instant melee corridor check
## along the aim (like the spear's thrust, but with the bat's own reach
## and lateral tolerance). EVERY figure it reaches — friendly fire is on
## (#57), only the wielder is exempt — takes BAT_DAMAGE and is LAUNCHED
## like a projectile (issue #549): the initial impulse runs along the
## shot direction with a guaranteed lift against gravity (BAT_MIN_LIFT),
## then gravity carries the flight (see _tick_bat_push), gated as a turn
## effect so the post-shot handover waits while the hit figures fly
## (same pattern as the drill). Issue #527 rework: the swing power
## (chosen by the hold-F charge, the rocket's issue-#114 recipe) scales
## the launch — a tap pushes at 40% of BAT_KNOCKBACK_SPEED, the full
## hold at 100%. Issue #721 rework (owner 2026-11-28): the swing is a
## WIND-UP first — the corridor hit lands at the forward sweep's peak
## (see _bat_strike), not at the release; the bat rests on the opposite
## side of the wielder and pulls further back for the wind-up, scaled
## by the same power. The turn-effect gate is created here, at the
## swing's start, so the handover waits through the whole animation.
func _swing_bat(power := 1.0) -> void:
	_melee_power = clampf(power, 0.0, 1.0)
	_bat_swing_t = 0.0
	_bat_strike_done = false
	_bat_push.clear()
	_bat_push_left = 0.0
	_bat_push_speed = BAT_KNOCKBACK_SPEED \
			* lerpf(MIN_SHOT_POWER, 1.0, _melee_power)
	var parent := get_parent() as Node2D
	if parent == null:
		return
	if _bat_effect == null or not is_instance_valid(_bat_effect):
			_bat_effect = Node.new()
			_bat_effect.name = "BatKnockback"
			_bat_effect.add_to_group(TurnController.EFFECT_GROUP)
			if parent.get_parent() != null:
				parent.get_parent().add_child(_bat_effect)


## Issue #721 rework: the bat strike itself — the corridor check that
## runs the instant the forward sweep peaks (the wind-up has played out
## first). Everything else is the historic _swing_bat body: every
## figure the corridor reaches takes BAT_DAMAGE and is LAUNCHED
## (issue #549); the strike direction is sampled from the LIVE aim at
## the strike moment (the wielder may re-aim through the wind-up).
func _bat_strike() -> void:
	_bat_strike_done = true
	var parent := get_parent() as Node2D
	if parent == null:
		return
	_bat_push_dir = _aim().normalized()
	var dir := _bat_push_dir
	var perp := Vector2(-dir.y, dir.x)
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body == parent or not is_instance_valid(body) \
					or not body.has_method("take_damage"):
				continue
			var hp = body.get("health")
			if hp is int and hp <= 0:
				continue
			var offset := body.global_position - global_position
			var along := offset.dot(dir)
			var lateral := absf(offset.dot(perp))
			if along > 0.0 and along <= BAT_RANGE and lateral <= BAT_LATERAL:
				body.take_damage(BAT_DAMAGE)
				# Issue #721 (part 4c): the bat strike pops the 3c hit star
				# where the barrel met the victim — the warm wood family,
				# big for the heaviest melee damage.
				_pop_melee_hit(global_position + dir
						* minf(along, BAT_RANGE * 0.5), 1.5)
				_bat_push.append(_bat_launch(body))
	if _bat_push.is_empty():
		return
	_bat_push_left = BAT_FLIGHT_CAP


## Issue #549: the initial flight record of one victim — the impulse
## along the shot direction, lifted so at least BAT_MIN_LIFT of the
## launch speed points AGAINST the level's gravity at the victim (a
## flat aim would pin them to the floor and there would be no arc to
## bend; the missing anti-gravity component is replaced by the
## guaranteed one, the aimed TANGENTIAL direction always survives).
func _bat_launch(body: Node2D) -> Dictionary:
	var vel := _bat_push_dir * _bat_push_speed
	var grav := LevelTerrain.gravity_vector(body)
	var lift := vel.dot(-grav)
	var min_lift := _bat_push_speed * BAT_MIN_LIFT
	if lift < min_lift:
		vel -= grav * (min_lift - lift)
	return {"body": body, "vel": vel, "air": false}


## Issue #549: one physics tick of the bat's knockback — every hit
## figure flies BALLISTICALLY like a projectile: gravity accelerates the
## stored flight velocity every tick (the figures' shared Stats.GRAVITY
## along the level's LevelTerrain gravity field, exactly what a figure
## integrates in its own _physics_process), and the velocity write +
## body shove is the jackhammer's #363 recipe (an idle figure's clamp
## eats a one-shot tangential velocity write, so the body itself is
## moved every tick). A CharacterBody2D victim that has been airborne
## and is back on the floor has LANDED — its flight ends there; a plain
## Node2D stand-in (tests) reports no floor contact and rides the
## BAT_FLIGHT_CAP to the end.
func _tick_bat_push(delta: float) -> void:
	_bat_push_left -= delta
	var flying: Array = []
	for entry in _bat_push:
		# Issue #597: a victim can DIE from the bat hit — its corpse is
		# freed mid-flight, and `as` on a freed object is a script error
		# that ABORTS this tick (and every later one: the abort repeats
		# each physics frame while the loop restarts on the same freed
		# record). That error storm is the web-build "crash" of #597 —
		# and the aborted tick never reached its end, so the flight's
		# turn-effect gate stayed live and every handover after it
		# stalled on pending effects. Drop a dead record BEFORE any cast
		# touches it: validity first, cast second.
		var raw = entry["body"]
		if raw == null or not is_instance_valid(raw):
			continue
		var body := raw as Node2D
		if body == null or not is_instance_valid(body):
			continue
		var vel: Vector2 = entry["vel"] \
				+ LevelTerrain.gravity_vector(body) * Stats.GRAVITY * delta
		entry["vel"] = vel
		if "velocity" in body:
			body.velocity = vel
		var physics := body as PhysicsBody2D
		if physics != null:
			physics.move_and_collide(vel * delta)
		else:
			body.global_position += vel * delta
		var character := body as CharacterBody2D
		if character != null:
			if character.is_on_floor():
				if entry["air"]:
					continue  # landed — this flight is over
			else:
				entry["air"] = true
		flying.append(entry)
	_bat_push = flying
	if _bat_push.is_empty() or _bat_push_left <= 0.0:
		_end_bat_push()


## Issue #527: the knockback is done — release the turn-effect gate so
## the handover can pass the turn.
func _end_bat_push() -> void:
	_bat_push_left = 0.0
	_bat_push.clear()
	if _bat_effect != null and is_instance_valid(_bat_effect):
			_bat_effect.queue_free()
	_bat_effect = null


## Issue #656: the entrenching shovel swing — the bat's instant melee
## corridor with the spear's lateral tolerance but LESS reach than the
## spear, plus THE DIG: every swing carves the upright ellipse out of
## destructible ground in front of the wielder (see _shovel_dig).
## Issue #721 rework (owner 2026-11-28): charged — `power` (0..1, the
## hold-F charge) scales the wind-up AND the dig carve; the swing winds
## up first (see the swing tick in _physics_process) and the corridor
## hit + dig land at the forward sweep's peak (see _shovel_strike).
func _swing_shovel(power := 1.0) -> void:
	_melee_power = clampf(power, 0.0, 1.0)
	_shovel_swing_t = 0.0
	_shovel_strike_done = false


## Issue #721 rework: the shovel strike itself — the corridor hit and
## the dig, run the instant the forward sweep peaks (after the
## power-scaled wind-up).
func _shovel_strike() -> void:
	_shovel_strike_done = true
	_shovel_sweep_hit()
	_shovel_dig()


## Issue #656: the swing's damage corridor — every figure ahead of the
## wielder along the aim within SHOVEL_RANGE and the spear's 12 px
## lateral tolerance takes SHOVEL_DAMAGE (20% of the spear's hit).
## Friendly fire stays on (#57) — only the wielder is exempt, like the
## spear's thrust and the bat's swing.
func _shovel_sweep_hit() -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var dir := _aim().normalized()
	var perp := Vector2(-dir.y, dir.x)
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body == parent or not is_instance_valid(body) \
					or not body.has_method("take_damage"):
				continue
			var hp = body.get("health")
			if hp is int and hp <= 0:
				continue
			var offset := body.global_position - global_position
			var along := offset.dot(dir)
			var lateral := absf(offset.dot(perp))
			if along > 0.0 and along <= SHOVEL_RANGE and lateral <= 12.0:
				body.take_damage(SHOVEL_DAMAGE)
				# Issue #721 (part 4c): the shovel strike star — small (the
				# shovel's chip damage) and earthy, at the contact point.
				_pop_melee_hit(global_position + dir
						* minf(along, SHOVEL_RANGE * 0.5), 0.8)


## Issue #656: THE DIG — one use carves ONE upright ellipse out of
## destructible ground in front of the wielder: centred a touch ahead
## of the body along the aim (SHOVEL_DIG_OFFSET — rework #3: the bore
## opens ON the wielder so the figure already stands inside it), its long
## axis (the
## figure's height) along the character's VERTICAL (_frame_up — the dig
## stays upright in the wielder's gravity frame wherever the aim
## points), the short axis (the figure's FULL width, rework #2: the
## original "half of character's width" (32) could never admit the
## 48 px collider capsule, so the figure just bumped into the notch —
## the dug hole must let the character MOVE INTO the tunnel) across
## it. Rework:
## the ellipse is ANCHORED in world space by the first swing of the
## stance (see SHOVEL_DIG_REANCHOR) and carved EXACTLY via
## DestructibleGround.apply_dig — no fan of blast circles — so however
## the five swings are aimed while standing, the removed ground remains
## that one ellipse. Stamping into thin air is a no-op and indestructible
## ground ignores the dig, so a swing at nothing costs the shot and
## moves nothing. Issue #721 rework (owner 2026-11-28): the strike
## POWER scales the carve (both radii at the MIN_SHOT_POWER..1 charge
## scale; the full hold is the historic 64x64 bore) and a STRONGER
## swing at the same anchor re-carves it deeper — an equal or weaker
## swing stays the historic once-per-anchor no-op.
func _shovel_dig() -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var dig_scale := lerpf(MIN_SHOT_POWER, 1.0, _melee_power)
	if _shovel_dig_body == Vector2.INF \
				or parent.global_position.distance_to(_shovel_dig_body) \
				> SHOVEL_DIG_REANCHOR:
		_shovel_dig_anchor = parent.global_position \
				+ _aim().normalized() * SHOVEL_DIG_OFFSET
		_shovel_dig_up = _frame_up().normalized()
		_shovel_dig_body = parent.global_position
		_shovel_dig_power = -1.0
	if _shovel_dig_power >= dig_scale:
		return
	var carved_any := false
	for ground in get_tree().get_nodes_in_group("destructible_ground"):
		var chunk := ground as Node2D
		if chunk != null and is_instance_valid(chunk) \
				and chunk.has_method("apply_dig"):
			chunk.apply_dig(_shovel_dig_anchor,
					SHOVEL_DIG_WIDTH / 2.0 * dig_scale,
					SHOVEL_DIG_HEIGHT / 2.0 * dig_scale,
					_shovel_dig_up)
			carved_any = true
	_shovel_dig_power = dig_scale
	# Issue #721 (part 4c): a carve that actually opened ground pops a
	# dusty earthy 3c hit star at the bore — the dig reads the moment it
	# opens (the star reuses the shovel's own flash palette). Once per
	# anchor: later swings skip the carve above and never reach this pop;
	# a swing into thin air stays silent.
	if carved_any:
		_pop_melee_hit(_shovel_dig_anchor, 1.1)


func _fire_rocket(power := 1.0) -> void:
	# Issue #114: the rocket is a rigid body — its speed scales with the
	# shot power (how long F was held). Issue #245: that speed is only the
	# INITIAL velocity — the rocket now has weight, so the level's gravity
	# bends the flight into an arc after launch.
	var speed := ROCKET_SPEED * lerpf(MIN_SHOT_POWER, 1.0, power)
	_spawn_body(ProjectileBody.Kind.ROCKET,
		_aim() * speed, ROCKET_DAMAGE, ROCKET_LIFETIME,
		Vector2(22, 8), Color(0.9, 0.35, 0.15, 1), ROCKET_BLAST, ROCKET_MASS)


func _fire_grenade(power := 1.0) -> void:
	# Issue #99: NPC grenades are aimed ballistically at the target so the
	# arc lands ON the target instead of falling back onto the shooter's
	# own team (blast damage is friendly fire since issue #57).
	if npc_target != null and is_instance_valid(npc_target):
		var to := npc_target.global_position - global_position
		var t := clampf(to.length() / GRENADE_SPEED, 0.5, 1.5)
		var velocity := to / t
		velocity.y -= 0.5 * 1200.0 * t
		_spawn_body(ProjectileBody.Kind.GRENADE, velocity, GRENADE_DAMAGE,
			GRENADE_FUSE, Vector2(14, 14), Color(0.3, 0.7, 0.3, 1),
			GRENADE_BLAST, GRENADE_MASS)
		npc_target = null
		return
	# Issue #114: player grenades are charged too — power scales the launch
	# speed, the grenade itself is a bouncing rigid body under gravity.
	# Issue #277 rework: the launch velocity follows the INDICATED aim plus
	# the frame's lob — no more 180° flip when facing left (see
	# lobbed_velocity).
	var speed := GRENADE_SPEED * lerpf(MIN_SHOT_POWER, 1.0, power)
	var aim := _aim()
	var velocity := lobbed_velocity(aim, _frame_up(), speed,
			lerpf(MIN_SHOT_POWER, 1.0, power))
	_spawn_body(ProjectileBody.Kind.GRENADE, velocity, GRENADE_DAMAGE,
		GRENADE_FUSE, Vector2(14, 14), Color(0.3, 0.7, 0.3, 1),
		GRENADE_BLAST, GRENADE_MASS)


## Issue #246: the MINE throw — the grenade's lobbed arc and aiming, but
## the mine has no fuse: it lands, lies dormant (across turns) and only
## explodes when a character steps within 0.6 of a figure width of it,
## after a 2-second countdown (all of that lives in ProjectileBody).
func _throw_mine(power := 1.0) -> void:
	var mine_aim := _aim()
	var strength := lerpf(MIN_SHOT_POWER, 1.0, power)
	# Issue #277 rework: the indicated aim + frame lob (see lobbed_velocity).
	var mine_velocity := lobbed_velocity(mine_aim, _frame_up(),
			MINE_SPEED * strength, strength)
	_spawn_body(ProjectileBody.Kind.MINE, mine_velocity, MINE_DAMAGE, 0.0,
		Vector2(14, 14), Color(0.22, 0.24, 0.3, 1), MINE_BLAST, MINE_MASS)


## Issue #570: the CIRCULAR SAW throw — the mine's lobbed arc and aiming,
## but the saw has no fuse and no blast: once it lands it spins in place,
## sucking in nearby figures and grinding the contact ones (all of that
## lives in ProjectileBody, Kind.SAW), then it disappears. Issue #99
## mirror: an NPC lobs the saw ballistically at its target like the
## grenade, so the blade lands ON the target and the suction does the rest.
func _throw_saw(power := 1.0) -> void:
	if npc_target != null and is_instance_valid(npc_target):
		var to := npc_target.global_position - global_position
		var t := clampf(to.length() / SAW_SPEED, 0.5, 1.5)
		var velocity := to / t
		velocity.y -= 0.5 * 1200.0 * t
		_spawn_body(ProjectileBody.Kind.SAW, velocity, 0, 0.0,
			Vector2(16, 16), Color(0.75, 0.78, 0.85, 1), 0.0, SAW_MASS)
		npc_target = null
		return
	var saw_aim := _aim()
	var strength := lerpf(MIN_SHOT_POWER, 1.0, power)
	# Issue #277 rework: the indicated aim + frame lob (see lobbed_velocity).
	var saw_velocity := lobbed_velocity(saw_aim, _frame_up(),
			SAW_SPEED * strength, strength)
	_spawn_body(ProjectileBody.Kind.SAW, saw_velocity, 0, 0.0,
		Vector2(16, 16), Color(0.75, 0.78, 0.85, 1), 0.0, SAW_MASS)


## Issue #227: the Rock TOOL throw. Same launch arc as a player grenade
## (lobbed, level gravity, bouncing), but the rock never explodes — on
## its fuse it crumbles into destructible ground where it rests
## (ProjectileBody._create_ground).
## Issue #234 rework: the rock is thrown through the grenade's FULL aiming
## mechanics — `power` (0..1, the hold-F charge) scales the launch speed
## exactly like a grenade. Called by the charged-shoot release in
## _physics_process; ToolInventory.rock_thrown spends the tool quota.
func throw_rock(power := 1.0) -> void:
	var rock_aim := _aim()
	var strength := lerpf(MIN_SHOT_POWER, 1.0, power)
	# Issue #277 rework: the indicated aim + frame lob (see lobbed_velocity).
	var rock_velocity := lobbed_velocity(rock_aim, _frame_up(),
			GRENADE_SPEED * strength, strength)
	_spawn_body(ProjectileBody.Kind.ROCK, rock_velocity, 0, GRENADE_FUSE,
		Vector2(16, 16), Color(0.55, 0.5, 0.45, 1),
		ProjectileBody.ROCK_GROUND_RADIUS, ROCK_MASS)
	ToolInventory.rock_thrown(get_parent())


## Issue #727: never spawn a projectile inside the ground. `offset` is
## the intended spawn offset from the weapon (aim * 36); a ground-layer
## ray from the weapon to that point reports the first terrain in the
## way, and the spawn backs off so the whole body clears the surface
## (half the body's diagonal + margin). The offset never collapses
## below SPAWN_MIN_OFFSET, so a point-blank throw still starts in front
## of the wielder (outside its 24 px capsule) and then simply bounces
## off the surface — visible, never buried.
const SPAWN_MIN_OFFSET := 12.0
const SPAWN_SURFACE_MARGIN := 2.0


func _safe_spawn_position(offset: Vector2, size: Vector2) -> Vector2:
	var target := global_position + offset
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			global_position, target, 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return target
	var clear := size.length() / 2.0 + SPAWN_SURFACE_MARGIN
	var t: float = maxf(
			(hit.position - global_position).length() - clear,
			SPAWN_MIN_OFFSET)
	return global_position + offset.normalized() * t


## Issue #114: spawn a physics-driven explosive projectile (rigid body).
func _spawn_body(kind: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float, mass: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(ProjectileBodyScript)
	body.setup(kind, velocity, damage, lifetime, size, color, blast_radius, mass)
	# Issue #57: remember the wielder so shots pass through them.
	body.shooter = get_parent()
	# Issue #727: a close-range throw aimed at the ground used to spawn
	# the projectile 36 px ahead of the weapon — inside the terrain (the
	# figure centre sits ~29 px above the floor, so a steep throw clears
	# the surface well before the spawn point; a wall at point-blank did
	# the same sideways). The spawn is now clamped to the surface: the
	# first ground between the weapon and the intended point backs the
	# spawn off so the whole body starts clear of the soil.
	body.global_position = _safe_spawn_position(_aim() * 36.0, size)
	get_parent().get_parent().add_child(body)
	# Issue #368: muzzle flash where the shot leaves the barrel.
	# Issue #680 (part 3): aimed along the shot's own velocity.
	_muzzle_flash(body.global_position, velocity.normalized())
	return body


## Issue #721 rework (owner 2026-11-28): the SIGNED hold anchor — the
## registry magnitude, flipped to the opposite side of the aim for a
## back-carry style (the baseball bat rests BEHIND the wielder; see
## WeaponVisuals.carry_sign).
func _carry_anchor() -> float:
	var idx := _held_style_index()
	return WeaponVisuals.anchor(idx) * WeaponVisuals.carry_sign(idx)


## Issue #721 rework: the power-scaled wind-up duration of the melee
## strike currently animating — MELEE_WINDUP_MIN on a tap,
## +MELEE_WINDUP_RANGE at the full hold. The wind-up AMPLITUDE scales
## with the power the same way (see the swing ticks).
func _melee_windup_time() -> float:
	return MELEE_WINDUP_MIN + MELEE_WINDUP_RANGE * _melee_power


## Issue #721 rework: the spear's thrust reach for the current strike
## power — MIN_SHOT_POWER..1 of the historic SPEAR_RANGE (a tap pokes
## at 40%, the full hold is the classic lunge). Damage stays frozen.
func _spear_reach() -> float:
	return SPEAR_RANGE * lerpf(MIN_SHOT_POWER, 1.0, _melee_power)


## Issue #721 rework: the bat/shovel strike sweep's peak OFFSET along
## the aim, measured from the CURRENT (signed) carry anchor so the
## strike centre lands exactly at the historic position (the default
## anchor + half the corridor reach) wherever the weapon rests.
func _melee_strike_offset(corridor_range: float) -> float:
	var idx := _held_style_index()
	return WeaponVisuals.anchor(idx) + corridor_range * 0.5 \
			- _carry_anchor()


## Issue #721 rework (owner 2026-11-28): the MELEE STRIKE state machine,
## ticked from _physics_process BEFORE the held visual — the strike's
## timing is gameplay now, not just animation:
##   * SPEAR (issue #133/#257 base): a WIND-UP first — the spear pulls
##     BACK (SPEAR_PULLBACK * power, eased out) over the power-scaled
##     wind-up, then lunges fast out (0.12 s) to the power-scaled reach
##     and returns slowly (0.5 s). The hitbox follows the spearhead for
##     the whole lunge, out and back; the pull-back never hits.
##   * BAT (issue #527 base) and SHOVEL (issue #656 base): the same
##     wind-up (BAT_WINDUP / SHOVEL_WINDUP * power) then a fast forward
##     sweep (0.1 s) to the historic strike position and a slow return
##     (0.3 s). The corridor hit (and the shovel's dig) land exactly at
##     the sweep's peak — _bat_strike / _shovel_strike — so the swing
##     animation really happens BEFORE the strike, scaled by its power.
## Runs for every wielder (the visual block below may be skipped for
## stand-in shooters); the offsets are exposed for the held visual.
func _tick_melee(delta: float) -> void:
	_melee_thrust = 0.0
	_melee_swing = 0.0
	_melee_shovel_swing = 0.0
	if _thrust_t >= 0.0:
		_thrust_t += delta
		var windup := _melee_windup_time()
		var pull := SPEAR_PULLBACK * _melee_power
		var reach := _spear_reach()
		if _thrust_t <= windup:
			_melee_thrust = -pull * ease(_thrust_t / windup, 0.6)
		elif _thrust_t <= windup + 0.12:
			_melee_thrust = lerpf(-pull, reach, (_thrust_t - windup) / 0.12)
		elif _thrust_t <= windup + 0.62:
			_melee_thrust = reach * (1.0 - (_thrust_t - windup - 0.12) / 0.5)
		else:
			_thrust_t = -1.0
		# Issue #257: the hitbox follows the spearhead for the ENTIRE
		# lunge (out and pull back) — everything between the wielder and
		# the current tip position is damaged as it is reached. #721
		# rework: the wind-up's negative tip is skipped — the strike is
		# the lunge, not the pull-back.
		if _thrust_t >= 0.0 and _thrust_t > windup:
			_spear_sweep_hit(SPEAR_TIP_BASE + _melee_thrust
					+ HELD_STYLES[3]["size"].x / 2.0)
	if _bat_swing_t >= 0.0:
		_bat_swing_t += delta
		var windup := _melee_windup_time()
		var cocked := -BAT_WINDUP * _melee_power
		var peak := _melee_strike_offset(BAT_RANGE)
		if _bat_swing_t > windup + BAT_SWING_OUT and not _bat_strike_done:
			_bat_strike()
		if _bat_swing_t <= windup:
			_melee_swing = cocked * ease(_bat_swing_t / windup, 0.6)
		elif _bat_swing_t <= windup + BAT_SWING_OUT:
			_melee_swing = lerpf(cocked, peak,
					(_bat_swing_t - windup) / BAT_SWING_OUT)
		elif _bat_swing_t <= windup + BAT_SWING_OUT + BAT_SWING_BACK:
			_melee_swing = peak * (1.0 - (_bat_swing_t - windup
					- BAT_SWING_OUT) / BAT_SWING_BACK)
		else:
			_bat_swing_t = -1.0
			# A whiffed swing releases its turn-effect gate once the
			# animation is over (a hit keeps it until the flights land —
			# see _tick_bat_push / _end_bat_push).
			if _bat_push_left <= 0.0:
				_end_bat_push()
	if _shovel_swing_t >= 0.0:
		_shovel_swing_t += delta
		var windup := _melee_windup_time()
		var cocked := -SHOVEL_WINDUP * _melee_power
		var peak := _melee_strike_offset(SHOVEL_RANGE)
		if _shovel_swing_t > windup + SHOVEL_SWING_OUT \
				and not _shovel_strike_done:
			_shovel_strike()
		if _shovel_swing_t <= windup:
			_melee_shovel_swing = cocked * ease(_shovel_swing_t / windup, 0.6)
		elif _shovel_swing_t <= windup + SHOVEL_SWING_OUT:
			_melee_shovel_swing = lerpf(cocked, peak,
					(_shovel_swing_t - windup) / SHOVEL_SWING_OUT)
		elif _shovel_swing_t <= windup + SHOVEL_SWING_OUT + SHOVEL_SWING_BACK:
			_melee_shovel_swing = peak * (1.0 - (_shovel_swing_t - windup
					- SHOVEL_SWING_OUT) / SHOVEL_SWING_BACK)
		else:
			_shovel_swing_t = -1.0


func _thrust_spear(power := 1.0) -> void:
	# Issue #257: no instant press-time hit — the held spear lunges along
	# the aim axis and damages everything the spearhead actually passes
	# through on its way out AND back (see _spear_sweep_hit, ticked from
	# _physics_process while the thrust animates). Issue #721 rework
	# (owner 2026-11-28): the spear is CHARGED — `power` (0..1, the
	# hold-F charge) scales the wind-up, the pull-back and the lunge
	# reach; the spear goes BACK before the strike and the animation
	# depends on that power.
	_melee_power = clampf(power, 0.0, 1.0)
	_thrust_hit.clear()
	_thrust_t = 0.0


## Issue #257: continuous spear hitbox — called every physics frame while
## the thrust animates. tip_forward is the CURRENT spearhead position along
## the aim axis (held offset 26 + thrust + half the 40 px spear). Everything
## between the wielder and that tip takes SPEAR_DAMAGE once per thrust, so
## the spear damages along its entire trajectory: targets beyond the old
## instant check range are hit when the head reaches them, and targets that
## move into the path mid-attack are caught on the way back.
## Issue #57 (friendly fire) and the issue #133 along-axis rule still apply.
func _spear_sweep_hit(tip_forward: float) -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var dir := _aim().normalized()
	var lateral_tolerance := 12.0
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body == parent or not body.has_method("take_damage") \
					or _thrust_hit.has(body):
				continue
			var offset := body.global_position - global_position
			var forward := offset.dot(dir)
			var lateral := absf(offset.dot(Vector2(-dir.y, dir.x)))
			if forward > 0.0 and forward <= tip_forward and lateral <= lateral_tolerance:
				_thrust_hit.append(body)
				body.take_damage(SPEAR_DAMAGE)
				# Issue #721 (part 4c): the spearhead strike pops the 3c hit
				# star at the contact point — the spear's steel family —
				# so the point landing reads where it bit.
				_pop_melee_hit(global_position + dir
						* minf(forward, tip_forward), 1.3)


## Issue #307: the gravity direction at the WIELDER's current spot — the
## drill is pushed along it (toward the centre of gravity), straight DOWN
## on flat levels, toward the core on radial arenas.
func _gravity_dir() -> Vector2:
	var parent := get_parent()
	if parent != null and parent.has_method("current_gravity"):
		var grav: Vector2 = parent.current_gravity()
		if grav.length_squared() > 0.5:
			return grav.normalized()
	return Vector2.DOWN


## Issue #307: start the jackhammer drill — `power` (0..1, the held-F
## charge fraction) maps to JACKHAMMER_MIN..MAX seconds of drilling.
## Issue #316: the drill runs along the AIM direction (any direction the
## character directs it — not just down), carves destructible ground
## ahead and damages every other character on the way. A lightweight
## node in the turn-effects group keeps the post-shot handover waiting
## until the drill finishes (same gate as projectiles and blast rings).
func _start_jackhammer(power: float = 1.0) -> void:
	_drill_left = lerpf(JACKHAMMER_MIN_TIME, JACKHAMMER_MAX_TIME,
			clampf(power, 0.0, 1.0))
	_drill_dir = _aim().normalized()
	_drill_push.clear()
	_drill_stall = 0.0
	_drill_carve_at = Vector2.INF
	var parent := get_parent()
	_drill_last_pos = parent.global_position if parent != null else Vector2.ZERO
	if _drill_effect == null or not is_instance_valid(_drill_effect):
		_drill_effect = Node.new()
		_drill_effect.name = "JackhammerDrill"
		_drill_effect.add_to_group(TurnController.EFFECT_GROUP)
		if parent != null and parent.get_parent() != null:
			parent.get_parent().add_child(_drill_effect)
	# Issue #495: the drill is audible from its first tick — the loop
	# runs until _end_jackhammer stops it.
	if _drill_player != null:
		_drill_player.play()


## Issue #307: one physics tick of the drill — carve, damage, push, and
## stop early when the wielder grinds against indestructible ground (the
## only way a drill ends before its time — the player cannot cancel it).
func _tick_jackhammer(delta: float) -> void:
	var parent := get_parent() as CharacterBody2D
	if parent == null or not is_instance_valid(parent):
		_end_jackhammer()
		return
	_drill_left -= delta
	_drill_dust_cd = maxf(0.0, _drill_dust_cd - delta)
	_drill_grind_cd = maxf(0.0, _drill_grind_cd - delta)
	# Issue #316: the drill follows the LIVE aim at every tick — steering
	# the aim (W/S) turns a running drill, and there is no cancel: it runs
	# until the time is up or it stalls. On radial arenas the aim frame
	# rides the level gravity, so the tunnel still bends around the core.
	var aimed := _aim()
	if aimed.length_squared() > 0.01:
		_drill_dir = aimed.normalized()
	# Carve a fresh tunnel circle whenever the wielder advanced
	# JACKHAMMER_CARVE_STEP px (bounds the recursive chunk splitting).
	var carve_point := parent.global_position + _drill_dir * 12.0
	if _drill_carve_at.distance_to(carve_point) >= JACKHAMMER_CARVE_STEP:
		_drill_carve_at = carve_point
		var grounds := get_tree().get_nodes_in_group("destructible_ground")
		for ground in grounds:
				var chunk := ground as Node2D
				if chunk != null and is_instance_valid(chunk) \
						and chunk.has_method("apply_blast"):
						chunk.apply_blast(carve_point, JACKHAMMER_RADIUS)
		# Issue #722 (part 4d): contact feedback — a drill that is actually
		# opening ground pops a small 3c dust star at the bore, throttled
		# to ~3/s while the tunnel advances (a stalled drill opens no
		# fresh circles, and a level with no destructible ground pops
		# nothing). Purely visual — no gameplay calculation reads it.
		if not grounds.is_empty() and _drill_dust_cd <= 0.0:
			_pop_melee_hit(carve_point, 0.7)
			_drill_dust_cd = DRILL_STAR_INTERVAL
	_jackhammer_sweep_hit(parent, delta)
	# Push the wielder along the drill direction. Player._physics_process
	# keeps the velocity while the handover freezes input (#316), so this
	# lands in the next move_and_slide.
	parent.velocity = _drill_dir * JACKHAMMER_SPEED
	# No progress for JACKHAMMER_STALL_TIME seconds — the drill hit
	# indestructible ground (or a wall): grind to a halt early.
	if parent.global_position.distance_to(_drill_last_pos) < 0.5:
		_drill_stall += delta
		if _drill_stall >= JACKHAMMER_STALL_TIME:
			_end_jackhammer()
			return
	else:
		_drill_stall = 0.0
	_drill_last_pos = parent.global_position
	if _drill_left <= 0.0:
		_end_jackhammer()


## Issue #307/#316: the drill's contact corridor — every OTHER character
## ahead of the wielder (along the drill direction within the reach,
## inside the tunnel radius laterally). Issue #316 rework: the forward
## window reaches JACKHAMMER_REACH — far enough to catch a TOUCHING
## figure (see the constant) — so a drill aimed at a nearby enemy (not
## into the ground) catches them the moment the bodies press together.
## Issue #363 rework: a met figure is no longer damaged once per drill —
## the drill PUSHES them along the aim direction and grinds them at
## JACKHAMMER_PUSH_DPS per second for as long as the contact lasts.
func _jackhammer_sweep_hit(parent: Node2D, delta: float) -> void:
	var perp := Vector2(-_drill_dir.y, _drill_dir.x)
	var push := _drill_dir * JACKHAMMER_SPEED
	for group in ["player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body == parent or not is_instance_valid(body) \
					or not body.has_method("take_damage"):
					continue
			var hp = body.get("health")
			if hp is int and hp <= 0:
				continue
			var offset := body.global_position - parent.global_position
			var along := offset.dot(_drill_dir)
			var lateral := absf(offset.dot(perp))
			if not (along > -10.0 and along < JACKHAMMER_REACH \
					and lateral <= JACKHAMMER_RADIUS):
				continue
			# Issue #363: push the met figure along the aim direction. An
			# idle figure's own physics clamp (Player/Npc keep only the
			# along-gravity velocity component) eats a plain tangential
			# velocity write, so the drill shoves the body itself every
			# tick — collision-safe for physics bodies via move_and_collide,
			# a direct offset for plain Node2D stand-ins. The velocity write
			# still hands them the shove's momentum for when contact breaks.
			if "velocity" in body:
				body.velocity = push
			var physics := body as PhysicsBody2D
			if physics != null:
				physics.move_and_collide(push * delta)
			else:
				body.global_position += push * delta
			# Issue #363: grind damage — 10 per second, dealt in whole-number
			# chunks as it accrues while the contact lasts.
			var accrued: float = float(_drill_push.get(body, 0.0)) \
					+ JACKHAMMER_PUSH_DPS * delta
			var whole := int(accrued)
			if whole >= 1:
				body.take_damage(whole)
				# Issue #722 (part 4d): grind feedback — a 3c hit star where
				# the bit meets the victim, in the jackhammer's own
				# steel-spark palette, throttled (the chunks land every
				# ~0.1 s). Purely visual.
				if _drill_grind_cd <= 0.0:
					_pop_melee_hit(
							body.global_position - _drill_dir * 8.0, 0.9)
					_drill_grind_cd = DRILL_STAR_INTERVAL
				_drill_push[body] = accrued - whole
			else:
				_drill_push[body] = accrued


## Issue #307: finish the drill — hand the wielder back to normal physics
## (the figure drops into the tunnel it carved) and release the turn-effect
## gate so the handover can pass the turn.
func _end_jackhammer() -> void:
	_drill_left = 0.0
	# Issue #495: the drill loop ends with the drill.
	if _drill_player != null and _drill_player.playing:
		_drill_player.stop()
	var parent := get_parent() as CharacterBody2D
	if parent != null and is_instance_valid(parent):
		parent.velocity = Vector2.ZERO
	if _drill_effect != null and is_instance_valid(_drill_effect):
		_drill_effect.queue_free()
	_drill_effect = null


## Issue #359: true while this wielder charges the railgun (holding F) —
## Player._physics_process slows the walk and shakes the sight then.
func is_charging_railgun() -> bool:
	return _charging and selected_weapon == 6


## Issue #359: the wielder's walk-speed factor — half speed while the
## railgun charges, full speed otherwise. Read by Player._physics_process.
func move_speed_factor() -> float:
	return RAILGUN_CHARGE_SLOWDOWN if is_charging_railgun() else 1.0


## Issue #359: this tick's sight wobble while the railgun charges — a
## small random angle offset (radians), 0.0 when not charging. Read by
## Player._physics_process every physics tick.
func sight_shake() -> float:
	if not is_charging_railgun():
		return 0.0
	return randf_range(-RAILGUN_SIGHT_SHAKE, RAILGUN_SIGHT_SHAKE)


## Issue #722 rework (owner 2026-11-28): the powering tremble's
## AMPLITUDE for a charge fraction — 0 for every other weapon, growing
## linearly from 0 at the press to the jackhammer's/saw's full rev at
## the MAX_CHARGE_TIME hold (the jackhammer's full level equals the
## running drill's own shake, so the rev hands over to the drilling
## tremble without a jump). Pure data for the visual block and the
## #722 regression test.
static func powering_jitter(weapon: int, charge: float) -> float:
	if weapon != 5 and weapon != 9:
		return 0.0
	var full: float = JACKHAMMER_REV_JITTER if weapon == 5 \
			else SAW_REV_JITTER
	return full * clampf(charge, 0.0, 1.0)


## Issue #722 rework: the powering BLADE-JUDDER's angular amplitude
## (radians) — the saw alone judders in rotation (its motor spins the
## blade up while F is held); the jackhammer and every other weapon
## return 0 (the jackhammer's rev is the linear bit chatter instead).
static func powering_wobble(weapon: int, charge: float) -> float:
	if weapon != 9:
		return 0.0
	return SAW_REV_WOBBLE * clampf(charge, 0.0, 1.0)


## Issue #359: railgun damage for a charge fraction — 60 on an instant
## tap, 150 at full charge, lerped between (no range falloff: the damage
## depends on the charge alone, never the distance).
static func railgun_damage(power: float) -> int:
	return int(round(lerpf(RAILGUN_MIN_DAMAGE, RAILGUN_MAX_DAMAGE,
			clampf(power, 0.0, 1.0))))


## Issue #359: the beam's gradient stops — the iridescent rainbow of a
## plain shot lerped toward WHITE as the charge builds (a full charge is
## a pure white beam).
static func railgun_beam_colors(power: float) -> PackedColorArray:
	var stops := PackedColorArray([Color.RED, Color.ORANGE, Color.YELLOW,
			Color.GREEN, Color.CYAN, Color.BLUE, Color.MAGENTA])
	var charged := clampf(power, 0.0, 1.0)
	var out := PackedColorArray()
	out.resize(stops.size())
	for i in stops.size():
		out[i] = stops[i].lerp(Color.WHITE, charged)
	return out


## Issue #359: fire the railgun — an INSTANT hitscan beam along the aim.
## `power` (0..1, the held-F charge fraction) scales the damage (see
## railgun_damage). The ray stops at the FIRST character or terrain it
## meets (collision layers: ground 1, NPC 2, player 8); with nothing in
## the way it runs the full "infinite" range. A gate node in the
## turn-effects group keeps the post-shot handover waiting while the beam
## is still visible (same pattern as the jackhammer drill, #307).
func _fire_railgun(power: float = 1.0) -> void:
	var muzzle := global_position + _aim() * 36.0
	var dir := _aim().normalized()
	var query := PhysicsRayQueryParameters2D.create(muzzle,
			muzzle + dir * RAILGUN_RANGE, 1 | 2 | 8)
	var wielder := get_parent()
	if wielder is CollisionObject2D:
		# The shooter never blocks their own beam.
		var exclude: Array[RID] = [wielder.get_rid()]
		query.exclude = exclude
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	var beam_end := muzzle + dir * RAILGUN_RANGE
	# Issue #720 (part 4b): whether the beam landed on the WORLD (not a
	# damage-taker — figures and items keep their own take_damage
	# feedback, e.g. the warm hit star from Character._pop_hit_star).
	var struck_world := false
	if not hit.is_empty():
		beam_end = hit["position"]
		var target: Object = hit["collider"]
		if target != null and target.has_method("take_damage"):
			target.take_damage(railgun_damage(power), wielder)
		else:
			struck_world = true
	_railgun_beam(muzzle, beam_end, power)
	# Issue #720 (part 4b): the beam's landing on the WORLD pops an icy
	# hit star (the 3c CartoonBlast.hit re-paletted from the same
	# registry flash entry as the muzzle burst) so the boring-in point
	# reads in the weapon's own colors.
	if struck_world:
		var fx_root := get_parent().get_parent()
		if fx_root != null:
			CartoonBlast.pop_hit(fx_root, beam_end, 1.4,
					WeaponVisuals.flash_style(_held_style_index()))
	# Issue #368: the railgun's shot flashes bright at the muzzle.
	# Issue #680 (part 3): the cartoon burst rides the beam direction.
	_muzzle_flash(muzzle, dir)


## Issue #359: the railgun tracer — a thick Line2D from the muzzle to the
## hit point with a rainbow-to-white gradient (see railgun_beam_colors).
## It lingers RAILGUN_BEAM_TIME seconds (fading over the last quarter),
## then frees itself together with the turn-effects gate.
func _railgun_beam(muzzle: Vector2, beam_end: Vector2, power: float) -> void:
	var beam := Line2D.new()
	beam.name = "RailgunBeam"
	beam.width = RAILGUN_BEAM_WIDTH
	beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	var gradient := Gradient.new()
	var stops := railgun_beam_colors(power)
	# Gradient.new() ships two default stops (black->white) — assign the
	# full offset/color arrays instead of add_point to REPLACE them.
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in stops.size():
		offsets.append(float(i) / float(stops.size() - 1))
		colors.append(stops[i])
	gradient.offsets = offsets
	gradient.colors = colors
	beam.gradient = gradient
	var level_root := get_parent().get_parent()
	if level_root == null:
		return
	level_root.add_child(beam)
	beam.global_position = muzzle
	beam.points = PackedVector2Array([Vector2.ZERO, beam.to_local(beam_end)])
	# Issue #368: a bright light at the muzzle fades with the beam.
	var beam_light := ShotLight.create(Color(0.9, 0.9, 1.0), 130.0, 2.4)
	beam.add_child(beam_light)
	beam_light.fade(RAILGUN_BEAM_TIME)
	var gate := Node.new()
	gate.name = "RailgunBeamGate"
	gate.add_to_group(TurnController.EFFECT_GROUP)
	level_root.add_child(gate)
	var tween := beam.create_tween()
	tween.tween_interval(RAILGUN_BEAM_TIME - 0.25)
	tween.tween_property(beam, "modulate:a", 0.0, 0.25)
	tween.tween_callback(gate.queue_free)
	tween.tween_callback(beam.queue_free)
