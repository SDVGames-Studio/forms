extends Node
## Regression check for issue #409: reset() restores the bot and its
## figure to a clean episode start — spawn position, full HP, default
## protection (shield off), zeroed cooldowns/velocity/aim, a game-over
## figure revived (death flag down, death tween cancelled), the pending
## command cleared — while the framework's own bookkeeping keeps its base
## behaviour (needs_reset cleared by the core, the reward accumulator
## left to the Sync's zero_reward()).
##
## Run headless: godot --headless res://tests/test_issue409.tscn
## Exit code 0 = pass.

const Bot := preload("res://BotController.gd")
const Stats := preload("res://scripts/CharacterStats.gd")

const SPAWN := Vector2(300, 200)


## Figure stand-in carrying every piece of state reset() touches.
class FakeFigure extends CharacterBody2D:
	const Stats := preload("res://scripts/CharacterStats.gd")

	signal health_changed(health: int, max_health: int)

	var health: int = Stats.MAX_HEALTH
	var _dead := false
	var shielded := false
	var _cooldown_left := 0.0
	var _jump_left := 0.0
	var view_angle := 0.0
	var death_tween: Tween
	var bars_updated: Array = []

	func set_shielded(value: bool) -> void:
		shielded = value

	func _update_bar() -> void:
		bars_updated.append([health, Stats.MAX_HEALTH])


func _ready() -> void:
	var ok := true

	var bot = Bot.new()
	add_child(bot)  # in-tree: AGENT group + figure resolution need the tree

	var figure := FakeFigure.new()
	figure.position = SPAWN
	add_child(figure)
	# enemy_team, so the controller's alive resolution finds the figure.
	figure.add_to_group("enemy_team")

	# The first observation happens at the clean start — it captures the
	# spawn snapshot reset() must restore to.
	var obs: Dictionary = bot.get_obs()
	ok = _expect(obs.has("obs"), "get_obs() returns the flat vector") and ok
	ok = _expect(bot.owns_figure(figure), "controller owns its figure") and ok

	# Dirty the world like a long losing episode: moved, flying, wounded,
	# shielded, cooling down, aiming, dead and mid shrink-out tween.
	figure.position = Vector2(640, 480)
	figure.velocity = Vector2(25.0, -40.0)
	figure.health = 17
	figure.set_shielded(true)
	figure._cooldown_left = 1.2
	figure._jump_left = 0.7
	figure.view_angle = 0.6
	figure._dead = true
	figure.death_tween = figure.create_tween()
	figure.death_tween.tween_property(figure, "scale", Vector2.ZERO, 5.0)
	figure.scale = Vector2(0.4, 0.4)

	# Controller-side leftovers reset() must also clear.
	bot.pending_command = {"move": 1, "action": 2, "move_dir": Vector2.RIGHT}
	bot.needs_reset = true
	bot.reward = 1.0

	bot.reset()

	ok = _expect(figure.position == SPAWN,
			"position restored to spawn, got %s" % figure.position) and ok
	ok = _expect(figure.velocity == Vector2.ZERO,
			"velocity zeroed, got %s" % figure.velocity) and ok
	ok = _expect(figure.health == Stats.MAX_HEALTH,
			"health restored to max, got %s" % figure.health) and ok
	ok = _expect(not figure.shielded, "shield (protection slot) off") and ok
	ok = _expect(figure._cooldown_left == 0.0,
			"fire cooldown cleared, got %s" % figure._cooldown_left) and ok
	ok = _expect(figure._jump_left == 0.0,
			"jump cooldown cleared, got %s" % figure._jump_left) and ok
	ok = _expect(figure.view_angle == 0.0, "aim restored to level") and ok
	ok = _expect(not figure._dead, "game-over figure revived") and ok
	ok = _expect(figure.scale == Vector2.ONE,
			"death shrink-out cancelled, scale %s" % figure.scale) and ok
	ok = _expect(figure.death_tween == null or not figure.death_tween.is_valid(),
			"death tween killed") and ok
	ok = _expect(figure.bars_updated.size() == 1
			and figure.bars_updated[0] == [Stats.MAX_HEALTH, Stats.MAX_HEALTH],
			"health bar redrawn at full") and ok

	# The pending order never survives into the new episode.
	var command: Dictionary = bot.consume_pending_command()
	ok = _expect(command["move"] == 0 and command["action"] == 0,
			"pending command cleared to HOLD/IDLE, got %s" % command) and ok

	# Framework bookkeeping: the core reset ran (needs_reset down) and the
	# reward accumulator is left to the framework's zero_reward().
	ok = _expect(not bot.needs_reset, "core reset cleared needs_reset") and ok
	ok = _expect(bot.get_reward() == 1.0,
			"reset() leaves the reward accumulator alone") and ok

	# Post-reset observation reports a fully-healed, resting bot.
	var fresh: Array = bot.get_obs()["obs"]
	ok = _expect(is_equal_approx(float(fresh[0]), 1.0),
			"post-reset obs reports full HP, got %s" % fresh[0]) and ok

	# The snapshot is stable: a second episode restores the ORIGINAL spawn,
	# not wherever the previous episode ended.
	figure.position = Vector2(900, 700)
	bot.reset()
	ok = _expect(figure.position == SPAWN,
			"second reset restores the original spawn, got %s" % figure.position) and ok

	print("ISSUE409 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
