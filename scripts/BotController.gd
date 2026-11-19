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
## Issue #437 implements the terminal-outcome half: a terminal game state
## (elimination / draw) pays the REWARD_SPEC §2.9 win/loss through the
## framework's game_over() flags — done=true + needs_reset=true, truncated
## stays false, and the turn-limit horizon (truncation) never pays it.
## Issue #607 widens that declaration to the FULL action repertoire:
## five discrete heads — move (all 6 movement commands, jump and
## backflip included), aim (hold/up/down), attack (hold fire + all 10
## WeaponInventory slots), target (nearest-first enemy selection) and
## tool (all 4 ToolInventory tools) — with a per-head legality mask
## shipped in info["action_mask"].
## Issue #447 appends the TEAM block (4 floats) on top of the local
## observations: the shared focus target's relative position, the team's
## average HP fraction and the living ally-to-enemy ratio — all sourced
## from TeamBlackboard (issue #446) through the agent's OWN team id, never
## from a fresh world query.

const Stats := preload("res://scripts/CharacterStats.gd")

static var _last_reset_frame: int = -1

## Issue #381: fixed observation layout. OBS_SLOTS enemies and OBS_SLOTS
## allies are reported every step — nearest first, missing figures pad
## with zeros — so the flat vector length never changes
## (4 + 4*5 + 4*5 + 2 + 4 = 50 floats), whatever happens on the
## battlefield. The trailing 4 are the issue #447 team block.
const OBS_SLOTS := 4
const FEATURES_PER_FIGURE := 5

## Issue #381: normalization scales — the Level1.tscn arena half-extents
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
##   "team"      [focus_x, focus_y, team_hp, ally_enemy_ratio]   (4)
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
		"team": _team_blackboard_features(figure, frame),
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

## Issue #447: TEAM-level block (4 floats) sourced from the TeamBlackboard
## (issue #446), NOT from a fresh world query — TurnController refreshes the
## acting team's board once per TURN, so these slots report the team's
## shared turn-level picture: [focus_x, focus_y, team_hp, ally_enemy_ratio].
## focus_x/focus_y — the TEAM-SHARED focus target's offset from the agent in
## the same agent-local frame and [-1, 1] normalization as the enemy slots
## (0.0, 0.0 while the board holds no living focus target); team_hp and
## ally_enemy_ratio via the helpers below. Without a bound figure the block
## falls back to [0.0, 0.0, 1.0, 0.5] — no focus target, a healthy team, an
## even ratio — the same well-formed neutral convention as _own_features'
## fully-healed stationary bot.
func _team_blackboard_features(figure: Node2D, frame: Node2D) -> Array:
	if figure == null:
		return [0.0, 0.0, 1.0, 0.5]
	var team_id := TurnController.team_id_of(figure)
	var rel := Vector2.ZERO
	var focus := TeamBlackboard.get_focus_target(team_id)
	if focus != null:
		rel = _norm_rel(_local_position(focus, frame))
	return [rel.x, rel.y, _team_hp_frac(team_id), _ally_enemy_ratio(team_id)]

## Issue #447: the board's average HP over the team's LIVING allies as a
## [0, 1] fraction of MAX_HEALTH — the same scale as the per-figure
## hp_frac slots; raw HP values never leave the controller.
func _team_hp_frac(team_id: String) -> float:
	return clampf(
		TeamBlackboard.get_team_hp_avg(team_id) / float(Stats.MAX_HEALTH),
		0.0, 1.0)

## Issue #447: living allies / (living allies + living enemies) from the
## board's counts — 1.0 = only allies alive, 0.0 = only enemies, 0.5 with
## nobody (an even, empty match keeps the slot neutral).
func _ally_enemy_ratio(team_id: String) -> float:
	var allies := TeamBlackboard.get_living_allies(team_id)
	var enemies := TeamBlackboard.get_living_enemies(team_id)
	var total := allies + enemies
	if total <= 0:
		return 0.5
	return clampf(float(allies) / float(total), 0.0, 1.0)

## Issue #381: fixed key order -> a deterministic flat layout (50 floats;
## the trailing "team" block is issue #447).
func _flatten_parts(parts: Dictionary) -> Array:
	var flat: Array = []
	for key in ["own", "enemies", "allies", "cooldowns", "team"]:
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
## Issue #437: the §2.9 terminal outcome — the ONE terminal-only component,
# exempt from the §3 steady-state budget (terminal steps clip to ±1.0 in
# get_reward() on read). A win pays measurably more than a timeout, which
# pays no outcome at all (truncation must not look like a victory).
const EPISODE_WIN_REWARD := 0.50      # §2.9: own team is the sole surviving side
const EPISODE_LOSS_REWARD := -0.50     # §2.9: own side wiped (draw included) or lost
## Issue #654: §2.10 conservation upkeep — per still-unspent SCARCE
## weapon at own-turn end. Deliberately upkeep-small (half of §2.4) so
## one decisive railgun shot (§2.1 + §2.2 pay up to +0.80) always
## outruns hoarding: the upkeep prices the weapon's opportunity cost,
## it never forbids spending it.
const SCARCE_WEAPON_SAVED_REWARD := 0.01
## Issue #654: indices into WeaponInventory.WEAPONS of the weapons worth
## saving — today exactly one, the railgun (WEAPON_RAILGUN = 6, the
## 1-use-per-team RAILGUN_USES budget; every other weapon carries five
## uses or is infinite, so none is scarce).
const SCARCE_WEAPON_INDICES := [6]
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
## Issue #437: the §2.9 terminal outcome events (REWARD_SPEC §4's
# `event_bonus("episode_won"/"episode_lost", ±0.5)` row) — payload is the
# signed delta actually added to `reward`, same contract as every other
# reward signal.
signal episode_won(applied: float)
signal episode_lost(applied: float)
## Issue #654: the §2.10 conservation upkeep event, declared for the
## recipe system (REWARD_SPEC §4) — same payload contract as every other
## reward signal: the signed delta actually added to `reward` when the
## agent's own turn ends with the team's scarce weapon budget unspent.
signal weapon_saved(applied: float)

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

## Issue #469: the snapshot of the per-step breakdown that rides the
## training step message. NcnnSync collects one step in a fixed order —
## get_reward() + zero_reward() first, get_info() after — so zero_reward()
## copies the window HERE before clearing it and get_info() ships the copy
## (the live log is already empty by the time it runs).
var _step_reward_components := {}

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
			"episode_won": "§2.9 — episode ended with own team the sole surviving side (+0.50 terminal, #437)",
			"episode_lost": "§2.9 — episode ended with own side wiped or outlived, draw included (−0.50 terminal, #437)",
			"weapon_saved": "§2.10 — own turn ended with the team's scarce weapon (railgun) budget still unspent (+0.01 per scarce weapon per turn, #654)",
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

## Issue #437: TurnController._check_win() calls this once when the game
# reaches a terminal state — every controller in the AGENT group gets its
# §2.9 outcome through on_episode_outcome(). Duck-typed dispatch like
## notify_figure_died(): foreign AGENT agents are skipped.
static func notify_episode_outcome(winner_team: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for ctrl in tree.get_nodes_in_group("AGENT"):
		if ctrl != null and ctrl.has_method("on_episode_outcome"):
			ctrl.on_episode_outcome(winner_team)

## Issue #437: the §2.9 terminal credit — win (+0.50) when the own team is
## the sole survivor, loss (−0.50) when the own side is wiped or outlived
## (a mutual-destruction draw counts as a loss: the own side is wiped).
## Flags ride the framework's game_over() helper: done=true + needs_reset=true,
## truncated stays false, and the outcome rides the accumulator the Sync
## drains on the terminal step (clipped to ±1.0 by get_reward(), §3).
func on_episode_outcome(winner_team: String) -> void:
	# Already ended this episode (e.g. the horizon fired earlier in the same
	# frame): a truncation must never be upgraded into a paid win/loss.
	if get_done():
		return
	var figure := _resolve_outcome_figure()
	if figure == null:
		return  # never observed, no side to attribute — no outcome credit
	var won: bool = not winner_team.is_empty() \
			and TurnController.team_id_of(figure) == winner_team
	var delta: float = EPISODE_WIN_REWARD if won else EPISODE_LOSS_REWARD

	print("!!! TRIGGERING GAME OVER !!! winner_team: ", winner_team, " won: ", won)

	game_over(delta)
	_log_reward_component("episode_outcome", delta)
	if won:
		episode_won.emit(delta)
	else:
		episode_lost.emit(delta)

func game_over(reward_delta: float = 0.0) -> void:
	self.reward += reward_delta
	done = true
	needs_reset = true

## Issue #437: whose side does the outcome belong to? The LINKED figure, else
## the spawn snapshot — both survive the figure's own death (a bot can die
## while its team wins). Deliberately NO alive-figure fallback: after the own
## side is wiped, _resolve_figure() would resolve an ENEMY figure and pay the
## wiped side's controller a phantom win. A controller with neither link nor
## snapshot cannot attribute a side at all — no credit (the training loop
## always observes first, so real runs always have the snapshot).
func _resolve_outcome_figure() -> Node2D:
	if not figure_path.is_empty():
		var linked := get_node_or_null(figure_path)
		if linked != null and linked is Node2D:
			return linked
	if is_instance_valid(_spawn_figure):
		return _spawn_figure
	return null

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
	# Issue #659 (task 2): the visible reward trace the issue asks for —
	# one line per landed hit, next to the ACTION EXECUTED trace.
	print("COMBAT REWARD: damage_dealt +%.3f" % bonus)
	damage_dealt.emit(bonus)

## Issue #433: §2.2 — flat kill bonus on the killing blow; the §2.1
## damage tick is deliberately NOT stacked under it (credit_combat_reward
## routes the blow to exactly one of the two).
func _credit_kill() -> void:
	reward += KILL_REWARD
	_log_reward_component("enemy_killed", KILL_REWARD)
	# Issue #659 (task 2): the kill trace — the reward/enemy_killed
	# TensorBoard curve in console form for --viz runs.
	print("COMBAT REWARD: enemy_killed +%.2f" % KILL_REWARD)
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
	# Issue #654: §2.10 conservation upkeep — the turn passed with the
	# team's scarce weapon still in the budget (option value preserved).
	# A state audit like §2.8, not a command audit: it reads the live
	# WeaponInventory ledger, so it needs no _has_ordered gate.
	var saved := _scarce_weapons_saved(figure)
	if saved > 0:
		var applied := SCARCE_WEAPON_SAVED_REWARD * float(saved)
		reward += applied
		_log_reward_component("weapon_saved", applied)
		weapon_saved.emit(applied)

## Issue #654: how many of the team's SCARCE weapons still have unspent
## uses, read from the live WeaponInventory budget (per-team ledger,
## lazily created on first touch — the enemy side's ledger is as real as
## the player's, so both bots audit their own team symmetrically).
func _scarce_weapons_saved(figure: Node2D) -> int:
	var team_id := TurnController.team_id_of(figure)
	var saved := 0
	for w in SCARCE_WEAPON_INDICES:
		if WeaponInventory.weapon_uses_left(team_id, w) > 0:
			saved += 1
	return saved

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

## Issue #469: ship the per-step reward breakdown (REWARD_SPEC §2 component
## names) in the training info dict — the wire the Python-side TensorBoard
## callback aggregates into tdm/reward/<component> curves and the win rate
## (the §2.9 episode_outcome value marks decided episodes). The Sync drains
## the accumulator (get_reward → zero_reward) BEFORE collecting info, so the
## value comes from the snapshot taken in zero_reward(); the live log is
## empty by the time this runs. An empty window (quiet step, nothing fired)
## ships no key — the trainer aggregates only what the env reports. Calls
## super so the base contract (action mask, #410) stays merged in.
func get_info() -> Dictionary:
	var info := super.get_info()
	if not _step_reward_components.is_empty():
		info["reward_components"] = _step_reward_components.duplicate()
	return info

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

## Issue #434/#607: §2.7's neutral command — every head the controller
## translates sits on its neutral value (hold position, hold aim, hold
## fire, no target, no tool).
func _command_all_neutral(command: Dictionary) -> bool:
	return int(command.get("move", MoveCommand.HOLD)) == MoveCommand.HOLD \
			and int(command.get("aim", AimCommand.HOLD)) == AimCommand.HOLD \
			and int(command.get("attack", AttackCommand.HOLD_FIRE)) == AttackCommand.HOLD_FIRE \
			and int(command.get("target", TargetCommand.NONE)) == TargetCommand.NONE \
			and int(command.get("tool", ToolCommand.NONE)) == ToolCommand.NONE

## Issue #433: the framework clears the accumulator per decision step
## (NcnnSync calls zero_reward()) — the §2.1 cap / §2.6 floor budgets
## restart together with it.
func zero_reward() -> void:
	# Issue #469: snapshot the per-step breakdown BEFORE the clear — the
	# Sync collects get_reward()/zero_reward() first and get_info() after,
	# so this copy is what the step message ships to the trainer.
	_step_reward_components = reward_component_log.duplicate()
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
	# Issue #446: the episode reset wipes the shared team blackboard — a
	# fresh episode must not inherit the old one's focus target or HP
	# snapshot. Idempotent: whichever controller resets first, the shared
	# state is empty afterwards.
	TeamBlackboard.reset_blackboard()
	pending_command = _idle_command()
	# Issue #659: a fresh episode starts with no half-executed order and
	# no turn edge — the executor re-arms at the next own turn.
	_exec_active_last = false
	_exec_command = _idle_command()
	_exec_walked = 0.0
	_exec_aimed = 0.0
	_exec_fire_wait = 0.0
	_exec_fired = false
	_exec_failed = false
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

	if _last_reset_frame != Engine.get_process_frames():
		_last_reset_frame = Engine.get_process_frames()
		TurnController.reset_game.call_deferred()

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
	# Issue #607: the full action declaration for the trainer's handshake —
	# five discrete heads, the wire order frozen here and in ACTION_SPEC.md
	# §2: move (6), aim (3), attack (11), target (4), tool (5) = 29 integer
	# slots per decision step. Sizes are enum-driven so the declaration can
	# never drift from the translation below.
	return {
		"move": {"size": MoveCommand.size(), "action_type": "discrete"},
		"aim": {"size": AimCommand.size(), "action_type": "discrete"},
		"attack": {"size": AttackCommand.size(), "action_type": "discrete"},
		"target": {"size": TargetCommand.size(), "action_type": "discrete"},
		"tool": {"size": ToolCommand.size(), "action_type": "discrete"},
	}

## Issue #607: per-head legality mask, the same contract as the training
## scaffold (#410/#422) — one boolean array per discrete head (true =
## legal), auto-shipped in info["action_mask"] by the base class whenever
## this method exists. move, aim and tool are unconditionally legal (a
## jump, an aim step or a tool order is always a well-formed choice; the
## tool quota is spent at EXECUTION by ToolInventory, not by the mask).
## attack slots 1-10 need at least one visible enemy; target index k
## needs the k-th visible enemy to exist. "Visible" reuses this
## controller's own enemy predicate — alive, opposing side, inside
## ATTACK_REACH — ordered nearest-first, the same order the observation
## vector reports enemies in (issue #381), so "target k" and the k-th
## observation enemy slot always name the same figure.
func get_action_mask() -> Dictionary:
	var visible := _visible_enemies_nearest_first()
	# Issue #659: the budget owner of the attack heads — the resolved
	# figure's team (an empty id only when nothing is resolved, in which
	# case `visible` is empty too and every attack slot is illegal).
	var mask_team_id := ""
	var mask_figure := _resolve_alive_figure()
	if mask_figure != null:
		mask_team_id = TurnController.team_id_of(mask_figure)
	var mask := {}
	for key in get_action_space().keys():
		var size: int = get_action_space()[key]["size"]
		var legal: Array = []
		legal.resize(size)
		legal.fill(true)
		if key == "attack":
			# Issue #659 (task 4): a firing slot is legal only while a
			# visible enemy stands in reach AND the team can still PAY
			# for that weapon — the budget-blind mask let the policy
			# order slots Weapon._fire silently refused, burning the
			# whole turn on an impossible input.
			for i in range(1, size):
				legal[i] = not visible.is_empty() \
						and WeaponInventory.can_spend_weapon(mask_team_id, i - 1)
		elif key == "target":
			for k in range(1, size):
				legal[k] = k <= visible.size()
		elif key == "tool":
			# Issue #659 (task 4): tool orders have no executor yet —
			# every tool slot is ILLEGAL (only NONE) so the policy never
			# spends a decision on an order the game would ignore. The
			# head stays in the space (wire compatibility, ACTION_SPEC
			# §2); execution lands with the tools follow-up.
			for i in range(1, size):
				legal[i] = false
		mask[key] = legal
	return mask

## Issue #607: the mask's enemy list — alive opposing figures inside
## ATTACK_REACH, nearest first (distance ties broken by node name, the
## same deterministic order _team_features sorts the observation slots
## with). The k-th entry is the figure TargetCommand.ENEMY_k selects.
func _visible_enemies_nearest_first() -> Array:
	var figure := _resolve_alive_figure()
	if figure == null or not is_inside_tree():
		return []
	var enemies := _enemies_in_reach(figure)
	enemies.sort_custom(func(a, b):
		var da: float = figure.global_position.distance_squared_to(a.global_position)
		var db: float = figure.global_position.distance_squared_to(b.global_position)
		if da == db:
			return String(a.name) < String(b.name)
		return da < db)
	return enemies

## Issue #407/#607: concrete game commands the raw policy indices
## translate into — #607 replaced the two-head set with the full
## repertoire:
## "move" carries every movement command the game offers (the TrainingBot
## scaffold's six, #422: hold, walk right/left, jump, backflip, skip
## turn); "aim" the view-angle adjustment; "attack" selects + fires one
## of the 10 WeaponInventory.WEAPONS slots (index i+1 = WEAPONS[i]; slot
## order pinned by test_issue607); "target" names the enemy an attack is
## aimed at (index k = the k-th of _visible_enemies_nearest_first(), the
## observation vector's order); "tool" spends one of the 4
## ToolInventory.TOOLS (index i+1 = TOOLS[i]: Switch, Teleport, Shield,
## Rock). Resolving nodes, spending quotas and actuating the orders stays
## with the turn-based game loop, exactly the #407 execution model.
enum MoveCommand { HOLD, RIGHT, LEFT, JUMP, BACKFLIP, SKIP_TURN }
enum AimCommand { HOLD, UP, DOWN }
enum AttackCommand {
	HOLD_FIRE,
	FIRE_WEAPON_1, FIRE_WEAPON_2, FIRE_WEAPON_3, FIRE_WEAPON_4, FIRE_WEAPON_5,
	FIRE_WEAPON_6, FIRE_WEAPON_7, FIRE_WEAPON_8, FIRE_WEAPON_9, FIRE_WEAPON_10,
}
enum TargetCommand { NONE, ENEMY_1, ENEMY_2, ENEMY_3 }
enum ToolCommand { NONE, USE_SWITCH, USE_TELEPORT, USE_SHIELD, USE_ROCK }

## Walk direction each MoveCommand maps to (unit vector; distance and
## timing stay with the game loop's turn logic). JUMP, BACKFLIP and
## SKIP_TURN are discrete orders, not walk directions — they carry
## Vector2.ZERO and the game loop reads the "move" index itself.
const MOVE_DIRS := {
	MoveCommand.HOLD: Vector2.ZERO,
	MoveCommand.RIGHT: Vector2.RIGHT,
	MoveCommand.LEFT: Vector2.LEFT,
}

## Issue #407: the translated command the game loop executes on the bot's
## next turn — set_action() rewrites it on every policy decision step.
## Always carries "move" (MoveCommand) + "move_dir" (Vector2), "aim"
## (AimCommand), "attack" (AttackCommand), "target" (TargetCommand) and
## "tool" (ToolCommand); malformed policy output degrades per head to
## the neutral index, never a script error.
var pending_command: Dictionary = {
	"move": MoveCommand.HOLD,
	"move_dir": Vector2.ZERO,
	"aim": AimCommand.HOLD,
	"attack": AttackCommand.HOLD_FIRE,
	"target": TargetCommand.NONE,
	"tool": ToolCommand.NONE,
}

func set_action(action) -> void:
	# Issue #407: NcnnSync (TRAINING mode) calls this once per decision step
	# with the decoded policy output — for a discrete action space a
	# dictionary of action head -> integer index, e.g. {"move": 2,
	# "aim": 1, "attack": 5, "target": 1, "tool": 0}. The indices are
	# translated into the concrete commands above and STORED on the bot:
	# actuation stays with the turn-based game loop, which executes
	# pending_command when the bot's turn comes. The input is defended at
	# the type/range level — garbage degrades per head to the neutral
	# index with a warning, never a script error. Unknown heads (a stale
	# #407-era trainer still emitting "action") are simply ignored: their
	# slot stays neutral.
	if typeof(action) != TYPE_DICTIONARY:
		push_warning(
			"BotController.set_action: expected a Dictionary of action heads, "
			+ "got %s — idling" % type_string(typeof(action)))
		pending_command = _idle_command()
		return
	var move := _head_index(action, "move", MoveCommand.size())
	var aim := _head_index(action, "aim", AimCommand.size())
	var attack := _head_index(action, "attack", AttackCommand.size())
	var target := _head_index(action, "target", TargetCommand.size())
	var tool := _head_index(action, "tool", ToolCommand.size())
	pending_command = {
		"move": move,
		"move_dir": MOVE_DIRS.get(move, Vector2.ZERO),
		"aim": aim,
		"attack": attack,
		"target": target,
		"tool": tool,
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
		"move_dir": Vector2.ZERO,
		"aim": AimCommand.HOLD,
		"attack": AttackCommand.HOLD_FIRE,
		"target": TargetCommand.NONE,
		"tool": ToolCommand.NONE,
	}

## ─────────────────────────────────────────────────────────────────────
## Issue #659: TURN ACTION EXECUTION.
## The #407/#607 execution model ends here: set_action() stores the
## translated order in pending_command, and THIS per-physics-frame
## executor actuates it while the controller's figure is the turn's
## active member — the missing link behind the training report's
## zero-combat / timeout_frac 1.0 symptom (the order was stored on
## every decision step but nothing ever consumed it, so every turn of
## an agent-owned figure burned the whole timer standing still).
## The executor speaks the game's own actuation API — Character
## move/aim/jump and Weapon npc_fire — exactly the Npc.gd scripted-AI
## pattern, so cooldowns, shot quotas, team budgets, the weapon lock
## and the post-shot turn handover all apply to the bot unchanged.

## Issue #659: the aim gate — same tolerance the NPC AI fires through
## (Npc.AIM_TOLERANCE).
const EXEC_AIM_TOLERANCE := 0.12
## Issue #659: seconds of the turn the walk order is applied for — a
## full 3 s idle turn walks the whole arena; a bounded walk leaves the
## policy fine control over positioning.
const EXEC_WALK_DURATION := 1.2
## Issue #659: seconds the aim head slews (≈ the full 0→VIEW_MAX sweep
## at Stats.VIEW_SPEED) before the head counts as finished.
const EXEC_AIM_DURATION := 0.6
## Issue #659: max seconds to wait for the aim to converge onto the
## attack target before firing anyway (a near-enough shot beats a
## stalled turn).
const EXEC_FIRE_GRACE := 1.0

## Issue #659: executor state — the turn-start edge detector, the
## order being executed this turn, and its per-head progress.
var _exec_active_last := false
var _exec_command: Dictionary = _idle_command()
var _exec_walked := 0.0
var _exec_aimed := 0.0
var _exec_fire_wait := 0.0
var _exec_fired := false
var _exec_failed := false

func _physics_process(delta: float) -> void:
	# Issue #659: the executor tick — cheap, and it bails immediately
	# whenever it is not this controller's figure acting.
	var figure := _resolve_alive_figure()
	var active: bool = figure != null \
			and TurnController.active_team != "" \
			and TurnController.active_member == figure \
			and not TurnController.game_over \
			and not TurnController.is_input_frozen()
	if active and not _exec_active_last:
		_begin_execution(figure)
	_exec_active_last = active
	if not active:
		return
	_actuate(figure, delta)

## Issue #659 (task 1): the turn-start hook — consume the pending
## order, trace it (the issue's explicit debug print), and run the
## one-shot orders (jump, skip). Continuous orders (walk, aim, attack)
## are applied per tick in _actuate().
func _begin_execution(figure: Node2D) -> void:
	_exec_command = consume_pending_command()
	_exec_walked = 0.0
	_exec_aimed = 0.0
	_exec_fire_wait = 0.0
	_exec_fired = false
	_exec_failed = false
	print("ACTION EXECUTED: ", _exec_command)
	match int(_exec_command.get("move", MoveCommand.HOLD)):
		MoveCommand.JUMP, MoveCommand.BACKFLIP:
			# No backflip exists in the game's move set yet — the order
			# degrades to its nearest valid neighbour, a plain jump
			# (task 4: an unexecutable order must not waste the turn).
			if figure.has_method("jump"):
				figure.call("jump")
		MoveCommand.SKIP_TURN:
			TurnController.skip_turn(figure)
			_exec_command = _idle_command()

## Issue #659: per-tick actuation of the running turn's order. Every
## head is applied independently (the action space's heads are
## independent dimensions); once every ordered head is finished the
## turn is handed back early instead of burning the timer — the
## timeout_frac 1.0 half of the training report.
func _actuate(figure: Node2D, delta: float) -> void:
	var move_idx := int(_exec_command.get("move", MoveCommand.HOLD))
	var aim_idx := int(_exec_command.get("aim", AimCommand.HOLD))
	var attack_idx := int(_exec_command.get("attack", AttackCommand.HOLD_FIRE))

	# AIM head — slew the view while the order says so.
	var aiming := false
	if aim_idx != AimCommand.HOLD and _exec_aimed < EXEC_AIM_DURATION:
		var direction := 1.0 if aim_idx == AimCommand.UP else -1.0
		figure.call("aim", direction * Stats.VIEW_SPEED * delta)
		_exec_aimed += delta
		aiming = true

	# MOVE head — walk the ordered way for the bounded duration.
	var walking := false
	if (move_idx == MoveCommand.RIGHT or move_idx == MoveCommand.LEFT) \
			and _exec_walked < EXEC_WALK_DURATION:
		figure.call("move", 1.0 if move_idx == MoveCommand.RIGHT else -1.0)
		_exec_walked += delta
		walking = true

	# ATTACK head — slew the view onto the target, then fire the
	# ordered weapon slot through the game's own NPC fire path.
	if attack_idx != AttackCommand.HOLD_FIRE and not _exec_fired \
			and not _exec_failed:
		_execute_attack(figure, attack_idx, delta)

	# Turn economy: all ordered heads finished (jump/skip already ran
	# at turn start) — hand the turn back now. skip_turn is a no-op
	# once a committed shot started the post-shot handover.
	var move_done: bool = move_idx == MoveCommand.HOLD \
			or move_idx == MoveCommand.JUMP or move_idx == MoveCommand.BACKFLIP \
			or move_idx == MoveCommand.SKIP_TURN \
			or _exec_walked >= EXEC_WALK_DURATION
	var attack_done: bool = attack_idx == AttackCommand.HOLD_FIRE \
			or _exec_fired or _exec_failed
	if move_done and not aiming and attack_done:
		TurnController.skip_turn(figure)

## Issue #659: the attack order — resolve the ordered target (falling
## back to the nearest visible enemy when the ordered index expired),
## slew the figure's view onto it, then fire the ordered WeaponInventory
## slot. A fire that cannot happen at all (no weapon node, no target,
## npc_fire refusal) DEGRADES to a finished turn (task 4) — never a
## stall, never a wasted timer.
func _execute_attack(figure: Node2D, attack_idx: int, delta: float) -> void:
	_exec_fire_wait += delta
	var weapon: Node = figure.get_node_or_null("Weapon")
	if weapon == null or not weapon.has_method("npc_fire"):
		_exec_failed = true
		return
	var target := _resolve_attack_target(
			int(_exec_command.get("target", TargetCommand.NONE)))
	if target == null:
		_exec_failed = true
		return
	var desired := _aim_angle_at(figure, target)
	var current := float(figure.get("view_angle"))
	var slewed := move_toward(current,
			clampf(desired, -Stats.VIEW_MAX, Stats.VIEW_MAX),
			Stats.VIEW_SPEED * delta)
	figure.set("view_angle", slewed)
	if absf(desired - slewed) > EXEC_AIM_TOLERANCE \
			and _exec_fire_wait < EXEC_FIRE_GRACE:
		return  # still slewing onto the target
	# Lock the selection to this figure for the rest of the turn — the
	# held-weapon sync (Weapon._physics_process) would otherwise pull
	# selected_weapon back to the team's UI slot before the shot.
	WeaponInventory.lock_for(figure)
	weapon.set("npc_target", target)
	weapon.set("selected_weapon", attack_idx - 1)
	_exec_fired = bool(weapon.call("npc_fire"))
	if not _exec_fired:
		_exec_failed = true

## Issue #659: the ordered target — "target" index k names the k-th of
## _visible_enemies_nearest_first() (the same list the mask and the
## observation slots use). An expired index (the enemy died or left
## reach since the decision) degrades to the nearest visible enemy;
## nobody visible degrades to null (a failed, turn-ending order).
func _resolve_attack_target(target_idx: int) -> Node2D:
	var visible := _visible_enemies_nearest_first()
	if target_idx >= 1 and target_idx <= visible.size():
		return visible[target_idx - 1]
	if not visible.is_empty():
		return visible[0]
	return null

## Issue #659: the view angle that centres the aim on `target` — the
## Npc.gd formula in the figure's own gravity frame (flat training
## ground: the world frame), clamped by the fire path's VIEW_MAX.
func _aim_angle_at(figure: Node2D, target: Node2D) -> float:
	var to_target := target.global_position - figure.global_position
	var grav := Vector2.DOWN
	if figure.has_method("current_gravity"):
		grav = figure.call("current_gravity")
	var tangent := Vector2(grav.y, -grav.x)
	var vertical := to_target.dot(grav)
	var horizontal := absf(to_target.dot(tangent))
	return atan2(-vertical, maxf(horizontal, 1.0))

#func get_obs_space() -> Dictionary:
#	# Override only for complex obs (images, multiple keys). The base class derives
#	# {"obs": {"size": [len], "space": "box"}} from get_obs() automatically.
#	return super.get_obs_space()
