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
##                     trajectory (out and back), not one instant check
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
## Visuals are plain rectangles built in code — no extra assets.

const ProjectileScript := preload("res://Projectile.gd")
## Issue #114: rockets and grenades spawn as real rigid bodies.
const ProjectileBodyScript := preload("res://ProjectileBody.gd")

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
## shotgun 2, rocket 1, grenade 1, spear 2, mine 1, jackhammer 1, railgun 1)
## and the 3-second delay after every shot during which the character
## cannot shoot.
const SHOTS_PER_TURN: Array = [2, 1, 1, 2, 1, 1, 1]
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

var _facing := 1.0
var _cooldown_left := 0.0
## Issue #101: shots already made this turn by this member, per weapon
## (issue #116: the quota is per weapon so switching after a shot keeps
## the newly selected weapon's own quota).
var _shots_used := [0, 0, 0, 0, 0, 0, 0]

## Issue #101: seconds left before the character may shoot again.
var _shot_delay_left := 0.0
## Issue #114: charge state for the rocket/grenade charged launch.
var _charging := false
var _charge_time := 0.0
var _charge_bar: ColorRect
## Issue #133 (rework): the melee spear uses the HELD spear itself — no
## separate projectile rectangle is spawned. _thrust_t animates a quick
## forward lunge along the aim axis followed by a slow return to the hand.
var _thrust_t := -1.0
## Issue #257: bodies already damaged by the CURRENT thrust — each target
## on the spearhead's path takes the spear hit at most once per thrust.
var _thrust_hit: Array = []
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

## Issue #68: visual of the weapon currently held "in hands".
var _held: ColorRect
var _held_style := -1

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
	return selected_weapon

## Issue #68: size and color of the held weapon per selected weapon index.
## Issue #234: index 4 is the ROCK TOOL held in hands — a gray boulder,
## shown while the rock tool is armed for this member (see _rock_armed).
const HELD_STYLES: Array = [
	{"size": Vector2(26, 6), "color": Color(0.95, 0.85, 0.3, 1)},   # shotgun
	{"size": Vector2(30, 8), "color": Color(0.9, 0.35, 0.15, 1)},   # rocket
	{"size": Vector2(12, 12), "color": Color(0.3, 0.7, 0.3, 1)},    # grenade
	{"size": Vector2(40, 4), "color": Color(0.8, 0.8, 0.9, 1)},     # spear
	{"size": Vector2(14, 14), "color": Color(0.55, 0.5, 0.45, 1)},  # rock (tool)
	{"size": Vector2(14, 14), "color": Color(0.22, 0.24, 0.3, 1)},  # mine (#246)
	{"size": Vector2(10, 18), "color": Color(0.85, 0.85, 0.95, 1)},  # jackhammer (#307)
	{"size": Vector2(46, 4), "color": Color(0.55, 0.85, 1.0, 1)},   # railgun (#359)
]

## Currently selected weapon index (0..5), shared through the inventory HUD.
var selected_weapon := 0


func _ready() -> void:
	_held = ColorRect.new()
	_held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_held)
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
	_held.visible = _is_acting()
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


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	# Issue #101: tick the between-shots delay.
	_shot_delay_left = maxf(0.0, _shot_delay_left - delta)
	# Issue #307: an ACTIVE jackhammer drill ticks before the input logic —
	# it must keep running while the post-shot handover freezes input (the
	# drill IS the effect the handover waits for, see _drill_effect).
	if _drill_left > 0.0:
		_tick_jackhammer(delta)

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
			var grav: Vector2 = parent.current_gravity()
			if grav.length_squared() > 0.5:
				tangent = Vector2(grav.y, -grav.x)
				if tangent.x < 0.0:
					tangent = -tangent
		var walk := parent.velocity.dot(tangent)
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
	# Shotgun and spear keep their instant press-fire behavior.
	# Issue #234: an armed rock is charged too — same F mechanic as the
	# grenade; releasing F throws the rock instead of firing the weapon.
	# Issue #246: the mine (4) is charged too — it is thrown like a grenade.
	# Issue #244: while the handover waits for effects (after a shot or
	# when the timer ran out) the character is BLOCKED — no new charge, no
	# throw/fire; a charge in progress is cancelled without spending
	# anything (the not-can_act branch below).
	var frozen: bool = TurnController.is_input_frozen()
	var rock_armed := _rock_armed()
	var charged := rock_armed or selected_weapon == 1 or selected_weapon == 2 \
			or selected_weapon == 4 or selected_weapon == 5 \
			or selected_weapon == 6  # railgun (#359)
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
	# empty-handed until their own turn comes.
	_held.visible = _is_acting()
	# Issue #67: keep the held weapon aligned with the character's view.
	if _held != null and parent != null and parent.has_method("aim_dir"):
		var aim: Vector2 = parent.aim_dir(_facing, 1.0)
		# Issue #307: while the drill runs the jackhammer points along the
		# drill direction instead of along the aim.
		if _drill_left > 0.0:
			aim = _drill_dir
		var style: Dictionary = HELD_STYLES[_held_style_index()]
		_held.position = aim * 26.0 - style["size"] / 2.0
		# Issue #133: the spear (and every held weapon) rotates to the aim
		# axis instead of staying parallel to the ground.
		_held.pivot_offset = style["size"] / 2.0
		_held.rotation = aim.angle()
		# Issue #133 (rework): thrust offset along the aim axis — fast out,
		# slow back. 0.12 s lunge to SPEAR_RANGE, then 0.5 s return.
		var thrust := 0.0
		if _thrust_t >= 0.0:
			_thrust_t += delta
			if _thrust_t <= 0.12:
				thrust = SPEAR_RANGE * (_thrust_t / 0.12)
			elif _thrust_t <= 0.62:
				thrust = SPEAR_RANGE * (1.0 - (_thrust_t - 0.12) / 0.5)
			else:
				_thrust_t = -1.0
			# Issue #257: the hitbox follows the spearhead for the ENTIRE
			# thrust (lunge out and pull back) — everything between the
			# wielder and the current tip position is damaged as it is
			# reached, instead of one instant press-time check.
			if _thrust_t >= 0.0:
				_spear_sweep_hit(26.0 + thrust + HELD_STYLES[3]["size"].x / 2.0)
		_held.position += aim * thrust
		# Issue #307: the drilling jackhammer shakes in the wielder's hands.
		if _drill_left > 0.0:
			_held.position += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		# Issue #359: so does a CHARGING railgun — the held weapon rattles
		# while the charge builds (the aim itself wobbles via sight_shake).
		if is_charging_railgun():
			_held.position += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))


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


## Issue #68: draw the currently selected weapon in front of the wielder.
func _update_held() -> void:
	if _held == null:
		return
	_held_style = _held_style_index()
	var style: Dictionary = HELD_STYLES[_held_style]
	var size: Vector2 = style["size"]
	_held.size = size
	_held.position = Vector2(_facing * 26.0, 0.0) - size / 2.0
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
		3: _thrust_spear()
		4: _throw_mine(power)
		5: _start_jackhammer(power)
		6: _fire_railgun(power)
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
func _muzzle_flash(at: Vector2) -> void:
	var level_root := get_parent().get_parent()
	if level_root == null:
		return
	ShotLight.flash(level_root, at, Color(1.0, 0.85, 0.45), 110.0, 2.6, 0.12)


func _spawn_projectile(type: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float = 0.0) -> Area2D:
	var projectile := Area2D.new()
	projectile.set_script(ProjectileScript)
	projectile.setup(type, velocity, damage, lifetime, size, color, blast_radius)
	# Issue #57: remember the wielder so shots pass through them.
	projectile.shooter = get_parent()
	projectile.global_position = global_position + _aim() * 36.0
	get_parent().get_parent().add_child(projectile)
	# Issue #368: muzzle flash where the shot leaves the barrel.
	_muzzle_flash(projectile.global_position)
	return projectile


func _fire_shotgun() -> void:
	var aim := _aim()
	for i in 5:
		var spread := deg_to_rad(-8.0 + 4.0 * i)
		var velocity := aim.rotated(spread) * PELLET_SPEED
		_spawn_projectile(Projectile.Type.PELLET, velocity, PELLET_DAMAGE,
			PELLET_LIFETIME, Vector2(10, 4), Color(0.95, 0.85, 0.3, 1))


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


## Issue #114: spawn a physics-driven explosive projectile (rigid body).
func _spawn_body(kind: int, velocity: Vector2, damage: int, lifetime: float,
		size: Vector2, color: Color, blast_radius: float, mass: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.set_script(ProjectileBodyScript)
	body.setup(kind, velocity, damage, lifetime, size, color, blast_radius, mass)
	# Issue #57: remember the wielder so shots pass through them.
	body.shooter = get_parent()
	body.global_position = global_position + _aim() * 36.0
	get_parent().get_parent().add_child(body)
	# Issue #368: muzzle flash where the shot leaves the barrel.
	_muzzle_flash(body.global_position)
	return body


func _thrust_spear() -> void:
	# Issue #257: no instant press-time hit — the held spear lunges along
	# the aim axis and damages everything the spearhead actually passes
	# through on its way out AND back (see _spear_sweep_hit, ticked from
	# _physics_process while the thrust animates).
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
		for ground in get_tree().get_nodes_in_group("destructible_ground"):
				var chunk := ground as Node2D
				if chunk != null and is_instance_valid(chunk) \
						and chunk.has_method("apply_blast"):
						chunk.apply_blast(carve_point, JACKHAMMER_RADIUS)
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
	if not hit.is_empty():
		beam_end = hit["position"]
		var target: Object = hit["collider"]
		if target != null and target.has_method("take_damage"):
			target.take_damage(railgun_damage(power), wielder)
	_railgun_beam(muzzle, beam_end, power)
	# Issue #368: the railgun's shot flashes bright at the muzzle.
	_muzzle_flash(muzzle)


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
