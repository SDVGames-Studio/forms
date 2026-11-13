extends Node
## Regression check for issue #434: the REWARD_SPEC.md §2 positioning
## and survival reward components accumulated on the agent controller.
##
## DoD coverage:
##  - §2.4 survival: +0.02 × hp_fraction at own-turn start — SCALES with
##    the remaining HP (issue DoD), so a half-HP figure keeps half;
##  - §2.5 positioning: potential-based ±0.10 × ΔΦ — ending a turn in
##    cover is measurably better than ending in the open (Φ = fraction of
##    in-reach enemies whose fire line the world geometry occludes; the
##    influence-map half is deferred, fallback clause);
##  - §2.7 idling: −0.05 for an all-neutral turn with an enemy in reach,
##    NEVER on a turn the policy ordered nothing on (§1: no choice);
##  - §2.8 danger tile: −0.05 for ending on open ground under a clear
##    enemy fire line;
##  - camping in cover for a whole turn stays far below the kill reward;
##  - the own figure's death closes the turn (nothing fires after §2.3);
##  - the new signals/value function are declared in
##    get_reward_affordances() and really emitted (§4 manifest).
##
## Run headless: godot --headless res://tests/test_issue434.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")

## Exact expectations (magnitudes straight from REWARD_SPEC.md §2):
const SURVIVAL_FULL := 0.02    # §2.4 at hp 100/100
const SURVIVAL_HALF := 0.01    # §2.4 at hp 50/100 — scales with HP
const SHAPING := 0.10          # §2.5 × |ΔΦ| = 1


## Minimal figure stand-in: alive (health > 0), teamable, shielded flag
## for the observation path (issue #433 stand-in convention).
class FakeFigure extends Node2D:
	var health := 100
	var shielded := false


## A wall on the world collision layer — the tile/props data the cover
## check occludes fire lines with (layer 1 ground, DestructibleGround /
## IndestructibleGround live there).
func _make_wall(at: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)


func _ready() -> void:
	# The cover rays need the wall shapes synced into the physics space.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ok := true

	# --- §2.4/§2.5/§2.7/§2.8: a full idle turn on OPEN ground ----------
	# Neutral order, enemy in reach, no wall: Φ = 0 the whole turn.
	var bot_a: Node2D = Bot.new()
	bot_a.position = Vector2(0, 0)
	add_child(bot_a)
	var fig_a := FakeFigure.new()
	fig_a.position = Vector2(10, 0)
	fig_a.add_to_group("player_team")
	add_child(fig_a)
	var enemy_a := FakeFigure.new()
	enemy_a.position = Vector2(300, 0)
	enemy_a.add_to_group("enemy_team")
	add_child(enemy_a)

	ok = _expect(bot_a.owns_figure(fig_a), "open-ground bot owns its figure") and ok
	ok = _expect(is_equal_approx(bot_a.get_tile_quality(), 0.0),
			"Φ = 0 on open ground in reach, got %s" % bot_a.get_tile_quality()) and ok

	var survival_signals := {"n": 0.0}
	bot_a.survival_per_turn.connect(func(applied: float) -> void: survival_signals.n += 1.0)
	# Lambdas capture plain locals by value — counters ride in dicts (the
	# #433 test convention).
	var idle_signals := {"n": 0}
	bot_a.idle_turn.connect(func(_applied: float) -> void: idle_signals.n += 1)
	var danger_signals := {"n": 0}
	bot_a.danger_tile_turn_end.connect(func(_applied: float) -> void: danger_signals.n += 1)

	bot_a.set_action({"move": 0, "action": 0})  # the policy chose: all-neutral
	bot_a.on_own_turn_started()
	ok = _expect(is_equal_approx(bot_a.reward, SURVIVAL_FULL),
			"§2.4 full-HP survival pays %.2f, got %s" % [SURVIVAL_FULL, bot_a.reward]) and ok
	bot_a.on_own_turn_ended()
	# +0.02 survival − 0.05 idle − 0.05 danger; ΔΦ = 0 shapes nothing.
	ok = _expect(is_equal_approx(bot_a.reward, SURVIVAL_FULL - 0.10),
			"open idle turn nets %.2f, got %s" % [SURVIVAL_FULL - 0.10, bot_a.reward]) and ok
	ok = _expect(survival_signals.n == 1.0, "survival emitted once, got %s" % survival_signals.n) and ok
	ok = _expect(idle_signals.n == 1, "idle_turn emitted once, got %d" % idle_signals.n) and ok
	ok = _expect(danger_signals.n == 1, "danger_tile_turn_end emitted once, got %d" % danger_signals.n) and ok
	# The turn-end audit fires at most once per started turn.
	bot_a.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot_a.reward, SURVIVAL_FULL - 0.10),
			"double turn-end adds nothing, got %s" % bot_a.reward) and ok

	# --- §2.4 (HP scaling) + §2.5: LEAVING cover costs -----------------
	# Wall between the half-HP figure and its enemy: start Φ = 1, end Φ = 0.
	var bot_b: Node2D = Bot.new()
	bot_b.position = Vector2(5000, 0)
	add_child(bot_b)
	var fig_b := FakeFigure.new()
	fig_b.position = Vector2(5010, 0)
	fig_b.health = 50
	fig_b.add_to_group("player_team")
	add_child(fig_b)
	var enemy_b := FakeFigure.new()
	enemy_b.position = Vector2(5300, 0)
	enemy_b.add_to_group("enemy_team")
	add_child(enemy_b)
	_make_wall(Vector2(5150, 0))

	ok = _expect(is_equal_approx(bot_b.get_tile_quality(), 1.0),
			"Φ = 1 behind a wall (fire line occluded), got %s" % bot_b.get_tile_quality()) and ok

	var shaping_signals := {"sum": 0.0}
	bot_b.positioning_credited.connect(func(applied: float) -> void: shaping_signals.sum += applied)

	bot_b.set_action({"move": 1, "action": 0})  # walk: NOT neutral
	bot_b.on_own_turn_started()
	ok = _expect(is_equal_approx(bot_b.reward, SURVIVAL_HALF),
			"§2.4 half-HP survival pays %.2f (scales with HP), got %s" % [SURVIVAL_HALF, bot_b.reward]) and ok
	fig_b.position = Vector2(5010, -200)  # step out: the fire line clears the wall
	ok = _expect(is_equal_approx(bot_b._tile_quality(fig_b), 0.0),
			"Φ = 0 after stepping into the open, got %s" % bot_b._tile_quality(fig_b)) and ok
	bot_b.on_own_turn_ended()
	# +0.01 survival − 0.10 leaving cover − 0.05 danger; no idle (walked).
	ok = _expect(is_equal_approx(bot_b.reward, SURVIVAL_HALF - SHAPING - 0.05),
			"leaving cover nets %.2f, got %s" % [SURVIVAL_HALF - SHAPING - 0.05, bot_b.reward]) and ok
	ok = _expect(is_equal_approx(shaping_signals.sum, -SHAPING),
			"§2.5 shaped −0.10 once, got %s" % shaping_signals.sum) and ok

	# --- §2.5: TAKING cover pays — the DoD contrast ---------------------
	# Same geometry: start in the open, end behind the wall.
	var bot_c: Node2D = Bot.new()
	bot_c.position = Vector2(10000, 0)
	add_child(bot_c)
	var fig_c := FakeFigure.new()
	fig_c.position = Vector2(10010, -200)  # open (fire line clears the wall)
	fig_c.add_to_group("player_team")
	add_child(fig_c)
	var enemy_c := FakeFigure.new()
	enemy_c.position = Vector2(10300, 0)
	enemy_c.add_to_group("enemy_team")
	add_child(enemy_c)
	_make_wall(Vector2(10150, 0))

	ok = _expect(is_equal_approx(bot_c.get_tile_quality(), 0.0),
			"Φ = 0 in the open, got %s" % bot_c.get_tile_quality()) and ok
	bot_c.set_action({"move": 2, "action": 0})  # walk: NOT neutral
	bot_c.on_own_turn_started()
	fig_c.position = Vector2(10010, 0)  # take cover behind the wall
	bot_c.on_own_turn_ended()
	# +0.02 survival + 0.10 taking cover; no danger, no idle.
	ok = _expect(is_equal_approx(bot_c.reward, SURVIVAL_FULL + SHAPING),
			"turn ended in cover nets %.2f, got %s" % [SURVIVAL_FULL + SHAPING, bot_c.reward]) and ok
	# DoD: covered end vs open end differ measurably; camping in cover
	# for a whole turn can never approach the §2.2 kill reward.
	var covered_turn: float = SURVIVAL_FULL + SHAPING
	var open_turn: float = SURVIVAL_FULL - 0.10
	ok = _expect(covered_turn - open_turn >= 0.19,
			"covered end beats open end by ≥ 0.19, got %.2f" % (covered_turn - open_turn)) and ok
	ok = _expect(covered_turn < Bot.KILL_REWARD,
			"best camping turn %.2f < kill %.2f" % [covered_turn, Bot.KILL_REWARD]) and ok

	# --- §2.7: no order this turn ⇒ no choice ⇒ no idle penalty ---------
	var bot_d: Node2D = Bot.new()
	bot_d.position = Vector2(20000, 0)
	add_child(bot_d)
	var fig_d := FakeFigure.new()
	fig_d.position = Vector2(20010, 0)
	fig_d.add_to_group("player_team")
	add_child(fig_d)
	var enemy_d := FakeFigure.new()
	enemy_d.position = Vector2(20300, 0)
	enemy_d.add_to_group("enemy_team")
	add_child(enemy_d)

	var d_idle := {"n": 0}
	bot_d.idle_turn.connect(func(_applied: float) -> void: d_idle.n += 1)
	bot_d.on_own_turn_started()  # controller never got a set_action
	bot_d.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot_d.reward, SURVIVAL_FULL - 0.05),
			"no-choice turn: survival − danger only, got %s" % bot_d.reward) and ok
	ok = _expect(d_idle.n == 0, "silent controller is never idle-punished, got %d" % d_idle.n) and ok

	# --- §2.8: out of the enemy band ⇒ no danger, Φ = 1 (safe tile) -----
	var bot_f: Node2D = Bot.new()
	bot_f.position = Vector2(40000, 0)
	add_child(bot_f)
	var fig_f := FakeFigure.new()
	fig_f.position = Vector2(40010, 0)
	fig_f.add_to_group("player_team")
	add_child(fig_f)
	var enemy_f := FakeFigure.new()
	enemy_f.position = Vector2(40700, 0)  # 690 px away: beyond ATTACK_REACH
	enemy_f.add_to_group("enemy_team")
	add_child(enemy_f)

	ok = _expect(is_equal_approx(bot_f.get_tile_quality(), 1.0),
			"Φ = 1 with no enemy in reach, got %s" % bot_f.get_tile_quality()) and ok
	bot_f.set_action({"move": 0, "action": 0})
	bot_f.on_own_turn_started()
	bot_f.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot_f.reward, SURVIVAL_FULL),
			"out-of-band neutral turn pays only survival, got %s" % bot_f.reward) and ok

	# --- §2.3 interaction: the own death closes the turn ---------------
	var bot_e: Node2D = Bot.new()
	bot_e.position = Vector2(30000, 0)
	add_child(bot_e)
	var fig_e := FakeFigure.new()
	fig_e.position = Vector2(30010, 0)
	fig_e.add_to_group("player_team")
	add_child(fig_e)
	var enemy_e := FakeFigure.new()
	enemy_e.position = Vector2(30300, 0)
	enemy_e.add_to_group("enemy_team")
	add_child(enemy_e)

	bot_e.get_obs()  # the training loop observes first (spawn snapshot)
	bot_e.set_action({"move": 0, "action": 0})
	bot_e.on_own_turn_started()
	fig_e.health = 0
	Bot.notify_figure_died(fig_e)
	bot_e.on_own_turn_ended()  # dead figures owe no turn-end audits
	ok = _expect(is_equal_approx(bot_e.reward, SURVIVAL_FULL + Bot.DEATH_PENALTY),
			"death mid-turn: survival − 0.50 and nothing after, got %s" % bot_e.reward) and ok

	# --- dispatch: TurnController's path through the AGENT group --------
	# A second turn for fig_a via the static boundary the turn loop calls;
	# no fresh order arrived, so this one cannot be "idling" either.
	var reward_before: float = bot_a.reward
	Bot.notify_own_turn_started(fig_a)
	Bot.notify_own_turn_ended(fig_a)
	ok = _expect(is_equal_approx(bot_a.reward - reward_before, SURVIVAL_FULL - 0.05),
			"dispatched turn: survival − danger, no stale-idle, got %s" % (bot_a.reward - reward_before)) and ok

	# --- §4: manifest + real signal emission ----------------------------
	var affordances: Dictionary = bot_a.get_reward_affordances()
	for signal_name in ["survival_per_turn", "positioning_credited", "idle_turn", "danger_tile_turn_end"]:
		ok = _expect(affordances.get("signals", {}).has(signal_name),
				"manifest declares '%s'" % signal_name) and ok
		ok = _expect(bot_a.has_signal(signal_name),
				"controller really emits '%s'" % signal_name) and ok
	ok = _expect(affordances.get("value_functions", {}).has("tile_quality"),
			"manifest declares the 'tile_quality' value function") and ok

	print("ISSUE434 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
