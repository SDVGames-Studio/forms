extends Node
## Regression check for issue #408: get_reward() returns the controller's
## accumulated reward property (calling it never resets the accumulator);
## game logic (take_damage) credits +1.0 to the attacker's controller on
## a landed hit; the framework's zero_reward() is what clears it.
##
## Run headless: godot --headless res://tests/test_issue408.tscn
## Exit code 0 = pass.

const Bot := preload("res://BotController.gd")


## Minimal figure stand-in: alive (health > 0), teamable, and the same
## take_damage wiring the real figures use — credit the attacker's
## controller when damage lands (issue #408).
class FakeFigure extends Node2D:
	const BotController := preload("res://BotController.gd")

	var health := 50

	func take_damage(amount: int, attacker: Node2D = null) -> void:
		health = maxi(health - amount, 0)
		BotController.credit_hit_reward(attacker)


func _ready() -> void:
	var ok := true

	var bot: Node2D = Bot.new()
	add_child(bot)  # in-tree: AGENT group + figure resolution need the tree

	var shooter := FakeFigure.new()
	shooter.add_to_group("enemy_team")
	add_child(shooter)
	var victim := FakeFigure.new()
	add_child(victim)

	# Fresh accumulator: get_reward() reports 0.0 until an event lands.
	ok = _expect(bot.get_reward() == 0.0,
			"fresh reward is 0.0, got %s" % bot.get_reward()) and ok

	# The controller resolves and owns its nearest alive figure.
	ok = _expect(bot.owns_figure(shooter), "controller owns its figure") and ok

	# Known game event — the bot's figure lands a hit: +1.0 accumulated.
	victim.take_damage(10, shooter)
	ok = _expect(victim.health == 40,
			"victim took the damage, health %s" % victim.health) and ok
	ok = _expect(bot.reward == 1.0,
			"reward after one hit = %s, want 1.0" % bot.reward) and ok
	ok = _expect(bot.get_reward() == 1.0,
			"get_reward() reports the hit") and ok

	# get_reward() never resets: repeated reads report the same total.
	bot.get_reward()
	ok = _expect(bot.get_reward() == 1.0,
			"get_reward() is read-only") and ok

	# Hits without a known attacker change nothing.
	victim.take_damage(10, null)
	ok = _expect(bot.reward == 1.0,
			"anonymous hit earns nothing, reward %s" % bot.reward) and ok

	# The framework's zero_reward() is what clears the accumulator...
	bot.zero_reward()
	ok = _expect(bot.get_reward() == 0.0, "zero_reward() clears") and ok

	# ...and the accumulator keeps working afterwards.
	victim.take_damage(10, shooter)
	ok = _expect(bot.get_reward() == 1.0,
			"accumulator live after clear") and ok

	print("ISSUE408 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
