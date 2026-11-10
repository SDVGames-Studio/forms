extends Node
## Regression check for issue #436: the final stage of the reward
## pipeline — normalize/clip the per-step return (REWARD_SPEC §3) and log
## each component's contribution (§2) in a debug dictionary on the
## controller.
##
## The issue's DoD, verified end to end against the real #433/#434
## wiring (attribution path, turn audits, shaping):
##  - over a full scripted sample episode, the absolute value of the
##    value returned by get_reward() NEVER exceeds the §3 bound
##    (REWARD_CLIP_BOUND = 1.0), including a multi-kill step whose RAW
##    accumulator sum exceeds +1.0 (two kills + survival + shaped Φ
##    swing in one decision step) and emulated terminal steps stacking
##    the §2.9 outcome on §3's best/worst rows;
##  - the per-component log shows non-zero contributions from at least
##    three distinct components in the representative run (it shows
##    six: damage_dealt, enemy_killed, survival_per_turn, positioning,
##    idling, danger_tile_turn_end);
##  - the log always sums back to the RAW accumulator (the clip is a
##    read-side guarantee, it never mutates the property) and resets at
##    exactly the moment the reward property is cleared (zero_reward()).
##
## Run headless: godot --headless res://tests/test_issue436.tscn
## Exit code 0 = pass.

const Bot := preload("res://BotController.gd")

## Exact expectations, magnitudes straight from REWARD_SPEC.md §2:
const SURVIVAL_FULL := 0.02    # §2.4 at hp 100/100
const DMG_40 := 0.15 * 0.40    # §2.1 for 40 damage
const KILL := 0.50             # §2.2 flat
const IDLE := -0.05            # §2.7
const DANGER := -0.05          # §2.8
## Step 1 of the representative run: survival + 40 damage − idle −
## danger (open ground, ΔΦ = 0 shapes nothing).
const STEP1_NET := SURVIVAL_FULL + DMG_40 + IDLE + DANGER
## Step 2: survival + the killing blow (+0.50, no damage tick under it,
## §2.2) + the shaped Φ swing 0 → 1 when the last enemy drops.
const STEP2_NET := SURVIVAL_FULL + KILL + 0.10


## Minimal figure stand-in with the real take_damage wiring (the #433
## attribution path: credit after damage, notify on death).
class FakeFigure extends Node2D:
	const BotController := preload("res://BotController.gd")

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


## Every decision step's clipped return — the DoD's "never exceeds the
## documented bound" is asserted over this whole episode transcript.
var _step_returns: Array = []


func _ready() -> void:
	var ok := true

	# --- the representative run: two scripted decision steps ----------
	# Zone 1 (x = 30000): a bot, its player-team figure, and one enemy
	# 290 px away on open ground (inside ATTACK_REACH, clear fire line —
	# the #435 convention: Φ = 0, danger tile, idling is a choice).
	var bot: Node2D = Bot.new()
	bot.position = Vector2(30000, 0)
	add_child(bot)
	var own := FakeFigure.new()
	own.position = Vector2(30010, 0)
	own.add_to_group("player_team")
	add_child(own)
	var foe := FakeFigure.new()
	foe.position = Vector2(30290, 0)
	foe.add_to_group("enemy_team")
	add_child(foe)

	# The Φ / danger rays need the physics space synced (#434 convention).
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Decision step 1: the policy idles on a danger tile and lands a
	# non-lethal 40-damage hit mid-turn.
	bot.set_action({"move": 0, "action": 0})  # all-neutral: the policy chose
	bot.on_own_turn_started()
	foe.take_damage(40, own)
	bot.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot.reward, STEP1_NET),
			"step 1 raw %.3f, got %s" % [STEP1_NET, bot.reward]) and ok
	ok = _expect(is_equal_approx(bot.get_reward(), STEP1_NET),
			"step 1 (inside the bound) returns unclipped, got %s" % bot.get_reward()) and ok
	_step_returns.append(bot.get_reward())

	# Per-component log, step 1: the issue's second DoD — non-zero
	# contributions from ≥ 3 distinct components in ONE representative
	# step (here: damage_dealt, survival_per_turn, idling,
	# danger_tile_turn_end).
	var log1: Dictionary = bot.reward_component_log.duplicate()
	var nonzero1 := 0
	for key in log1.keys():
		if not is_zero_approx(float(log1[key])):
			nonzero1 += 1
	ok = _expect(nonzero1 >= 3,
			"step 1 logs %d non-zero components (DoD: ≥ 3): %s" % [nonzero1, log1]) and ok
	ok = _expect(is_equal_approx(_log_sum(log1), bot.reward),
			"log sums to the raw accumulator %s, got %s" % [bot.reward, _log_sum(log1)]) and ok
	# The keys are the spec's §2 component names.
	for component in ["damage_dealt", "survival_per_turn", "idling", "danger_tile_turn_end"]:
		ok = _expect(log1.has(component),
				"step 1 log carries §2 component '%s'" % component) and ok

	# zero_reward(): the log clears at the SAME moment the reward
	# property does — the framework collects, then clears both.
	bot.zero_reward()
	ok = _expect(is_zero_approx(bot.reward) and bot.reward_component_log.is_empty(),
			"zero_reward() clears reward and log together") and ok

	# Decision step 2: the killing blow — §2.2 pays the kill alone (no
	# §2.1 tick stacked), and §2.5's shaped potential swings 0 → 1 as the
	# last enemy drops (no enemy in reach ⇒ Φ = 1).
	bot.set_action({"move": 0, "action": 0})
	bot.on_own_turn_started()
	foe.take_damage(60, own)  # 60 ≥ remaining 60: the killing blow
	bot.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot.reward, STEP2_NET),
			"step 2 raw %.3f, got %s" % [STEP2_NET, bot.reward]) and ok
	_step_returns.append(bot.get_reward())
	var log2: Dictionary = bot.reward_component_log.duplicate()
	ok = _expect(log2.has("enemy_killed") and log2.has("positioning"),
			"step 2 logs the kill and the shaped Φ swing: %s" % log2) and ok
	bot.zero_reward()

	# Across the whole episode: six distinct components contributed.
	var episode_log: Dictionary = {}
	for key in log1.keys():
		episode_log[key] = log1[key]
	for key in log2.keys():
		episode_log[key] = episode_log.get(key, 0.0) + log2[key]
	var episode_nonzero := 0
	for key in episode_log.keys():
		if not is_zero_approx(float(episode_log[key])):
			episode_nonzero += 1
	ok = _expect(episode_nonzero >= 3,
			"episode logs %d non-zero components (DoD: ≥ 3): %s" % [episode_nonzero, episode_log]) and ok

	# --- §3: a step whose RAW sum exceeds the bound --------------------
	# Zone 2 (x = 50000): two enemies die to the agent inside ONE
	# decision step — §3's table budgets a single kill, so the raw
	# accumulator crosses +1.0 and get_reward() must return exactly the
	# bound while the property keeps its raw value.
	var streak: Node2D = Bot.new()
	streak.position = Vector2(50000, 0)
	add_child(streak)
	var own2 := FakeFigure.new()
	own2.position = Vector2(50010, 0)
	own2.add_to_group("player_team")
	add_child(own2)
	var foe_a := FakeFigure.new()
	foe_a.position = Vector2(50290, 0)
	foe_a.add_to_group("enemy_team")
	add_child(foe_a)
	var foe_b := FakeFigure.new()
	foe_b.position = Vector2(50500, 0)
	foe_b.add_to_group("enemy_team")
	add_child(foe_b)

	streak.set_action({"move": 1, "action": 0})  # movement: no idle audit
	streak.on_own_turn_started()
	foe_a.take_damage(100, own2)  # killing blows: §2.2 twice in one step
	foe_b.take_damage(100, own2)
	streak.on_own_turn_ended()
	ok = _expect(streak.reward > Bot.REWARD_CLIP_BOUND,
			"multi-kill raw step exceeds the bound (%s > %s)" % [
					streak.reward, Bot.REWARD_CLIP_BOUND]) and ok
	ok = _expect(is_equal_approx(streak.get_reward(), Bot.REWARD_CLIP_BOUND),
			"multi-kill step returns exactly the bound, got %s" % streak.get_reward()) and ok
	ok = _expect(streak.reward > streak.get_reward(),
			"the clip is read-side only — the raw property survives") and ok
	ok = _expect(is_equal_approx(_log_sum(streak.reward_component_log), streak.reward),
			"the log still sums to the RAW value across the clip") and ok
	_step_returns.append(streak.get_reward())
	streak.zero_reward()

	# --- §3: terminal steps clip to ±1.0 before logging ----------------
	# Zone 3: the §2.9 episode_outcome signals are not emitted yet, so
	# the terminal rows of the §3 table are emulated by stacking the
	# documented ±0.50 outcome on §3's best/worst step sums directly on
	# the accumulator (the only input get_reward() has).
	var terminal: Node2D = Bot.new()
	terminal.position = Vector2(70000, 0)
	add_child(terminal)
	terminal.reward = 0.92 + 0.50  # best non-terminal step + win outcome
	ok = _expect(is_equal_approx(terminal.get_reward(), 1.0),
			"terminal +1.42 clips to +1.0, got %s" % terminal.get_reward()) and ok
	terminal.reward = -0.90 - 0.50  # worst non-terminal step + loss outcome
	ok = _expect(is_equal_approx(terminal.get_reward(), -1.0),
			"terminal −1.40 clips to −1.0, got %s" % terminal.get_reward()) and ok

	# --- the episode transcript: |r| never exceeds the bound -----------
	for i in _step_returns.size():
		ok = _expect(absf(_step_returns[i]) <= Bot.REWARD_CLIP_BOUND,
				"episode step %d return %s within ±%s" % [
						i + 1, _step_returns[i], Bot.REWARD_CLIP_BOUND]) and ok

	print("ISSUE436 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _log_sum(log: Dictionary) -> float:
	var total := 0.0
	for key in log.keys():
		total += float(log[key])
	return total


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
