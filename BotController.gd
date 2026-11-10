extends NcnnAIController2D

## Bot controller for the Forms battlefield, created from the editor's
## "NCNN AI Controller" script template (issue #355).
##
## Issue #381 implements the observation half of the contract: get_obs()
## gathers the bot's own vitals, the visible enemy and ally figures, and
## the active cooldown timers — normalized to stable ranges ([-1, 1] for
## relative positions and velocities, [0, 1] for HP/cooldown fractions).
## No raw coordinates or HP values ever leave this script. Issue #419
## re-expresses every positional and velocity slot in the agent's LOCAL
## frame — the bound figure's facing direction becomes +X (to_local() for
## positions, the inverse of the figure's rotation for velocities) — so
## the observation is translation- and rotation-invariant across the map.
## Issue #407
## implements the action-application half: set_action() translates discrete
## policy head indices into concrete game commands and stores them in
## pending_command for the turn-based game loop. Issue #408 implements
## the reward half: get_reward() returns the accumulated reward property,
## credited by game logic when this bot's figure lands a hit; issue #433
## refines those credits into the REWARD_SPEC.md §2 combat components
## (proportional damage with a per-step cap, a flat kill bonus on the
## killing blow, a once-per-death own-death penalty, and a floored
## friendly-fire term). Issue #434 adds the positioning and tempo
## components — an HP-scaled survival upkeep at own-turn start (§2.4),
## potential-based tile-quality shaping over the own turn (§2.5), and
## the idle-command and danger-tile turn-end penalties (§2.7/§2.8) —
## driven by TurnController's turn boundaries via notify_own_turn_*.
## Issue #409
## implements the episode lifecycle half: reset() clears the controller's
## own state (a pending order) and restores its figure to a clean start —
## spawn position, full HP, default protection, no cooldowns, revived.
## The action-space declaration remains a loud stub until its own issue.

const Stats := preload("res://scripts/CharacterStats.gd")

## Issue #381: fixed observation layout. OBS_SLOTS enemies and OBS_SLOTS
## allies are reported every step — nearest first, missing figures pad
## with zeros — so the flat vector length never changes
## (4 + 4*5 + 4*5 + 2 = 46 floats), whatever happens on the battlefield.
const OBS_SLOTS := 4
const FEATURES_PER_FIGURE := 5

## Issue #381: normalization scales — the Level.tscn arena half-extents
## (playable column 1152x752, same convention as TrainingBot.gd), so a
## figure on the opposite side of the arena maps to ~[-1, 1]. Velocities
## divide by the shared run speed (CharacterStats.SPEED).
const NORM_HALF_W := 576.0
const NORM_HALF_H := 376.0
const VEL_NORM := Stats.SPEED
## Issue #381: cooldown ceilings for the [0, 1] fractions — the slowest AI
## fire pause (Npc.gd FIRE_PAUSE, easy difficulty, 2.0 s) and the jump
## cooldown (Npc.gd JUMP_COOLDOWN, 1.0 s).
const FIRE_CD_MAX := 2.0
const JUMP_CD_MAX := 1.0

## Issue #381: the figure this controller plays (Player.gd or Npc.gd).
## Optional — when unset (or the linked figure is down) the controller
## speaks for the nearest alive figure in the current level.
@export var figure_path: NodePath

## Issue #409: spawn snapshot — whose clean pose was captured, and where.
## The FIRST resolution of a figure happens at its clean starting state
## (the framework observes before any action is applied), so that pose
## becomes the position reset() restores to. A NEW figure instance (the
## old one freed by its death animation, re-instantiated by the level)
## gets a fresh snapshot at its own clean state.
var _spawn_figure: Node2D = null
var _spawn_position := Vector2.ZERO

func get_obs() -> Dictionary:
	# Issue #381: the NcnnAIController2D contract wants ONE flat float
	# array under "obs" (the trainer reads only that key); the named
	# normalized groups live in _collect_obs_parts() for humans and tests.
	return {"obs": _flatten_parts(_collect_obs_parts())}

## Issue #381: named observation groups, each a float Array with every
## value already normalized:
##   "own"       [hp_frac, shield, vel_x, vel_y]                 (4)
##   "enemies"   OBS_SLOTS x [rel_x, rel_y, hp, vel_x, vel_y]   (20)
##   "allies"    OBS_SLOTS x [rel_x, rel_y, hp, vel_x, vel_y]   (20)
##   "cooldowns" [fire_frac, jump_frac]                          (2)
## Issue #419: every offset and velocity is expressed in the agent's
## LOCAL frame (local +X = the figure's facing direction); see
## _local_position() / _local_velocity(). Forms has no AP stat, so the shield flag (issue #221: it blocks one
## hit) fills the protection slot next to HP. Every alive figure in the
## level counts as visible — Forms has no fog or line-of-sight occlusion.
func _collect_obs_parts() -> Dictionary:
	var figure := _resolve_figure()
	var origin: Vector2 = figure.global_position if figure != null else global_position
	# Issue #419: the observation frame — the bound figure's local space
	# (the controller node itself when none is bound). Positions and
	# velocities below are expressed against it, so the observation stays
	# the same wherever (and at whatever angle) the battle happens.
	var frame: Node2D = figure if figure != null else self
	return {
		"own": _own_features(figure, frame),
		"enemies": _team_features(_enemy_group(figure), origin, figure, frame),
		"allies": _team_features(_ally_group(figure), origin, figure, frame),
		"cooldowns": _cooldown_features(figure),
	}

## Issue #409: capture `figure`'s current pose as the spawn snapshot —
## once per figure instance; later calls keep the original snapshot.
func _capture_spawn(figure: Node2D) -> void:
	if figure == _spawn_figure and is_instance_valid(_spawn_figure):
		return
	_spawn_figure = figure
	_spawn_position = figure.global_position

## Issue #409: the linked-or-nearest ALIVE resolution, plus the spawn
## snapshot capture on first sight of a figure.
func _resolve_figure() -> Node2D:
	var figure := _resolve_alive_figure()
	if figure != null:
		_capture_spawn(figure)
	return figure

## Issue #381: the linked figure, or the nearest alive figure in the tree.
## Duck-typed on `health` — both Player.gd and Npc.gd report it, so no
## type coupling to either script.
func _resolve_alive_figure() -> Node2D:
	if not figure_path.is_empty():
		var linked := get_node_or_null(figure_path)
		if linked != null and linked is Node2D and _alive(linked):
			return linked
	if not is_inside_tree():
		return null
	var best: Node2D = null
	var best_d := INF
	for side in ["player_team", "enemy_team"]:
		for fig in get_tree().get_nodes_in_group(side):
			if not (fig is Node2D and _alive(fig)):
				continue
			var d: float = global_position.distance_squared_to(fig.global_position)
			if d < best_d:
				best_d = d
				best = fig
	return best

## Issue #381: the controller fights for the side its figure is NOT in.
## Player figures and "player"-side NPCs share "player_team"; everything
## else fights under "enemy_team" (Npc.gd issue #121). Without a figure
## the default enemy-side view matches the Npc default team.
func _enemy_group(figure: Node2D) -> String:
	if figure != null and figure.is_in_group("player_team"):
		return "enemy_team"
	return "player_team"

func _ally_group(figure: Node2D) -> String:
	return "player_team" if _enemy_group(figure) == "enemy_team" else "enemy_team"

## Issue #381: nearest-first figure block with zero padding to a constant
## length; `exclude` drops the own figure from its allies (it is already
## reported by "own", and its position IS the observation origin).
## `origin` stays a WORLD-space point — it only feeds the nearest-first
## sort (distance is frame-independent); the reported features go through
## the agent-local `frame` (issue #419).
func _team_features(group_name: String, origin: Vector2, exclude: Node2D, frame: Node2D) -> Array:
	var rows: Array = []
	var figs: Array = []
	if is_inside_tree():
		figs = get_tree().get_nodes_in_group(group_name).filter(
			func(f): return f is Node2D and f != exclude and _alive(f))
		figs.sort_custom(func(a, b):
			var da := origin.distance_squared_to(a.global_position)
			var db := origin.distance_squared_to(b.global_position)
			if da == db:
				return String(a.name) < String(b.name)
			return da < db)
	for i in OBS_SLOTS:
		if i < figs.size():
			rows.append_array(_figure_features(figs[i], frame))
		else:
			for _j in FEATURES_PER_FIGURE:
				rows.append(0.0)
	return rows

## Issue #381/#419: one figure = [rel_x, rel_y, hp_frac, vel_x, vel_y] —
## offset and velocity in the agent's LOCAL frame (issue #419:
## _local_position() / _local_velocity() below), the offset normalized by
## the arena half-extents, HP as a [0, 1] fraction, velocity by the shared
## run speed; all clamped to [-1, 1]. An enemy straight ahead reads
## rel_x > 0 at any agent rotation.
func _figure_features(fig: Node2D, frame: Node2D) -> Array:
	var rel := _norm_rel(_local_position(fig, frame))
	var vel := _norm_vel(_local_velocity(fig.get("velocity"), frame))
	return [rel.x, rel.y, _hp_frac(fig), vel.x, vel.y]

## Issue #419: world → agent-local transforms. The frame's local +X is its
## facing direction; positions go through Godot's to_local() (the inverse
## of its global transform), velocities through the inverse of its
## rotation basis — for a 2D node that is the velocity rotated by
## -global_rotation, the 2D equivalent of
## global_transform.basis.orthonormalized().inverse() * linear_velocity.
## With rotation 0 the local frame equals the world frame, so scenes that
## never rotate their figures observe no change.
func _local_position(fig: Node2D, frame: Node2D) -> Vector2:
	return frame.to_local(fig.global_position)

func _local_velocity(value, frame: Node2D) -> Vector2:
	if value == null:
		return Vector2.ZERO
	var v: Vector2 = value
	return v.rotated(-frame.global_rotation)

## Issue #381: own vitals — HP fraction (never the raw value), the shield
## flag in the AP slot, and the current velocity in [-1, 1], expressed in
## the agent's own (local) frame (issue #419) — moving forward reads
## vel_x > 0 at any rotation. Without a figure the slots report a
## fully-healed stationary bot so the vector stays well-formed.
func _own_features(figure: Node2D, frame: Node2D) -> Array:
	if figure == null:
		return [1.0, 0.0, 0.0, 0.0]
	var vel := _norm_vel(_local_velocity(figure.get("velocity"), frame))
	var shield := 1.0 if bool(figure.get("shielded")) else 0.0
	return [_hp_frac(figure), shield, vel.x, vel.y]

## Issue #381: active cooldown timers as [0, 1] fractions of their
## ceilings — fire pause (_cooldown_left / FIRE_CD_MAX) and jump cooldown
## (_jump_left / JUMP_CD_MAX). Figures without a cooldown stat (Player.gd
## has none) read as 0.
func _cooldown_features(figure: Node2D) -> Array:
	if figure == null:
		return [0.0, 0.0]
	return [
		_cd_frac(figure.get("_cooldown_left"), FIRE_CD_MAX),
		_cd_frac(figure.get("_jump_left"), JUMP_CD_MAX),
	]

## Issue #381: fixed key order -> a deterministic flat layout (46 floats).
func _flatten_parts(parts: Dictionary) -> Array:
	var flat: Array = []
	for key in ["own", "enemies", "allies", "cooldowns"]:
		flat.append_array(parts[key])
	return flat

func _norm_rel(offset: Vector2) -> Vector2:
	# Issue #381: scaled by the arena half-extents, clamped to [-1, 1] so
	# larger levels stay inside the stable range.
	return Vector2(
		clampf(offset.x / NORM_HALF_W, -1.0, 1.0),
		clampf(offset.y / NORM_HALF_H, -1.0, 1.0))

func _norm_vel(value) -> Vector2:
	if value == null:
		return Vector2.ZERO
	var v: Vector2 = value
	return Vector2(
		clampf(v.x / VEL_NORM, -1.0, 1.0),
		clampf(v.y / VEL_NORM, -1.0, 1.0))

func _hp_frac(fig: Node2D) -> float:
	var hp = fig.get("health")
	if hp == null:
		return 0.0
	return clampf(float(hp) / float(Stats.MAX_HEALTH), 0.0, 1.0)

func _cd_frac(value, ceiling: float) -> float:
	if value == null or ceiling <= 0.0:
		return 0.0
	return clampf(float(value) / ceiling, 0.0, 1.0)

func _alive(fig) -> bool:
	var hp = fig.get("health")
	return hp != null and float(hp) > 0.0

func get_reward() -> float:
	# Issue #408: the accumulated reward signal — simply the inherited
	# `reward` property, never reset here. Game logic increments the
	# property at known events (Player/Npc.take_damage credit the REWARD_SPEC
	# §2 combat components when this bot's figure lands a hit); the training
	# framework clears it after each collection (NcnnSync /
	# zero_reward()), so this reports the delta since the last step.
	# Issue #436: the §3 final stage — the raw accumulator is returned
	# HARD-CLIPPED to ±REWARD_CLIP_BOUND before the trainer sees it. By
	# construction every non-terminal step already sits inside the bound
	# (§3 table: best +0.92 / worst −0.90), so the clip only guards sums
	# §3's single-kill budget cannot express — terminal steps stacking the
	# §2.9 outcome (not yet emitted) on a combat step, or a multi-kill
	# step. The raw accumulator is NOT touched: the clip is a read-side
	# guarantee, the framework stays the sole owner of clearing.
	return clampf(reward, -REWARD_CLIP_BOUND, REWARD_CLIP_BOUND)

## Issue #433: the combat reward components, magnitudes straight from
## REWARD_SPEC.md §2 (the damage fraction is damage / MAX_HEALTH, §1).
## A killing blow pays KILL_REWARD alone — the kill bonus applies once
## and NOT also the §2.1 damage tick on the same blow (issue #433), so
## removing an enemy is always worth more than the same damage dealt
## non-lethally.
const DAMAGE_REWARD_SCALE := 0.15        # §2.1: +0.15 × damage_fraction
const DAMAGE_REWARD_STEP_CAP := 0.30     # §2.1: cap per decision step
const KILL_REWARD := 0.50                # §2.2: flat, per kill
const DEATH_PENALTY := -0.50             # §2.3: flat, once per own death
const FRIENDLY_FIRE_SCALE := -0.10       # §2.6: −0.10 × damage_fraction
const FRIENDLY_FIRE_STEP_FLOOR := -0.30  # §2.6: floor per decision step

## Issue #434: the positioning/tempo reward components, magnitudes
## straight from REWARD_SPEC.md §2 (updated in the same change): the
## survival upkeep is SCALED by the remaining HP fraction (issue #434
## DoD) so cautious play keeps more of it, while staying ≤ +0.02 so the
## §3 quiet-step budget |r| ≤ 0.12 keeps holding.
const SURVIVAL_REWARD := 0.02         # §2.4: +0.02 × hp_fraction per own turn
const POSITIONING_SCALE := 0.10       # §2.5: ±0.10 × ΔΦ per decision step
const IDLE_PENALTY := -0.05           # §2.7: flat, per idle turn
const DANGER_TILE_PENALTY := -0.05    # §2.8: flat, per turn ended on a danger tile
## Issue #436: REWARD_SPEC §3's magnitude budget — every non-terminal
## per-step reward is inside [−1, +1] by construction and terminal steps
## clip to ±1.0 before logging. Derived from §3, not chosen freely (the
## spec's Maintenance rule): if §2 magnitudes are ever retuned, this
## bound follows the re-derived §3 table in the same change.
const REWARD_CLIP_BOUND := 1.0
## Issue #434: the ACTION_SPEC §1 enemy-visibility band — alive +
## opposing side + within ATTACK_REACH (the same reach the scaffold's
## action mask uses, TrainingBot.ATTACK_REACH: the widest AI weapon
## band, the rocket).
const ATTACK_REACH := 620.0
## Issue #434: the world collision layer — destructible AND indestructible
## ground both live on layer 1 (IndestructibleGround/DestructibleGround),
## exactly what a projectile's flight can be occluded by: the levels'
## own tile/props data IS the cover check (the issue's fallback clause).
const WORLD_LAYER := 1

## Issue #433: the four combat reward events, declared for the declarative
## recipe system (REWARD_SPEC §4): RewardRecipe validates event_bonus
## terms against get_reward_affordances() and a RewardAdapter routes
## these signals into a Reward's trigger_event(). The payload is the
## signed delta actually added to `reward` (already cap/floor-amortized),
## so an external logger sees exactly the numbers the trainer does.
signal damage_dealt(applied: float)
signal enemy_killed
signal own_figure_died
signal friendly_fire(applied: float)

## Issue #434: the positioning/tempo reward events, declared for the
## recipe system (REWARD_SPEC §4) — same payload contract as the combat
## signals: the signed delta actually added to `reward`. The §2.5 shaped
## term itself is a VALUE FUNCTION (tile_quality below); its per-step
## delta rides positioning_credited for logging parity.
signal survival_per_turn(applied: float)
signal positioning_credited(applied: float)
signal idle_turn(applied: float)
signal danger_tile_turn_end(applied: float)

## Issue #433: how much of this step's §2.1 cap / §2.6 floor budget is
## already spent — several hits inside ONE decision step amortize into
## the cap, so the trackers reset exactly when the framework clears the
## accumulator (zero_reward() / reset()).
var _step_damage_reward := 0.0
var _step_friendly_fire_reward := 0.0

## Issue #436: per-component reward log — every §2 component's signed
## contribution since the accumulator was last cleared, keyed by the
## spec's component names (damage_dealt, enemy_killed, survival_per_turn,
## positioning, idling, ...), so training logs can break the step's
## return down by category. Cheap by design: plain float adds on the
## rare reward-event paths, no per-frame string formatting, and the
## dictionary stays empty on quiet steps. Cleared together with the
## `reward` property in zero_reward() (and at episode reset).
var reward_component_log := {}

## Issue #434: own-turn bookkeeping — the shaping potential rebases at
## every own-turn start (§2.5), the idle audit reads the order that was
## pending when the turn began (what the game loop will consume at turn
## start, #407), and every turn-end term fires at most once per started
## turn. _has_new_order tracks whether the policy decided since the last
## turn start: a controller that never got a set_action had no choice,
## so its expired turn is not "idling" (REWARD_SPEC §1).
var _turn_active := false
var _turn_figure: Node2D = null
var _has_new_order := false
var _has_ordered := false
var _turn_command := _idle_command()
var _potential_baseline := 0.0

## Issue #433: the manifest the recipe tooling validates against
## (RewardRecipe.validate reads {"signals": …}); the four combat signals
## exist and are emitted by the attribution path below — the positioning,
## tempo and termination signals are #434's work order.
func get_reward_affordances() -> Dictionary:
	return {
		"value_functions": {
			"tile_quality": "§2.5 — Φ ∈ [0,1] cover potential of the figure's tile: fraction of alive enemies within ATTACK_REACH whose fire line is occluded by world geometry; 1.0 when none is in reach (influence-map half deferred, #434 fallback clause)",
		},
		"signals": {
			"damage_dealt": "§2.1 — enemy figure lost health to this agent's hit (+0.15×frac, +0.30/step cap)",
			"enemy_killed": "§2.2 — this agent's blow killed an enemy figure (+0.50 flat, no damage tick stacked)",
			"own_figure_died": "§2.3 — the controlled figure died (−0.50 flat, once per death)",
			"friendly_fire": "§2.6 — this agent's hit damaged its own team (−0.10×frac, −0.30/step floor)",
			"survival_per_turn": "§2.4 — own turn started while alive (+0.02 × hp_fraction, ≤ +0.02)",
			"positioning_credited": "§2.5 — potential-based shaped ΔΦ credited this step (±0.10 × ΔΦ, rebased at own-turn start)",
			"idle_turn": "§2.7 — turn ended all-neutral with an enemy in reach (−0.05, only on turns the policy ordered on)",
			"danger_tile_turn_end": "§2.8 — turn ended inside an enemy's clear line-of-fire band (−0.05)",
		},
	}

## Issue #408: does this controller play `fig`? Game logic (take_damage)
## uses it to find whose accumulator a landed hit credits. Controllers
## duck-type on this method, so foreign AGENT-group agents are skipped.
## Deliberately resolves WITHOUT capturing the spawn snapshot: game
## logic calls this on every landed hit, and while the controller's own
## figure lies dying the alive filter resolves a DIFFERENT figure —
## re-capturing then would clobber the snapshot the death attribution
## reads a moment later (issue #433). get_obs() owns the capturing.
func owns_figure(fig: Node2D) -> bool:
	return _resolve_alive_figure() == fig

## Issue #433: combat attribution — Player/Npc.take_damage calls this
## right AFTER applying the damage (so a killing blow is detectable from
## the victim's health), with the figure that fired. Every controller in
## the AGENT group whose figure is the attacker earns the matching
## REWARD_SPEC §2 component: enemy damage (§2.1), the kill bonus on the
## killing blow (§2.2, replacing the damage tick), or friendly fire
## (§2.6). Every weapon path that threads its shooter (Projectile,
## ProjectileBody, railgun) feeds the same accumulator.
static func credit_combat_reward(attacker: Node2D, victim: Node2D, damage: int) -> void:
	if attacker == null or not attacker.is_inside_tree():
		return
	for ctrl in attacker.get_tree().get_nodes_in_group("AGENT"):
		if ctrl == null or not ctrl.has_method("owns_figure"):
			continue
		if not ctrl.owns_figure(attacker):
			continue
		if _same_team(attacker, victim):
			ctrl._credit_friendly_fire(damage)
		elif _figure_dead(victim):
			ctrl._credit_kill()
		else:
			ctrl._credit_damage(damage)

## Issue #433: the own-death penalty — REWARD_SPEC §2.3 fires at the
## moment of death for every controller that plays the dying figure,
## whatever killed it (an enemy, a stray blast, no attacker at all).
## take_damage's _dead guard makes each figure die exactly once, so the
## penalty can never stack.
static func notify_figure_died(victim: Node2D) -> void:
	if victim == null or not victim.is_inside_tree():
		return
	for ctrl in victim.get_tree().get_nodes_in_group("AGENT"):
		if ctrl != null and ctrl.has_method("on_owned_figure_died"):
			ctrl.on_owned_figure_died(victim)

## Issue #433: does this controller play `fig` even now that fig is
## DEAD? owns_figure() resolves through the alive-only filter, which
## skips a figure at the moment of its death — so the death attribution
## checks the LINKED figure (down or not) and the spawn snapshot
## (captured by the last observation, see owns_figure()). A controller
## that has never observed (no snapshot, no link) cannot attribute the
## death — the training loop always observes first, so that is a
## stand-in-only corner.
func _owns_dead_figure(fig: Node2D) -> bool:
	if not figure_path.is_empty():
		var linked := get_node_or_null(figure_path)
		if linked == fig:
			return true
	return fig == _spawn_figure and is_instance_valid(_spawn_figure)

## Issue #433: §2.3 — flat, exactly once per death of the controlled
## figure. Called by notify_figure_died(); foreign stand-ins without
## this method are skipped.
func on_owned_figure_died(fig: Node2D) -> void:
	if not _owns_dead_figure(fig):
		return
	reward += DEATH_PENALTY
	_log_reward_component("own_figure_died", DEATH_PENALTY)
	own_figure_died.emit()
	# Issue #434: §2.3 — after the own figure's death every further
	# per-step component reads 0: the own-turn state closes so no idle,
	# danger-tile or shaped remainder can fire afterwards.
	_turn_active = false
	_turn_figure = null

## Issue #433: §2.1 — proportional to the damage dealt, amortized into
## the per-step cap (the cap, not the per-hit term, is what a multi-hit
## step shares).
func _credit_damage(damage: int) -> void:
	var bonus := minf(
			DAMAGE_REWARD_SCALE * _damage_fraction(damage),
			DAMAGE_REWARD_STEP_CAP - _step_damage_reward)
	if bonus <= 0.0:
		return
	_step_damage_reward += bonus
	reward += bonus
	_log_reward_component("damage_dealt", bonus)
	damage_dealt.emit(bonus)

## Issue #433: §2.2 — flat kill bonus on the killing blow; the §2.1
## damage tick is deliberately NOT stacked under it (credit_combat_reward
## routes the blow to exactly one of the two).
func _credit_kill() -> void:
	reward += KILL_REWARD
	_log_reward_component("enemy_killed", KILL_REWARD)
	enemy_killed.emit()

## Issue #433: §2.6 — proportional friendly fire, floored per step so
## several careless blasts inside one decision step cannot bury the
## signal (the floor mirrors the §2.1 cap).
func _credit_friendly_fire(damage: int) -> void:
	var penalty := maxf(
			FRIENDLY_FIRE_SCALE * _damage_fraction(damage),
			FRIENDLY_FIRE_STEP_FLOOR - _step_friendly_fire_reward)
	if penalty >= 0.0:
		return
	_step_friendly_fire_reward += penalty
	reward += penalty
	_log_reward_component("friendly_fire", penalty)
	friendly_fire.emit(penalty)

## Issue #433: the [0, 1] damage fraction of REWARD_SPEC §1 — damage
## relative to CharacterStats.MAX_HEALTH, never the victim's own maximum.
func _damage_fraction(damage: int) -> float:
	return clampf(float(damage) / float(Stats.MAX_HEALTH), 0.0, 1.0)

## Issue #433: duck-typed team check — every real figure reports one of
## the two team groups (Npc.gd issue #121, Player.gd); matching groups
## mean the same team, so a hit between them is §2.6 friendly fire.
static func _same_team(a: Node2D, b: Node2D) -> bool:
	return a.is_in_group("player_team") == b.is_in_group("player_team") \
			and a.is_in_group("enemy_team") == b.is_in_group("enemy_team")

## Issue #433: health ≤ 0 means the killing blow just landed —
## take_damage applies health before crediting, so the attribution path
## sees the post-damage value. Duck-typed: test stand-ins report
## `health` exactly like Player/Npc.
static func _figure_dead(fig: Node2D) -> bool:
	var hp = fig.get("health")
	return hp != null and float(hp) <= 0.0

## Issue #434: TurnController calls these two at every turn boundary of
## a figure an AGENT controller plays (duck-typed dispatch, exactly the
## #433 pattern) — the turn-based half of the REWARD_SPEC §2.4/§2.5/
## §2.7/§2.8 components. Human-controlled figures simply have no
## controller in the AGENT group, so nothing fires for them.
static func notify_own_turn_started(member: Node2D) -> void:
	if not is_instance_valid(member) or not member.is_inside_tree():
		return
	for ctrl in member.get_tree().get_nodes_in_group("AGENT"):
		if ctrl != null and ctrl.has_method("owns_figure") and ctrl.owns_figure(member):
			ctrl.on_own_turn_started()

## Issue #434: the turn-end twin — dispatched before the winner check
## or the next team's turn could free or replace the acting member.
static func notify_own_turn_ended(member: Node2D) -> void:
	# is_instance_valid first: a figure freed by its death animation
	# (queue_free) can still be TurnController's active_member when the
	# turn ends — touching a freed instance would hard-error.
	if not is_instance_valid(member) or not member.is_inside_tree():
		return
	for ctrl in member.get_tree().get_nodes_in_group("AGENT"):
		if ctrl != null and ctrl.has_method("owns_figure") and ctrl.owns_figure(member):
			ctrl.on_own_turn_ended()

## Issue #434: §2.4 + §2.5 at own-turn start — the survival upkeep
## (HP-scaled, ≤ +0.02) and the shaping rebase: the turn's Φ travels
## are measured against the tile the turn STARTED on. The idle audit
## snapshots the order pending right now — the one the game loop will
## consume for this turn (#407) — and whether the policy decided at all
## since the last turn start (§1: no decision ⇒ no choice ⇒ no idling).
func on_own_turn_started() -> void:
	_turn_active = true
	_turn_figure = _resolve_alive_figure()
	_has_ordered = _has_new_order
	_turn_command = pending_command.duplicate()
	_has_new_order = false
	if _turn_figure != null:
		var applied := SURVIVAL_REWARD * _hp_frac(_turn_figure)
		reward += applied
		_log_reward_component("survival_per_turn", applied)
		survival_per_turn.emit(applied)
	_potential_baseline = get_tile_quality()

## Issue #434: the turn-end audits — §2.5's shaped remainder first, then
## §2.7 idling (the command audit) and §2.8's danger-tile penalty. Fires
## at most once per started turn; a figure that died mid-turn owes none
## of these (§2.3 fired at the moment of death; everything after reads 0).
func on_own_turn_ended() -> void:
	if not _turn_active:
		return
	_credit_positioning_step()
	_turn_active = false
	var figure := _turn_figure
	_turn_figure = null
	if figure == null or not is_instance_valid(figure) or not _alive(figure):
		return
	if _has_ordered and _command_all_neutral(_turn_command) \
				and _enemy_in_reach(figure):
		reward += IDLE_PENALTY
		_log_reward_component("idling", IDLE_PENALTY)
		idle_turn.emit(IDLE_PENALTY)
	if _on_danger_tile(figure):
		reward += DANGER_TILE_PENALTY
		_log_reward_component("danger_tile_turn_end", DANGER_TILE_PENALTY)
		danger_tile_turn_end.emit(DANGER_TILE_PENALTY)

## Issue #434: §2.5 — potential-based shaping: every decision step of
## the own turn pays ±0.10 × ΔΦ since the last evaluation, so a whole
## turn telescopes to 0.10 × (Φ_end − Φ_start) — repositioning smarter,
## never moving more. Evaluated while the own turn is active and only
## for the figure the turn belongs to (no drift scoring when the
## alive-fallback would resolve a stand-in, the #433 note).
func _credit_positioning_step() -> void:
	if not _turn_active:
		return
	var figure := _resolve_alive_figure()
	if figure == null or figure != _turn_figure:
		return
	var quality := _tile_quality(figure)
	var applied := POSITIONING_SCALE * (quality - _potential_baseline)
	_potential_baseline = quality
	if is_zero_approx(applied):
		return
	reward += applied
	_log_reward_component("positioning", applied)
	positioning_credited.emit(applied)

## Issue #436: record one component's signed delta in the per-component
## debug dictionary (REWARD_SPEC §2 component names). Called only on reward events —
## never per frame — so the log costs one float add per event and the
## string keys are constants on the (rare) credit paths, not something
## rebuilt every step.
func _log_reward_component(component: String, delta: float) -> void:
	reward_component_log[component] = reward_component_log.get(component, 0.0) + delta

## Issue #434: the §2.5 value function the manifest declares — the
## tile-quality potential Φ of the resolved figure's tile (0.0 in the
## no-figure fallback state, a constant so a death never shapes).
func get_tile_quality() -> float:
	var figure := _resolve_alive_figure()
	if figure == null:
		return 0.0
	return _tile_quality(figure)

## Issue #434: Φ ∈ [0, 1] — the fraction of the alive enemies within
## ATTACK_REACH whose straight fire line to the figure is occluded by
## world geometry (layer 1 ground, destructible and indestructible
## alike). No enemy in reach means nothing can fire at the tile at all:
## Φ = 1.0. The influence-map half of REWARD_SPEC §2.5 is Phase 3's map
## (it does not exist yet), so the issue's fallback clause makes this
## the minimal cover check over the levels' own tile/props data.
func _tile_quality(figure: Node2D) -> float:
	var enemies := _enemies_in_reach(figure)
	if enemies.is_empty():
		return 1.0
	var occluded := 0
	for enemy in enemies:
		if _fire_line_occluded(enemy.global_position, figure.global_position):
			occluded += 1
	return float(occluded) / float(enemies.size())

## Issue #434: the ACTION_SPEC §1 predicate — alive, opposing side
## (duck-typed on the team groups), within ATTACK_REACH of the figure.
func _enemies_in_reach(figure: Node2D) -> Array:
	if not is_inside_tree():
		return []
	var in_reach: Array = []
	for fig in get_tree().get_nodes_in_group(_enemy_group(figure)):
		if fig is Node2D and _alive(fig) \
				and figure.global_position.distance_to(fig.global_position) <= ATTACK_REACH:
			in_reach.append(fig)
	return in_reach

func _enemy_in_reach(figure: Node2D) -> bool:
	return not _enemies_in_reach(figure).is_empty()

## Issue #434: is the straight segment from `from` to `to` blocked by
## world geometry? A physics ray against the world layer — the same
## collision ground a projectile's flight would have to clear.
func _fire_line_occluded(from: Vector2, to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_LAYER)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## Issue #434: §2.8's danger tile — open ground under enemy fire: at
## least one alive enemy inside ATTACK_REACH holds a CLEAR fire line
## onto the figure's tile (the same tile set Φ scores: danger ⟺ Φ < 1).
func _on_danger_tile(figure: Node2D) -> bool:
	for enemy in _enemies_in_reach(figure):
		if not _fire_line_occluded(enemy.global_position, figure.global_position):
			return true
	return false

## Issue #434: §2.7's neutral command — every head the controller
## translates (#407) sits on its neutral value.
func _command_all_neutral(command: Dictionary) -> bool:
	return int(command.get("move", MoveCommand.HOLD)) == MoveCommand.HOLD \
			and int(command.get("action", ActionCommand.IDLE)) == ActionCommand.IDLE

## Issue #433: the framework clears the accumulator per decision step
## (NcnnSync calls zero_reward()) — the §2.1 cap / §2.6 floor budgets
## restart together with it.
func zero_reward() -> void:
	super.zero_reward()
	_step_damage_reward = 0.0
	_step_friendly_fire_reward = 0.0
	# Issue #436: the per-component log is a debug view of the SAME step
	# window as the accumulator — it clears at exactly the moment the
	# reward property is cleared (NcnnSync calls this after collecting).
	reward_component_log.clear()

## Issue #409: episode reset — restore the bot and its battlefield state
## to a clean start. The framework's share (step counter, needs_reset,
## recurrent memory — and the accumulated reward, cleared by the Sync's
## zero_reward()) is already handled by the base class; this override
## clears the controller's OWN custom state (a pending order must never
## fire in the new episode) and restores the controlled figure.
func reset() -> void:
	super.reset()
	pending_command = _idle_command()
	# Issue #433: a fresh episode restarts the per-step cap/floor budgets
	# together with the rest of the controller's own state (the reward
	# accumulator itself stays the framework's to clear).
	_step_damage_reward = 0.0
	_step_friendly_fire_reward = 0.0
	# Issue #436: a fresh episode also starts with an empty per-component
	# log — the previous episode's breakdown must not leak into the next
	# one's training logs.
	reward_component_log.clear()
	# Issue #434: a fresh episode starts outside any turn — no stale order
	# can be audited as this episode's idling, no Φ baseline leaks in.
	_turn_active = false
	_turn_figure = null
	_has_new_order = false
	_has_ordered = false
	_turn_command = _idle_command()
	_restore_figure()

## Issue #409: the horizon auto-reset must restore the episode too — the
## base reset_if_done() only clears core bookkeeping, which would leave a
## stale command and a battered figure behind at a reset_after boundary.
func reset_if_done() -> void:
	if get_done():
		reset()

## Issue #409: which figure reset() restores — the LINKED figure even
## when down (the game-over state _resolve_figure()'s alive filter
## skips), else the spawn snapshot's owner if it still exists, else the
## alive fallback. A figure FREED by its death animation (Player/Npc._die
## queue_free()s after the shrink-out) is gone for good: a fresh episode
## re-instances it with the scene, and until then the controller observes
## the well-formed "no figure" default (issue #381).
func _resolve_reset_figure() -> Node2D:
	if not figure_path.is_empty():
		var linked := get_node_or_null(figure_path)
		if linked != null and linked is Node2D:
			return linked
	if is_instance_valid(_spawn_figure):
		return _spawn_figure
	return _resolve_figure()

## Issue #409: the state restore itself — every access duck-typed so any
## figure flavour (Player, Npc, test stand-ins) resets as far as it can:
## spawn position, at rest, full HP, default protection (Forms has no AP
## stat — the shield fills that slot, issue #381), zeroed cooldowns and
## aim, a game-over figure revived, the health bar redrawn.
func _restore_figure() -> void:
	var figure := _resolve_reset_figure()
	if figure == null:
		return
	_capture_spawn(figure)
	figure.global_position = _spawn_position
	if figure.get("velocity") != null:
		figure.set("velocity", Vector2.ZERO)
	figure.set("health", Stats.MAX_HEALTH)
	if figure.has_method("set_shielded"):
		figure.set_shielded(false)
	for cooldown in ["_cooldown_left", "_jump_left"]:
		if cooldown in figure:
			figure.set(cooldown, 0.0)
	if "view_angle" in figure:
		figure.set("view_angle", 0.0)
	if "_dead" in figure and bool(figure.get("_dead")):
		_revive_figure(figure)
	if figure.has_signal("health_changed"):
		figure.emit_signal("health_changed", Stats.MAX_HEALTH, Stats.MAX_HEALTH)
	if figure.has_method("_update_bar"):
		figure.call("_update_bar")

## Issue #409: a game-over figure is revived — the death flag comes down,
## physics resumes, and the shrink-out death tween is cancelled (killed,
## body scale restored) so the bot re-enters the next episode whole.
func _revive_figure(figure: Node2D) -> void:
	figure.set("_dead", false)
	figure.set_physics_process(true)
	var death_tween = figure.get("death_tween")
	if death_tween is Tween:
		death_tween.kill()
		figure.set("death_tween", null)
	figure.scale = Vector2.ONE

func get_action_space() -> Dictionary:
	# Describe each action head. Examples:
	#     "move": {"size": 4, "action_type": "discrete"}     # one of 4 choices
	#     "steer": {"size": 2, "action_type": "continuous"}  # 2 floats in [-1, 1]
	push_error("get_action_space() not implemented")
	return {}

## Issue #407: concrete game commands the raw policy indices translate
## into. "move" orders the turn's walk direction (HOLD = stand still);
## "action" orders the combat move — ATTACK_ENEMY_A targets the nearest
## alive enemy, ATTACK_ENEMY_B the second nearest (the same nearest-first
## order the observation vector reports them in, issue #381), USE_ABILITY
## the figure's special, IDLE passes. Resolving which node "enemy A"/"B"
## name at execution time stays with the game loop.
enum MoveCommand { HOLD, RIGHT, LEFT }
enum ActionCommand { IDLE, ATTACK_ENEMY_A, ATTACK_ENEMY_B, USE_ABILITY }

## Walk direction each MoveCommand maps to (unit vector; distance and
## timing stay with the game loop's turn logic).
const MOVE_DIRS := {
	MoveCommand.HOLD: Vector2.ZERO,
	MoveCommand.RIGHT: Vector2.RIGHT,
	MoveCommand.LEFT: Vector2.LEFT,
}

## Issue #407: the translated command the game loop executes on the bot's
## next turn — set_action() rewrites it on every policy decision step.
## Always carries "move" (MoveCommand), "action" (ActionCommand) and
## "move_dir" (Vector2); malformed policy output degrades to idle/hold.
var pending_command: Dictionary = {
	"move": MoveCommand.HOLD,
	"action": ActionCommand.IDLE,
	"move_dir": Vector2.ZERO,
}

func set_action(action) -> void:
	# Issue #407: NcnnSync (TRAINING mode) calls this once per decision step
	# with the decoded policy output — for a discrete action space a
	# dictionary of action head -> integer index, e.g. {"move": 2,
	# "action": 0}. The indices are translated into the concrete commands
	# above and STORED on the bot: actuation stays with the turn-based game
	# loop, which executes pending_command when the bot's turn comes. The
	# input is defended at the type/range level — garbage degrades to the
	# idle command with a warning, never a script error.
	if typeof(action) != TYPE_DICTIONARY:
		push_warning(
			"BotController.set_action: expected a Dictionary of action heads, "
			+ "got %s — idling" % type_string(typeof(action)))
		pending_command = _idle_command()
		return
	var move := _head_index(action, "move", MoveCommand.size())
	var order := _head_index(action, "action", ActionCommand.size())
	pending_command = {
		"move": move,
		"action": order,
		"move_dir": MOVE_DIRS[move],
	}
	# Issue #434: a decision arrived — the NEXT own turn is one the policy
	# chose commands on, so its idle audit may fire (REWARD_SPEC §1).
	_has_new_order = true

## Issue #407: the game loop calls this when the bot's turn starts — it
## hands over the stored order and resets the bot to idle/hold so a stale
## command can never fire twice.
func consume_pending_command() -> Dictionary:
	var command := pending_command
	pending_command = _idle_command()
	return command

## Issue #407: action-head lookup that survives any decoder — a missing
## head or a value that is out of range / not int-coercible falls back to
## index 0 (the head's neutral HOLD/IDLE value) with a warning. int()
## coerces the float/string values foreign decoders emit; containers can
## never be an index and are rejected outright.
func _head_index(action: Dictionary, head: String, size: int) -> int:
	if not action.has(head):
		return 0
	var value = action[head]
	var value_type := typeof(value)
	if value_type == TYPE_ARRAY or value_type == TYPE_DICTIONARY \
			or value_type == TYPE_OBJECT:
		push_warning(
			("BotController.set_action: head '%s' is a %s, expected an "
			+ "integer index — using 0") % [head, type_string(value_type)])
		return 0
	var index := int(value)
	if index < 0 or index >= size:
		push_warning(
			("BotController.set_action: head '%s' index %d outside [0, %d] "
			+ "— using 0") % [head, index, size - 1])
		return 0
	return index

func _idle_command() -> Dictionary:
	return {
		"move": MoveCommand.HOLD,
		"action": ActionCommand.IDLE,
		"move_dir": Vector2.ZERO,
	}

#func get_obs_space() -> Dictionary:
#	# Override only for complex obs (images, multiple keys). The base class derives
#	# {"obs": {"size": [len], "space": "box"}} from get_obs() automatically.
#	return super.get_obs_space()
