extends Node
## Regression check for issue #433: the REWARD_SPEC.md §2 combat reward
## components accumulated on the agent controller.
##
## DoD coverage:
##  - §2.1 damage: +0.15 × damage_fraction, capped at +0.30 per step;
##  - §2.2 kill: +0.50 flat on the killing blow, NOT stacked on the
##    damage tick — killing pays more than the same damage non-lethally;
##  - §2.3 death: −0.50 exactly once, at the moment of the own figure's
##    death, whatever killed it;
##  - §2.6 friendly fire: −0.10 × damage_fraction, floored at −0.30 per
##    step;
##  - zero_reward() restarts the per-step cap/floor budgets;
##  - the four combat signals are declared in get_reward_affordances()
##    and really emitted (§4 manifest + signal emission).
##
## Run headless: godot --headless res://tests/test_issue433.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")

## Damage fractions are damage / MAX_HEALTH (=100), so exact floats:
const DMG_20 := 0.15 * 0.20   # 0.030
const DMG_30 := 0.15 * 0.30   # 0.045
const DMG_100 := 0.15 * 1.00  # 0.150
const FF_20 := -0.10 * 0.20   # -0.020


## Minimal figure stand-in with the real take_damage wiring (issue #433
## attribution path: credit after damage is applied, notify on death).
class FakeFigure extends Node2D:
	const BotController := preload("res://scripts/BotController.gd")

	var health := 100
	var shielded := false  # _own_features reads it (bool(null) would error)
	var _dead := false

	func take_damage(amount: int, attacker: Node2D = null) -> void:
		if _dead:
			return
		health = maxi(health - amount, 0)
		BotController.credit_combat_reward(attacker, self, amount)
		if health == 0:
			_dead = true
			BotController.notify_figure_died(self)


func _ready() -> void:
	var ok := true

	# --- §2.1: proportional damage, per-step cap -----------------------
	# Bot plays an enemy_team shooter; the victim (ungrouped stand-in,
	# i.e. NOT the shooter's team) takes non-lethal damage.
	var bot: Node2D = Bot.new()
	add_child(bot)
	var shooter := FakeFigure.new()
	shooter.position = Vector2(10, 0)
	shooter.add_to_group("enemy_team")
	add_child(shooter)
	var victim := FakeFigure.new()
	victim.health = 1000
	add_child(victim)

	ok = _expect(bot.owns_figure(shooter), "controller owns its shooter") and ok

	victim.take_damage(20, shooter)
	ok = _expect(is_equal_approx(bot.reward, DMG_20),
			"§2.1 20 dmg pays %.3f, got %s" % [DMG_20, bot.reward]) and ok

	# Three 100-damage non-lethal hits inside ONE step: 0.15 each, but
	# the §2.1 cap holds the step total at +0.30.
	victim.take_damage(100, shooter)
	victim.take_damage(100, shooter)
	ok = _expect(is_equal_approx(bot.reward, 0.30),
			"§2.1 per-step cap at 0.30, got %s" % bot.reward) and ok
	victim.take_damage(100, shooter)
	ok = _expect(is_equal_approx(bot.reward, 0.30),
			"capped step stays at 0.30, got %s" % bot.reward) and ok

	# zero_reward() clears the accumulator AND restarts the cap budget.
	bot.zero_reward()
	victim.take_damage(100, shooter)
	ok = _expect(is_equal_approx(bot.reward, DMG_100),
			"cap budget restarts after zero_reward(), got %s" % bot.reward) and ok

	# --- §2.2: kill bonus, not stacked on the damage tick --------------
	# Fresh controller + fresh shooter: a 30-damage killing blow pays
	# exactly +0.50 (no +0.045 damage tick under it) — strictly more
	# than the same 30 damage dealt non-lethally (DoD).
	var kill_bot: Node2D = Bot.new()
	kill_bot.position = Vector2(10000, 0)
	add_child(kill_bot)
	var kill_shooter := FakeFigure.new()
	kill_shooter.position = Vector2(10010, 0)
	kill_shooter.add_to_group("enemy_team")
	add_child(kill_shooter)
	var kill_victim := FakeFigure.new()
	kill_victim.position = Vector2(12000, 0)
	kill_victim.health = 30
	add_child(kill_victim)

	var kills := {"n": 0}
	kill_bot.enemy_killed.connect(func() -> void: kills.n += 1)
	var hits := {"n": 0}
	kill_bot.damage_dealt.connect(func(_applied: float) -> void: hits.n += 1)

	kill_victim.take_damage(30, kill_shooter)
	ok = _expect(is_equal_approx(kill_bot.reward, Bot.KILL_REWARD),
			"§2.2 killing blow pays exactly %.2f, got %s" % [Bot.KILL_REWARD, kill_bot.reward]) and ok
	ok = _expect(kill_bot.reward > DMG_30,
			"kill (%s) beats same non-lethal damage (%s)" % [kill_bot.reward, DMG_30]) and ok
	ok = _expect(kills.n == 1, "enemy_killed emitted once, got %d" % kills.n) and ok
	ok = _expect(hits.n == 0, "no damage_dealt tick under the kill, got %d" % hits.n) and ok

	# --- §2.3: own-figure death penalty, exactly once -------------------
	# The controller must have resolved its figure once (the training
	# loop observes before events); then the figure dies to an attacker
	# no controller owns — the penalty still fires, once.
	var death_bot: Node2D = Bot.new()
	death_bot.position = Vector2(20000, 0)
	add_child(death_bot)
	var own_figure := FakeFigure.new()
	own_figure.position = Vector2(20010, 0)
	own_figure.add_to_group("enemy_team")
	own_figure.health = 10
	add_child(own_figure)
	var stranger := FakeFigure.new()
	stranger.position = Vector2(30000, 0)
	add_child(stranger)

	death_bot.get_obs()  # resolve + snapshot the controlled figure
	ok = _expect(death_bot.owns_figure(own_figure),
			"death bot owns its figure while alive") and ok

	var deaths := {"n": 0}
	death_bot.own_figure_died.connect(func() -> void: deaths.n += 1)
	own_figure.take_damage(10, stranger)
	ok = _expect(is_equal_approx(death_bot.reward, Bot.DEATH_PENALTY),
			"§2.3 death pays %.2f, got %s" % [Bot.DEATH_PENALTY, death_bot.reward]) and ok
	ok = _expect(deaths.n == 1, "own_figure_died emitted once, got %d" % deaths.n) and ok
	# Hitting the corpse is a no-op: the penalty can never stack.
	own_figure.take_damage(10, stranger)
	ok = _expect(is_equal_approx(death_bot.reward, Bot.DEATH_PENALTY),
			"death penalty applied exactly once, got %s" % death_bot.reward) and ok

	# --- §2.6: friendly fire, per-step floor ----------------------------
	var ff_bot: Node2D = Bot.new()
	ff_bot.position = Vector2(40000, 0)
	add_child(ff_bot)
	var ff_shooter := FakeFigure.new()
	ff_shooter.position = Vector2(40010, 0)
	ff_shooter.add_to_group("enemy_team")
	add_child(ff_shooter)
	var ff_victim := FakeFigure.new()
	ff_victim.position = Vector2(41000, 0)
	ff_victim.add_to_group("enemy_team")
	ff_victim.health = 1000
	add_child(ff_victim)

	var ff_signals := {"n": 0}
	ff_bot.friendly_fire.connect(func(_applied: float) -> void: ff_signals.n += 1)

	ff_victim.take_damage(20, ff_shooter)
	ok = _expect(is_equal_approx(ff_bot.reward, FF_20),
			"§2.6 20 friendly dmg pays %.3f, got %s" % [FF_20, ff_bot.reward]) and ok
	ok = _expect(ff_signals.n == 1, "friendly_fire emitted, got %d" % ff_signals.n) and ok

	# Four 100-damage friendly hits inside ONE step: −0.10 each (−0.02 −0.40
	# unfloored), so the §2.6 floor clamps the step total at −0.30.
	ff_victim.take_damage(100, ff_shooter)
	ff_victim.take_damage(100, ff_shooter)
	ok = _expect(is_equal_approx(ff_bot.reward, -0.22),
			"unfloored friendly step at -0.22, got %s" % ff_bot.reward) and ok
	ff_victim.take_damage(100, ff_shooter)
	ok = _expect(is_equal_approx(ff_bot.reward, -0.30),
			"§2.6 per-step floor at -0.30, got %s" % ff_bot.reward) and ok
	ff_victim.take_damage(100, ff_shooter)
	ok = _expect(is_equal_approx(ff_bot.reward, -0.30),
			"floored step stays at -0.30, got %s" % ff_bot.reward) and ok

	# --- §4: manifest + real signal emission ----------------------------
	var affordances: Dictionary = bot.get_reward_affordances()
	for signal_name in ["damage_dealt", "enemy_killed", "own_figure_died", "friendly_fire"]:
		ok = _expect(affordances.get("signals", {}).has(signal_name),
				"manifest declares '%s'" % signal_name) and ok
		ok = _expect(bot.has_signal(signal_name),
				"controller really emits '%s'" % signal_name) and ok

	print("ISSUE433 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
