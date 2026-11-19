extends Character
## First NPC (issue #5).
##
## Issue #611: the controller-pattern refactor, slice 1 — every shared
## mechanic (physics tick, gravity frame, health/bar/shield, damage and
## death flow, controller API) moved into the unified Character base
## (scripts/Character.gd). This script is now the figure's SCRIPTED-AI
## brain: the decision code below turns its choices into Character API
## calls (move/jump); the player's input brain lives in Player.gd and
## the RL policy reaches the same API through BotController.gd.
##
## An enemy figure that holds a weapon and tries to hit the player:
## Issue #66: smarter enemy AI — each NPC carries a real Weapon (the same
## arsenal the player team uses) and plays by the rules:
##  - TARGET: the lowest-health opposing figure in attack range (focus
##    fire), otherwise the nearest one, re-evaluated every frame;
##  - AIM: a view angle like the player (aim_dir) instead of flat shots;
##  - WEAPONS: switched by distance — spear up close, shotgun at medium
##    range, rocket farther, grenade lobbed at the farthest targets.
##    Issue #546: the WHOLE arsenal is in play — each distance band
##    rotates through every weapon that fits it (melee: spear/bat/
##    jackhammer; flat: shotgun/pistol; open lane: rocket/railgun;
##    ballistic: grenade/mine/saw, railgun on a clear line), and the tools
##    too: a badly hurt AI can hand its turn to the healthiest teammate
##    (Switch) and the ballistic band sometimes lobs the Rock tool
##    instead of a weapon (it crumbles into fresh ground — cover).
## The main goal stays: eliminate all other teams.

const WeaponScript := preload("res://scripts/Weapon.gd")

## Issue #308: only the FOCUS-FIRE window (prefer the weakest figure this
## close); targeting and firing themselves are level-wide now.
const ATTACK_RANGE := 500.0
const KEEP_DISTANCE := 140.0
## Issue #66: aim slew speed (rad/s) and per-weapon range bands.
const SPEAR_RANGE_NPC := 90.0
## Issue #430: raised to the shotgun's real flight range (900 px/s *
## 0.5 s = 450; the band claimed 360 while pellets only flew 315).
const SHOTGUN_RANGE_NPC := 450.0
const ROCKET_RANGE_NPC := 620.0

## Issue #35: team coordination constants.
const FLANK_SPACING := 110.0
const SEPARATION := 90.0

## Issue #121: which side this AI fights for. "enemy" (default) behaves
## exactly as before; "player" places the figure in the player team, so a
## level can stage a computer-vs-computer duel the user only spectates.
@export var team: String = "enemy"

## Issue #137: AI difficulty — 0 = easy, 1 = normal, 2 = hard. Scales
## aim slew speed and the pause between shots (set by the level
## configuration menu via GameConfig).
@export_range(0, 2) var difficulty := 1

## Issue #180: AI friendly-fire, from the TEAM configuration — 0 = always
## avoid hitting teammates, 10 = does not care at all (in between the
## avoidance checks are applied probabilistically per shot).
@export_range(0, 10) var ai_friendly_fire := 0

var _target: Node2D
var _cooldown_left := 0.0
var _visual: ColorRect
## Issue #226: a shape body drawn instead of the ColorRect body when
## the team shape is not a square (the modular character since #560).
var _shape_visual: Control

## Issue #277 rework 2 ("the character is flying, but it must be
## grounded"): jump cool-down. The old trigger re-fired the jump on EVERY
## tick an NPC touched ground, so an NPC blocked beside its target (or
## with the target "above" it) hop-spammed ~2/s and spent half its turn
## airborne — "flying". With the cool-down a blocked NPC hops at most
## once a second and otherwise stays grounded, aims and shoots.
const JUMP_COOLDOWN := 1.0
var _jump_left := 0.0
## Issue #641: how long the AI has kept pushing while the achieved motion
## along the walking tangent stayed collapsed — a vertical wall counts as
## floor now, so is_on_wall() can't be the blocked trigger anymore.
var _blocked_time := 0.0
var _flank_slot := 0.0  # Per-instance offset so team members spread out.
## Issue #221: per-turn AI state — a tool already spent this turn's
## action, the "nothing useful left" watchdog and the last position used
## to detect REAL movement (a blocked walk does not count).
var _tool_used := false
var _turn_stall := 0.0
var _last_pos := Vector2.ZERO
var _active_last := false
## Issue #137: per-difficulty aim slew and between-shot pause.
const AIM_SPEED_MULT := [0.5, 1.0, 1.5]
const FIRE_PAUSE := [2.0, 0.9, 0.0]
## Issue #120: grenade blasts are lethal at point-blank — never lob one
## that would land inside our own blast radius. Below this distance the
## NPC holds grenade fire (the spear closes the gap instead).
const GRENADE_MIN_RANGE := 130.0
## Issue #120: below this health fraction the AI kites — backs away from
## the target instead of walking deeper into danger, while still shooting.
## Issue #221: raised from 0.3 — the hurt AI now plays a TOOL (shield or
## teleport) and keeps its distance instead of trading blows.
const KITE_HEALTH_FRACTION := 0.35
## Issue #221: tool play — a badly hurt AI (health fraction at or below
## KITE_HEALTH_FRACTION) defends itself with its tools instead of firing:
## TELEPORT away when an enemy is breathing down its neck, SHIELD when
## the threat is merely near. The tool spends the turn's action (tool OR
## weapon, mirroring the player rule of issue #207). Easy AI (difficulty
## 0) fights as before.
const TOOL_THREAT_RANGE := 360.0
const TELEPORT_THREAT_RANGE := 170.0
## Issue #546: the ROCK tool's rotation slot — every ROCK_ROTATION-th
## acting window the ballistic band plays the rock instead of the
## picked weapon: the rock crumbles into destructible ground where it
## lands, building cover in the enemy's lane. Like every tool it
## consumes this character's turn action (tool OR weapon, issue #207),
## so one rock = this figure's whole turn. Deterministic on purpose:
## the band picks and the rock slot all key off _pick_rotation, so a
## fresh figure's first fight is always the classic weapon pick.
const ROCK_ROTATION := 4
## Issue #221: seconds of "nothing useful left" (not really moving, not
## firing, weapon idle) before the AI ends its own turn early instead of
## standing around until the turn timer runs out.
const STALL_SKIP_AFTER := 3.0
## Issue #221: inside this band only the spear or the flat shotgun are
## allowed — a grenade or rocket detonating that close self-harms.
const SHOTGUN_CLOSE_NPC := 200.0
## Issue #66: the weapon carried by this NPC (created in _ready).
var _weapon: Node2D

## Issue #481: this NPC already fired this turn — the weapon choice is
## locked until its next turn begins. The player-side rule of issues
## #131/#143 (the FIRST shot of the turn fixes the weapon for that
## character) now applies to the computer too: the distance-based
## re-pick must never swap guns after a shot has left, so an AI can no
## longer thrust the spear and finish the same turn with the shotgun.
var _weapon_locked := false

## Issue #546: which candidate of the current distance band this figure
## fights with — advanced by one at every CLOSED acting window (the
## deactivation edge in _control), so each of the figure's turns
## takes the NEXT weapon of whatever band it fights in. Deterministic:
## a fresh figure starts at rotation 0 (the classic first pick of each
## band), and over a round the whole arsenal cycles through its hands.
var _pick_rotation := 0


func _init() -> void:
	# Issue #611: display_name/team_color/team_shape defaults live in the
	# shared Character base (the player-side look); the NPC's classic
	# defaults are applied here — scene-authored exports still win.
	display_name = "Enemy"
	team_color = Color(0.75, 0.2, 0.45, 1)


## Issue #226: apply the team's body shape after the fact (called by
## GameConfig.apply once the level staged the teams).
func set_team_shape(value: String) -> void:
	team_shape = value
	_apply_team_shape()
	_attach_animator()


## Issue #558: point the procedural animator at whichever body visual is
## active — the modular character silhouette or the ColorRect square
## (mirrors Player.gd; created once, re-targeted after every shape change).
func _attach_animator() -> void:
	var visual: Control = null
	if _shape_visual != null and _shape_visual.visible:
		visual = _shape_visual
	elif _visual != null and _visual.visible:
		visual = _visual
	if visual == null:
		return
	if _animator == null:
		_animator = CharacterAnimator.new()
		_animator.name = "CharacterAnimator"
		add_child(_animator)
	_animator.setup(self, visual)


## Issue #556: every NPC wears the modular expressive character (the
## issue #557 component) as its body — square teams included (mirrors
## Player.gd). The look (team color + silhouette + the member's
## personality) is applied on EVERY call, so re-runs after a team-shape
## change (set_team_shape / GameConfig) restyle the SAME node instead of
## keeping the first shape.
func _apply_team_shape() -> void:
	if _visual == null:
		return
	if _shape_visual == null:
		_visual.visible = false
		_shape_visual = load("res://scripts/ModularCharacterVisual.gd").new()
		_shape_visual.name = "VisualShape"
		_shape_visual.offset_left = -32.0
		_shape_visual.offset_top = -32.0
		_shape_visual.offset_right = 32.0
		_shape_visual.offset_bottom = 32.0
		add_child(_shape_visual)
	if _shape_visual.has_method("apply_team_look"):
		_shape_visual.call("apply_team_look", team_color, team_shape,
				get_index())
	else:
		_shape_visual.set_shape(team_shape)
		_shape_visual.set_shape_color(team_color)
	# Issue #282: the body visual is appended after the Weapon node
	# (Npc._ready adds the weapon last, but GameConfig.apply calls
	# set_team_shape AFTER _ready) — that drew the held weapon/tool BEHIND
	# the figure. Keep the Weapon the last child; it draws in front.
	_keep_weapon_in_front()


## Issue #60: computer figures keep their TEAM color in the health bar
## fill (the base's player-side fill turns red as health drops).
func _bar_fill_color(_ratio: float) -> Color:
	return team_color


## Issue #221 heritage: the Shield bubble's box — the NPC-side geometry.
func _shield_offsets() -> Vector4:
	return Vector4(-BAR_WIDTH / 2.0 - 4.0, -44.0 - BAR_HEIGHT - 8.0,
			BAR_WIDTH / 2.0 + 4.0, -44.0 + 24.0)


func _ready() -> void:
	# Issue #39 rework: characters collide with each other (world + both
	# character layers) but never push — a walking figure is simply BLOCKED
	# by another figure (issue #144: one character must not move or
	# displace another during its move).
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	# Issue #155: characters are never platforms for each other (see
	# Player.gd) — a walking figure cannot carry an enemy standing on it.
	platform_floor_layers = 1
	if team == "enemy":
		add_to_group("enemy")
	add_to_group("enemy_team" if team == "enemy" else "player_team")
	_apply_team_color()
	# Stable per-instance flank slot (index within the enemy team).
	var members := get_tree().get_nodes_in_group("enemy_team")
	_flank_slot = float(members.find(self)) - (float(members.size() - 1) / 2.0)
	var shape := CollisionShape2D.new()
	# Issue #154: capsule instead of a circle — a round figure wedges into
	# the notch between the ground and another figure/wall and gets stuck;
	# the flat capsule sides slide along obstacles instead.
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	# Issue #406: the body push-box is 10% shorter vertically (64 -> 57.6)
	# so figures brush past each other's shoulders more easily.
	capsule.height = 57.6
	shape.shape = capsule
	add_child(shape)

	# Issue #226 rework: Level2/3/4 author the NPC body ColorRect in the
	# scene ("NpcVisual") — ADOPT it as the one body instead of stacking a
	# second code-made square: a non-square team shape hid only the code
	# rect, so the figure wore square AND circle shapes simultaneously.
	for child in get_children():
		var authored := child as ColorRect
		if authored != null:
			_visual = authored
			break
	if _visual == null:
		_visual = ColorRect.new()
		_visual.offset_left = -32.0
		_visual.offset_top = -32.0
		_visual.offset_right = 32.0
		_visual.offset_bottom = 32.0
		add_child(_visual)
	_visual.color = team_color
	_apply_team_shape()
	_attach_animator()

	_build_health_bar()
	# Issue #252: debug-mode visuals — HP number, damage popup, arrow.
	DebugInfo.attach(self)
	DebugInfo.update_hp(self, health, MAX_HEALTH)
	# Issue #66: give this NPC the standard weapon so it can use the full
	# arsenal (shotgun / rocket / grenade / spear), not just plain bullets.
	if get_node_or_null("Weapon") == null:
		_weapon = WeaponScript.new()
		_weapon.name = "Weapon"
		add_child(_weapon)
	else:
		_weapon = get_node("Weapon")


## Issue #611: the SCRIPTED-AI brain — the whole decision flow of the
## old Npc._physics_process, now issuing Character API calls (move/jump)
## inside the base's shared tick.
func _control(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_jump_left = maxf(0.0, _jump_left - delta)
	# Issue #65/#121: only the active character of the team on turn may
	# act — regardless of which team that is, so AI vs AI duels work.
	# Issue #183: the team check is explicit — an NPC must never act while
	# the OPPONENT's turn is active, even if a stale/lost active_member
	# still points at it (that desync let the computer move and shoot
	# during the player's move).
	var my_team: String = TurnController.team_id_of(self)
	# Issue #221: track the activation edge — the first tick of this NPC's
	# OWN turn runs the tool decisions and resets the per-turn AI state.
	var active: bool = not TurnController.game_over \
			and TurnController.active_team == my_team \
			and TurnController.active_member == self \
			and not TurnController.is_input_frozen()
	if active and not _active_last:
		_begin_my_turn()
	if _active_last and not active:
		# Issue #546: this figure's acting window just closed — its next
		# one rotates to the next weapon of the distance band (see
		# _pick_rotation), so consecutive turns cycle the whole arsenal.
		_pick_rotation += 1
	_active_last = active
	if not active:
		# Issue #546: a running jackhammer drill keeps pushing this NPC —
		# the weapon re-sets the drill velocity every tick
		# (Weapon._tick_jackhammer, the same ride Player.gd grants since
		# #316), so the idle branch must not zero the tangential component
		# while the drill runs.
		if _weapon == null or not _weapon.is_drilling():
			# Issue #250 rework: zero the walk along the surface (the tangent
			# frame), keep the fall/jump component along gravity.
			move(0.0)
		return

	_target = _nearest_opponent()
	if _target == null:
		# Issue #58: stop instantly instead of gliding to a halt
		# (tangent frame — see the walk step below).
		move(0.0)
		# Issue #221: nothing left to fight — hand the turn over at once
		# instead of burning the whole timer (the win check follows).
		TurnController.skip_turn(self)
		return

	# Aim at the chosen target, offset by this NPC's flank slot so the
	# team surrounds the opponents instead of forming a single column.
	var goal := _target.global_position \
			+ Vector2(KEEP_DISTANCE + absf(_flank_slot) * FLANK_SPACING, 0.0) \
			* (1.0 if _flank_slot >= 0.0 else -1.0)
	var to_target := goal - global_position
	var distance := _target.global_position.distance_to(global_position)

	# Issue #66: slew the view angle toward the target so the weapon aims
	# where the NPC looks (positive angle raises the muzzle).
	# Issue #277: measure the target in the CURRENT gravity frame — the aim
	# rotates with radial gravity, so world-x/y deltas would slew the view
	# toward an angle that no longer points at the target. Flat and
	# center-line levels: identical to the old world-axis formula.
	var aim_offset := _target.global_position - global_position
	var vertical := aim_offset.dot(_aim_grav)
	# Issue #147: slew the aim onto the ACTUAL target (not the flank goal)
	# so the hold-fire gate below can actually converge.
	var desired_angle := atan2(-vertical, maxf(absf(aim_offset.dot(_aim_tangent)), 1.0))
	view_angle = move_toward(view_angle, clampf(desired_angle, -VIEW_MAX, VIEW_MAX), VIEW_SPEED * AIM_SPEED_MULT[difficulty] * delta)

	var direction := 0.0
	if absf(to_target.x) > 16.0:
		direction = signf(to_target.x)
	# Separation: back off from other enemies we are stacking on.
	for other in get_tree().get_nodes_in_group("enemy_team"):
		if other == self:
			continue
		var away: float = global_position.x - other.global_position.x
		if absf(away) < SEPARATION and absf(global_position.y - other.global_position.y) < 40.0:
			direction += signf(away) * 0.5
	# Issue #120: kite at low health — back away from the target instead of
	# pressing into it, while still shooting from the safety of range.
	if _wants_retreat(distance):
		direction = -signf(to_target.x)
	# Issue #221: after a defensive tool the AI does not re-engage — it
	# holds its safe distance and lets the stall watchdog hand the turn
	# over once nothing useful is left.
	if _tool_used and not _wants_retreat(distance):
		direction = 0.0
	# Issue #641: the achieved motion along the walking tangent BEFORE this
	# tick's move() overwrites the velocity with fresh intent — pressing
	# into a vertical wall zeroes it (the wall is floor for the physics
	# now, and the slide response projects the speed into the surface),
	# while a walkable incline keeps a cos-component of SPEED.
	var achieved_tangent_speed := absf(velocity.dot(_aim_tangent))

	# Issue #250 rework: walk in the gravity frame's tangent (see above) —
	# the AI keeps its world-x heuristics, but the step itself follows the
	# surface instead of launching the figure off it.
	move(clampf(direction, -1.0, 1.0))

	# Issue #641: blocked = still pushing while the achieved tangent speed
	# stays collapsed for a beat — the perpendicular wall is floor for the
	# physics now, so is_on_wall() alone would never wake the wall jump.
	if direction != 0.0 and achieved_tangent_speed < _move_speed() * 0.1:
		_blocked_time += delta
	else:
		_blocked_time = 0.0

	# Jump when blocked or when the target is clearly above us.
	# Issue #277 rework 2 ("the character is flying, but it must be
	# grounded"): "clearly above" is measured in the CURRENT gravity frame
	# (along the frame's up, -_aim_grav), not in world y — on the disc arena
	# the player team sits world-above from most rim positions, so the old
	# world-y test ((target.y - y) * gravity_dir < -80) made every arriving
	# NPC jump for the sky instead of standing and fighting. Flat and
	# center-line levels keep exactly the old trigger (the frame's up IS the
	# world ±y axis there, gravity_dir included); plus the jump now cools
	# down (JUMP_COOLDOWN) so a blocked NPC hops deliberately, not twice a
	# second.
	var target_above := (_target.global_position - global_position) \
				.dot(_aim_grav) < -80.0
	if _jump_left <= 0.0 and is_on_floor() \
				and (is_on_wall() or _blocked_time > 0.25 or target_above):
		# Issue #202: jump must point AWAY from the floor — Character.jump.
		if jump():
			_jump_left = JUMP_COOLDOWN

	# Issue #66: pick the weapon by distance and take a shot when in range.
	# Issue #147: hold fire until we actually face the target and the view
	# angle has slewed onto it — no more blind flat shots while the aim is
	# still turning (cooldown stays at 0, so the shot fires as soon as the
	# aim lines up).
	# Issue #308: the computer sees an enemy at ANY point of the level —
	# the old `distance <= ATTACK_RANGE` cap left far figures untouchable,
	# so the AI could only walk (and burned its turn standing when the way
	# was blocked). _pick_weapon resolves EVERY distance — the ballistic
	# grenade is the far band — so the gate is aim + cooldown only.
	if _cooldown_left == 0.0 and _aim_ready() and not _tool_used:
		_pick_weapon(distance, absf(_target.global_position.y - global_position.y))
		# Issue #546: sometimes the ballistic band plays the ROCK tool
		# instead of the picked weapon — cover-building terrain play.
		if not _try_throw_rock():
			_shoot()
		_cooldown_left = FIRE_PAUSE[difficulty]

	# Issue #221: stall watchdog — ended turns instead of idle standing.
	_update_stall(delta)


## Issue #221: the AI's own turn just began — reset the per-turn state
## and play a TOOL when badly hurt near the enemy: teleport out of
## point-blank trouble, otherwise raise the shield. The tool spends the
## turn's action (tool OR weapon, like the player rule of issue #207),
## so a hurt AI retreats and hands over instead of trading blows it
## would lose. Easy AI (difficulty 0) skips the tool play.
func _begin_my_turn() -> void:
	_tool_used = false
	# Issue #481: a fresh turn unlocks the weapon choice — the lock is
	# per turn, exactly like the player's WeaponInventory lock reset.
	_weapon_locked = false
	_turn_stall = 0.0
	_last_pos = global_position
	if difficulty < 1 \
			or float(health) > float(MAX_HEALTH) * KITE_HEALTH_FRACTION:
		return
	var enemy := _nearest_opponent()
	if enemy == null:
		return
	var distance := global_position.distance_to(enemy.global_position)
	if distance <= TELEPORT_THREAT_RANGE and _try_teleport_away(enemy):
		_tool_used = true
		return
	if distance <= TOOL_THREAT_RANGE:
		set_shielded(true)
		_tool_used = true
		return
	# Issue #546: hurt but not under an immediate threat — the SWITCH
	# tool: hand this member's turn to the team's healthiest teammate
	# (the classic switch-out) instead of fighting on at low health.
	_try_switch_to_healthiest()


## Issue #221: TELEPORT tool — hop away from the threatening enemy to
## the nearest collision-free spot that keeps every opponent at a safe
## distance. Returns true when a hop was made.
func _try_teleport_away(enemy: Node2D) -> bool:
	var away := signf(global_position.x - enemy.global_position.x)
	if away == 0.0:
		away = 1.0 if randf() < 0.5 else -1.0
	var space := get_world_2d().direct_space_state
	for dist in [260.0, 330.0, 190.0, 400.0, 130.0]:
		for lift in [0.0, -80.0, 80.0]:
			var candidate := Vector2(global_position.x + away * dist,
					global_position.y + lift)
			if not _teleport_spot_free(space, candidate):
				continue
			if _nearest_opponent_distance_at(candidate) < TELEPORT_THREAT_RANGE:
				continue
			global_position = candidate
			velocity = Vector2.ZERO
			# Issue #518: re-anchor the walking/aiming frame at the hop
			# destination (same rule as the player teleport tool) — the hop
			# must not carry the old spot's tangent orientation over.
			reanchor_gravity_frame()
			# Issue #475: the NPC hop uses the same teleport sound as the
			# player tool (ToolInventory owns the player).
			ToolInventory.play_teleport_sound()
			return true
	return false


## Issue #221: true when the point is clear of solid world geometry
## (layer 1 = terrain, layer 8 = borders — characters may be overlapped,
## the body slides out of them).
func _teleport_spot_free(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1 | 8
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_point(query, 1).is_empty()


## Issue #221: distance from `point` to the closest living opponent
## (INF when there is none).
func _nearest_opponent_distance_at(point: Vector2) -> float:
	var best := INF
	for group in ["player", "team", "player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node2D
			if candidate == null or _same_side(candidate):
				continue
			var d: float = point.distance_to(candidate.global_position)
			if d < best:
				best = d
	return best


## Issue #221: the stall watchdog — when the AI is not really moving and
## its weapon is idle, it has nothing useful left to do: after
## STALL_SKIP_AFTER seconds it ends its own turn (the AI analogue of the
## player's Tab skip, #102) instead of standing idle until the timer
## runs out. REAL movement counts (distance from the last tick), so a
## walk blocked by a wall still accumulates the stall.
func _update_stall(delta: float) -> void:
	var moved := global_position.distance_to(_last_pos) > 0.5
	_last_pos = global_position
	if moved or (_weapon != null and _weapon.is_busy()):
		_turn_stall = 0.0
		return
	_turn_stall += delta
	if _turn_stall >= STALL_SKIP_AFTER:
		_turn_stall = 0.0
		TurnController.skip_turn(self)


## Issue #147: true when the shot direction matches the target — the NPC
## is turned toward it and the view angle is within tolerance of the
## direct aim angle at the target.
const AIM_TOLERANCE := 0.12  # rad

func _aim_ready() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var to_target := _target.global_position - global_position
	# Facing: never fire away from the target (Issue #277: measured along
	# the gravity tangent — the walking/aim axis — not the world x axis).
	var facing: float = _weapon._facing if _weapon != null else 1.0
	var along := to_target.dot(_aim_tangent)
	if signf(along) != 0.0 and signf(facing) != signf(along):
		return false
	# Aim: the slewed view angle must be on the direct line to the target
	# (Issue #277: measured in the current gravity frame).
	var desired := atan2(-to_target.dot(_aim_grav), maxf(absf(along), 1.0))
	return absf(view_angle - clampf(desired, -VIEW_MAX, VIEW_MAX)) <= AIM_TOLERANCE



## Issue #120: true when this NPC is badly hurt and the target is close
## enough that pressing the attack is riskier than falling back.
func _wants_retreat(distance: float) -> bool:
	if health > int(float(MAX_HEALTH) * KITE_HEALTH_FRACTION):
		return false
	# Issue #221: the hurt AI keeps its distance as soon as the threat is
	# merely NEAR (not already on top of it) — it played a tool this turn
	# and now disengages instead of trading blows.
	return distance < TOOL_THREAT_RANGE



## Issue #66 rework: pick an opposing figure — the lowest-health one within
## attack range (focus fire), otherwise the nearest one. Re-evaluated every
## frame, so when a target dies the NPC naturally switches to another.
func _nearest_opponent() -> Node2D:
	# Issue #446: the team blackboard's shared FOCUS TARGET wins while it
	# is still a living opponent — the whole team converges on the same
	# figure, and each bot needs only its OWN team id (TurnController's
	# team_id_of), never a reference to any other bot.
	var shared: Node2D = TeamBlackboard.get_focus_target(
			TurnController.team_id_of(self))
	if shared != null and not _same_side(shared):
		var shared_hp = shared.get("health")
		if shared_hp == null or float(shared_hp) > 0.0:
			return shared
	var fallback: Node2D = null
	var nearest_distance := INF
	var focus: Node2D = null
	var best_health := INF
	for group in ["player", "team", "player_team", "enemy_team"]:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node2D
			if candidate == null:
				continue
			# Issue #121: never target a figure from our own side.
			if _same_side(candidate):
				continue
			# Issue #221: dying (0-health) figures are skipped outright.
			var hp = candidate.get("health")
			if hp != null and float(hp) <= 0.0:
				continue
			var d := global_position.distance_to(candidate.global_position)
			# Track the plain nearest figure as the fallback target
			# (issue #221: the TRUE nearest — the old code kept the
			# first-seen figure and ignored a closer enemy).
			if d < nearest_distance:
				nearest_distance = d
				fallback = candidate
			# Focus fire: prefer the weakest figure in attack range.
			if d <= ATTACK_RANGE and hp != null and float(hp) < best_health:
				best_health = float(hp)
				focus = candidate
	return focus if focus != null else fallback


## Issue #121: true when the figure fights for the same team as we do.
## Issue #228: a team death-match — every AI team is its OWN side, so a
## computer figure only spares figures of its own team color (and, for
## the player team, other player figures). Computers on different teams
## fight each other, not just the player.
func _same_side(other: Node2D) -> bool:
	if other == self:
		return true
	if is_in_group("player_team"):
		return other.is_in_group("player_team")
	if not other.is_in_group("enemy_team"):
		return false
	var mate_color = other.get("team_color")
	return mate_color is Color and team_color == mate_color


## Issue #66: choose the weapon that fits the distance to the target.
## Issue #546: every band rotates through ALL the weapons that fit it
## (the band's candidate at this figure's rotation, filtered by the
## team budget), so the computer exercises the whole arsenal — mine,
## jackhammer, railgun, pistol and baseball bat included — instead of
## the four classic guns. The spear (infinite uses) always ends up
## affordable, so a pick never fails.
func _pick_weapon(distance: float, height_diff: float = 0.0) -> void:
	if _weapon == null:
		return
	# Issue #481: a shot already left this NPC's hands this turn — the
	# weapon in hands stays. The first-shot lock of issues #131/#143 is
	# the player's rule; the computer re-picking by distance on every
	# attempt silently bypassed it (spear thrust, then two shotgun shots
	# in one turn on LevelDuelBig). While locked, the re-pick is a no-op.
	if _weapon_locked:
		return
	var candidates: Array
	if distance <= SPEAR_RANGE_NPC:
		# Issue #546: the melee band — spear thrust, baseball bat swing
		# (BAT_RANGE) or a jackhammer grind down the adjacent enemy.
		candidates = [3, 8, 5]
	elif distance <= SHOTGUN_CLOSE_NPC:
		# Issue #221 keeps applying: at close range only flat/projectile
		# weapons — never a blast that would self-harm. Issue #546 adds
		# the pistol (straight bullet, no spread) beside the shotgun.
		candidates = [0, 7]
	elif distance <= SHOTGUN_RANGE_NPC and height_diff <= 60.0:
		candidates = [0, 7]  # shotgun / pistol (flat line of sight only)
	elif distance <= ROCKET_RANGE_NPC and height_diff <= 40.0 \
			and not _teammate_blocks_shot():
		# Issue #221: the flat rocket finally gets used — it reaches farther
		# than the pellets on an open lane with no teammate in the corridor.
		# Issue #546: the railgun alternates on the same open lane (the
		# hitscan beam shares the rocket's flat, unobstructed corridor).
		candidates = [1, 6]
	else:
		# Issue #99: prefer the ballistic grenade for long range or any
		# height difference — its arc reaches targets over terrain, while a
		# straight rocket just hits the platform underside (or the blast
		# catches the shooter's own team below instead of the target).
		# Issue #546: the mine joins the ballistic band (same lob, area
		# denial where it lands) and the railgun fits too when the straight
		# line to the target is clear of world geometry. Issue #570: the
		# circular saw lobs the same way — it lands on the target and the
		# suction drags it into the blade.
		candidates = [2, 4, 9]
		if _line_clear(_target):
			candidates.append(6)
	_weapon.selected_weapon = _pick_affordable(candidates)


## Issue #546: the band's candidate at this figure's rotation — the
## team's weapon budget must still have a use of it (the spear is always
## affordable, infinite uses), so rotation never picks a gun that cannot
## fire. Rotation 0 is the classic first pick of the band.
func _pick_affordable(candidates: Array) -> int:
	var team := TurnController.team_id_of(self)
	var affordable: Array = candidates.filter(
			func(w): return WeaponInventory.can_spend_weapon(team, w))
	if affordable.is_empty():
		return 3  # spear — infinite uses, always something to fight with
	return int(affordable[_pick_rotation % affordable.size()])


## Issue #546: is the straight segment to `fig` clear of world geometry
## (layer 1 ground, destructible and indestructible alike)? The railgun
## beam stops at the first terrain it meets, so the far band only gets
## the railgun candidate while a clear line exists.
func _line_clear(fig: Node2D) -> bool:
	if fig == null or not is_instance_valid(fig) or not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters2D.create(
			global_position, fig.global_position, 1)
	return get_world_2d().direct_space_state \
			.intersect_ray(query).is_empty()


## Issue #66: fire through the carried Weapon (it owns the cooldown,
## the projectile types and the shooter pass-through from issue #57).
## Issue #481: returns whether a shot really left — every hold-fire
## path reports false, so the caller (and the tests) can tell a locked
## held shot from a committed one.
func _shoot() -> bool:
	if _weapon == null:
		return false
	# Issue #99: hand the current target to the weapon so grenades are
	# lobbed ballistically at it (see Weapon._fire_grenade).
	_weapon.npc_target = _target
	# Issue #180: the friendly-fire parameter gates the avoidance checks —
	# care = 10 - friendly_fire; the checks are skipped with probability
	# friendly_fire / 10 per shot (always run at 0, never at 10).
	var cares := randf() * 10.0 >= ai_friendly_fire
	# Issue #99: never fire a straight-line weapon through a teammate — the
	# projectile hits the teammate first (friendly fire since #57) and the
	# enemy team wipes itself out while the players stay untouched. Switch
	# to the ballistic grenade, which arcs over the row; at spear-close
	# range the grenade blast would catch our own team, so hold fire there
	# (the separation steering opens the line instead).
	if cares and _weapon.selected_weapon != 2 and _teammate_blocks_shot():
		if _target != null and is_instance_valid(_target) \
				and global_position.distance_to(_target.global_position) > 160.0:
			# Issue #481: locked to the gun already fired — hold fire instead
			# of arcing the grenade over the teammate.
			if not _switch_weapon(2):
				return false
		else:
			return false
	# Issue #120: never lob a grenade (or, issue #546, throw a MINE — the
	# same lob and a grenade-sized blast) that would land inside our own
	# blast radius — hold fire at point-blank range instead (and switch to
	# the spear so the next in-range tick closes the gap rather than
	# re-throwing).
	if cares and (_weapon.selected_weapon == 2 or _weapon.selected_weapon == 4) \
				and _grenade_unsafe():
		# Issue #481: the swap is refused while locked — a locked AI holds
		# fire at point-blank (the stall watchdog ends its turn) instead of
		# trading the locked grenade for the spear.
		_switch_weapon(3)
		return false
	# Issue #305: never hand the weapon a gun the team can't pay for —
	# the grenade fallback above (and any stale pick) may be spent.
	if not WeaponInventory.can_spend_weapon(
			TurnController.team_id_of(self), _weapon.selected_weapon):
		# Issue #481: locked to a gun the team can no longer pay for — hold
		# fire rather than swapping to the spear; nothing useful is left, so
		# the stall watchdog hands the turn over.
		if not _switch_weapon(3):
			return false
	# Issue #481: lock the choice the moment a shot REALLY leaves —
	# npc_fire() reports the commit (it can refuse on quota, cooldown or
	# budget), and a refused order must not freeze the choice it never
	# fired with.
	var fired: bool = _weapon.npc_fire()
	if fired:
		_weapon_locked = true
	return fired


## Issue #481: change the held weapon — refused once this NPC has fired
## this turn (the one-weapon-per-turn rule of issues #131/#143, applied to
## the AI: no weapon change after the use). Returns true when the switch
## actually happened.
func _switch_weapon(id: int) -> bool:
	if _weapon_locked:
		return false
	_weapon.selected_weapon = id
	return true


## Issue #546: the ROCK tool. Decided in the fire gate: on its rotation
## slot (see ROCK_ROTATION) when the picked weapon sits in the ballistic
## band (grenade/mine), the AI lobs the rock at the target instead of
## firing — the rock crumbles into destructible ground where it lands
## (Weapon.throw_rock / ProjectileBody), building cover in the enemy's
## lane. Returns true when the rock left the hand.
func _try_throw_rock() -> bool:
	if difficulty < 1 or _weapon == null:
		return false
	if not (_weapon.selected_weapon == 2 or _weapon.selected_weapon == 4):
		return false
	if _pick_rotation % ROCK_ROTATION != ROCK_ROTATION - 1:
		return false
	return _throw_rock_tool()


## Issue #546: the actual rock throw — budget check + launch + the
## turn-action spend. Split from the rotation gate above so the throw
## itself stays deterministically testable.
func _throw_rock_tool() -> bool:
	if not WeaponInventory.can_spend_tool(
			TurnController.team_id_of(self), ToolInventory.TOOL_ROCK):
		return false
	_weapon.throw_rock(1.0)
	# The rock IS this character's action for the turn (tool OR weapon,
	# issue #207): no weapon may follow it, and the weapon choice freezes
	# so the distance re-pick never swaps away from the spent turn.
	_tool_used = true
	_weapon_locked = true
	DebugInfo.log("%s throws a rock" % display_name)
	return true


## Issue #546: the SWITCH tool — a badly hurt AI (the caller's kite
## branch) hands the REST of its turn to the team's healthiest living
## teammate, exactly what a player uses the Switch tool for: the hurt
## figure sits the action out and the healthy one fights. Spends one use
## of the team's switch budget; the receiving teammate may still act
## (the tool-OR-weapon rule is per character). Returns true when the
## hand-over happened.
func _try_switch_to_healthiest() -> bool:
	if not WeaponInventory.can_spend_tool(
			TurnController.team_id_of(self), ToolInventory.TOOL_SWITCH):
		return false
	var best: Node2D = null
	var best_hp := 0.0
	for mate in get_tree().get_nodes_in_group(
				"player_team" if is_in_group("player_team") else "enemy_team"):
		if mate == self or not (mate is Node2D) or not is_instance_valid(mate):
			continue
		if not _same_side(mate):
			continue
		var hp = mate.get("health")
		if hp == null or float(hp) <= 0.0:
			continue
		if float(hp) > best_hp:
			best_hp = float(hp)
			best = mate
	# Only switch to someone MEANINGFULLY healthier — above the kite
	# threshold the receiver takes no hurt-branch itself, so two hurt
	# figures can never ping-pong the turn between each other.
	if best == null or best_hp <= float(MAX_HEALTH) * KITE_HEALTH_FRACTION:
		return false
	WeaponInventory.spend_tool(
			TurnController.team_id_of(self), ToolInventory.TOOL_SWITCH)
	# This figure's turn action is spent (tool OR weapon) — also the
	# one-frame fuse while the active-member change propagates.
	_tool_used = true
	TurnController.active_member = best
	DebugInfo.log("%s switches out to %s" % [display_name,
			str(best.get("display_name"))])
	return true


## Issue #120: true when the grenade would land within our own blast
## radius — point-blank lobs damage us more than the target.
func _grenade_unsafe() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	return global_position.distance_to(_target.global_position) < GRENADE_MIN_RANGE


## Issue #99: true when a living teammate stands inside the corridor a
## straight projectile would travel between us and the current target.
func _teammate_blocks_shot() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var to := _target.global_position - global_position
	var length := to.length()
	if length < 1.0:
		return false
	var dir := to / length
	for mate in get_tree().get_nodes_in_group(
				"player_team" if is_in_group("player_team") else "enemy_team"):
		if mate == self or not is_instance_valid(mate):
			continue
		# Issue #228: only TRUE teammates block the shot — a figure from
		# another AI team standing in the line is fair collateral damage.
		if not _same_side(mate):
			continue
		var rel: Vector2 = mate.global_position - global_position
		var along := rel.dot(dir)
		if along <= 0.0 or along >= length:
			continue
		if absf(rel.cross(dir)) <= 44.0:
			return true
	return false
