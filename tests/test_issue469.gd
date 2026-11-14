extends Node
## Regression check for issue #469: the per-step reward breakdown reaches
## the Python trainer through the training info dict — the wire the
## TensorBoard callback (training_metrics.py) aggregates into the
## tdm/reward/<component> curves and the win rate (the §2.9
## episode_outcome component marks decided episodes).
##
## The issue's wire contract, verified against the real #433/#434/#436
## credit paths with NcnnSync's exact collection order
## (get_reward() + zero_reward() FIRST, get_info() after — see
## sync.gd _training_process):
##  - after a decision step with reward events, get_info() carries
##    "reward_components": the step's per-component breakdown under the
##    REWARD_SPEC §2 names, summing to the same window the drained
##    reward accumulator reported;
##  - a quiet window (no component fired) ships NO key — the trainer
##    aggregates only what the env actually reports, never fake zeros;
##  - the snapshot is per-step: the second window never repeats the
##    first one's components.
##
## Run headless: godot --headless res://tests/test_issue469.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")

## Magnitudes straight from REWARD_SPEC.md §2 (same representative run as
## tests/test_issue436.gd: open ground, one enemy 290 px away, 40 damage
## mid-idle-turn, then the 60-damage killing blow next turn).
const SURVIVAL_FULL := 0.02    # §2.4 at hp 100/100
const DMG_40 := 0.15 * 0.40    # §2.1 for 40 damage
const KILL := 0.50             # §2.2 flat
const PHI_SWING := 0.10        # §2.5 shaped 0 → 1 when the last enemy drops


## Minimal figure stand-in with the real take_damage wiring (the #433
## attribution path: credit after damage, notify on death).
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

	# Zone (x = 30000): a bot, its player-team figure, and one enemy 290 px
	# away on open ground — inside ATTACK_REACH with a clear fire line, the
	# #435 convention (Φ = 0, danger tile, idling is a choice).
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

	# Decision step 1: idle turn, 40 non-lethal damage — the window carries
	# survival + damage − idle − danger (positioning shapes nothing on flat
	# ground, so it stays absent — a missing key is a ZERO contribution).
	bot.set_action({"move": 0, "action": 0})
	bot.on_own_turn_started()
	foe.take_damage(40, own)
	bot.on_own_turn_ended()

	# NcnnSync's collection order, verbatim: drain the reward (which also
	# zeroes it), THEN collect the info dict.
	var drained: float = bot.get_reward()
	bot.zero_reward()
	var info: Dictionary = bot.get_info()

	ok = _expect(info.has("reward_components"),
			"step 1 info carries the reward breakdown") and ok
	var breakdown: Dictionary = info.get("reward_components", {})
	for component in ["damage_dealt", "survival_per_turn", "idling",
			"danger_tile_turn_end"]:
		ok = _expect(breakdown.has(component),
				"step 1 breakdown carries §2 component '%s' (got %s)"
				% [component, breakdown.keys()]) and ok
	ok = _expect(is_equal_approx(float(breakdown.get("damage_dealt", 0.0)), DMG_40),
			"damage_dealt = §2.1 %.3f, got %s" % [
					DMG_40, breakdown.get("damage_dealt")]) and ok
	ok = _expect(is_equal_approx(_sum(breakdown), drained),
			"breakdown sums to the drained window %.3f, got %.3f" % [
					drained, _sum(breakdown)]) and ok

	# A quiet window (no turn, no combat, nothing fired): no key at all —
	# the trainer must not mistake silence for a reported zero window.
	bot.zero_reward()
	var quiet: Dictionary = bot.get_info()
	ok = _expect(not quiet.has("reward_components"),
			"quiet window ships no reward_components key (got %s)"
			% [quiet.keys()]) and ok

	# Decision step 2: the killing blow — a NEW window (the snapshot is
	# per-step: the first step's components never leak into the second),
	# and it sums to the new drained value, not the old one.
	bot.set_action({"move": 0, "action": 0})
	bot.on_own_turn_started()
	foe.take_damage(60, own)  # 60 >= remaining 60: the killing blow
	bot.on_own_turn_ended()
	var drained2: float = bot.get_reward()
	bot.zero_reward()
	var info2: Dictionary = bot.get_info()
	var breakdown2: Dictionary = info2.get("reward_components", {})
	ok = _expect(breakdown2.has("enemy_killed"),
			"step 2 breakdown carries the kill (got %s)"
			% [breakdown2.keys()]) and ok
	ok = _expect(is_equal_approx(_sum(breakdown2), drained2),
			"step 2 breakdown sums to the new window %.3f, got %.3f" % [
					drained2, _sum(breakdown2)]) and ok
	ok = _expect(is_equal_approx(float(breakdown2.get("enemy_killed", 0.0)), KILL),
			"enemy_killed = §2.2 %.2f, got %s" % [
					KILL, breakdown2.get("enemy_killed")]) and ok
	ok = _expect(is_equal_approx(
			float(breakdown2.get("positioning", 0.0)), PHI_SWING),
			"positioning = §2.5 shaped swing %.2f, got %s" % [
					PHI_SWING, breakdown2.get("positioning")]) and ok

	print("ISSUE469 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _sum(breakdown: Dictionary) -> float:
	var total := 0.0
	for key in breakdown.keys():
		total += float(breakdown[key])
	return total


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		push_error("ISSUE469 FAIL: " + message)
	return cond
