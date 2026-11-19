extends Node
## Regression check for issue #654: the REWARD_SPEC.md §2.10
## `weapon_saved` conservation upkeep on the agent controller.
##
## DoD coverage:
##  - a turn that ends with the team's railgun budget still unspent pays
##    the +0.01 §2.10 upkeep — signal emitted, component logged;
##  - once the team SPENDS the railgun, the upkeep stops (no signal, no
##    log delta): the reward prices the weapon's option value, not
##    ownership of the slot;
##  - the enemy team's ledger is independent — its bot earns its OWN
##    upkeep until ITS railgun is spent (symmetric sides);
##  - a turn whose controller resolves no alive figure pays no upkeep
##    (the §2.3 convention: death closes the turn);
##  - the signal is declared in get_reward_affordances() (§4 manifest)
##    and really emitted.
##
## Run headless: godot --headless res://tests/test_issue654.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")

## Exact expectations (magnitudes straight from REWARD_SPEC.md §2):
const SURVIVAL_FULL := 0.02    # §2.4 at hp 100/100
const SAVED := 0.01            # §2.10 per scarce weapon while unspent
const RAILGUN := 6             # WeaponInventory.WEAPON_RAILGUN (1 use)


## Minimal figure stand-in: alive (health > 0), teamable, shielded flag
## for the observation path (issue #433 stand-in convention).
class FakeFigure extends Node2D:
	var health := 100
	var shielded := false


func _ready() -> void:
	var ok := true

	# --- Zone 1: player-team bot, its figure, one enemy 690 px away ----
	# Beyond ATTACK_REACH = 620: no idle/danger audit, Φ = 1 all turn,
	# so the turn's math is survival + weapon_saved only.
	var bot: Node2D = Bot.new()
	bot.position = Vector2(0, 0)
	add_child(bot)
	var fig := FakeFigure.new()
	fig.position = Vector2(10, 0)
	fig.add_to_group("player_team")
	add_child(fig)
	var foe := FakeFigure.new()
	foe.position = Vector2(700, 0)
	foe.add_to_group("enemy_team")
	add_child(foe)

	ok = _expect(bot.owns_figure(fig), "player bot owns its figure") and ok

	var saved_signals := {"n": 0, "sum": 0.0}
	bot.weapon_saved.connect(func(applied: float) -> void:
		saved_signals.n += 1
		saved_signals.sum += applied)

	# --- turn 1: railgun unspent → the §2.10 upkeep fires --------------
	bot.set_action({"move": 0, "action": 0})  # ordered, all-neutral
	bot.on_own_turn_started()
	ok = _expect(is_equal_approx(bot.reward, SURVIVAL_FULL),
			"turn 1 start pays §2.4 survival only, got %s" % bot.reward) and ok
	bot.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot.reward, SURVIVAL_FULL + SAVED),
			"turn 1 end adds the §2.10 upkeep %.3f, got %s"
					% [SURVIVAL_FULL + SAVED, bot.reward]) and ok
	ok = _expect(saved_signals.n == 1 and is_equal_approx(saved_signals.sum, SAVED),
			"weapon_saved emitted once with +0.01, got %d / %s"
					% [saved_signals.n, saved_signals.sum]) and ok
	ok = _expect(is_equal_approx(float(bot.reward_component_log.get("weapon_saved", 0.0)), SAVED),
			"component log carries weapon_saved = 0.01") and ok

	# --- the spend: budget empty → the upkeep stops --------------------
	WeaponInventory.spend_weapon(TurnController.TEAM_PLAYER, RAILGUN)
	ok = _expect(WeaponInventory.weapon_uses_left(TurnController.TEAM_PLAYER, RAILGUN) == 0,
			"the player team's railgun budget is spent") and ok
	bot.set_action({"move": 0, "action": 0})
	bot.on_own_turn_started()
	var before_end: float = bot.reward
	bot.on_own_turn_ended()
	ok = _expect(is_equal_approx(bot.reward, before_end),
			"turn 2 end adds no upkeep once the railgun is spent, got %+0.3f"
					% (bot.reward - before_end)) and ok
	ok = _expect(saved_signals.n == 1,
			"no second weapon_saved signal, got %d" % saved_signals.n) and ok
	ok = _expect(is_equal_approx(float(bot.reward_component_log.get("weapon_saved", 0.0)), SAVED),
			"the log's weapon_saved total stays 0.01") and ok

	# --- Zone 2: the enemy team's ledger is independent ---------------
	var enemy_bot: Node2D = Bot.new()
	enemy_bot.position = Vector2(5000, 0)
	add_child(enemy_bot)
	var enemy_fig := FakeFigure.new()
	enemy_fig.position = Vector2(5010, 0)
	enemy_fig.add_to_group("enemy_team")
	add_child(enemy_fig)
	var far_player := FakeFigure.new()  # the enemy bot's foe, out of reach
	far_player.position = Vector2(5700, 0)
	far_player.add_to_group("player_team")
	add_child(far_player)

	ok = _expect(enemy_bot.owns_figure(enemy_fig),
			"enemy bot owns its own figure") and ok
	var enemy_saved := {"n": 0}
	enemy_bot.weapon_saved.connect(func(_applied: float) -> void: enemy_saved.n += 1)
	enemy_bot.on_own_turn_started()
	enemy_bot.on_own_turn_ended()
	ok = _expect(enemy_saved.n == 1,
			"the enemy bot's own unspent railgun still pays ITS upkeep, got %d"
					% enemy_saved.n) and ok
	WeaponInventory.spend_weapon(TurnController.team_id_of(enemy_fig), RAILGUN)
	enemy_bot.on_own_turn_started()
	enemy_bot.on_own_turn_ended()
	ok = _expect(enemy_saved.n == 1,
			"enemy upkeep stops after ITS railgun is spent, got %d"
					% enemy_saved.n) and ok

	# --- no alive figure to resolve ⇒ no upkeep ------------------------
	# Every stand-in leaves the tree: the controller resolves no figure,
	# the turn end closes early (the §2.3 death convention).
	for node in [fig, foe, enemy_fig, far_player]:
		node.free()
	bot.on_own_turn_started()
	bot.on_own_turn_ended()
	ok = _expect(saved_signals.n == 1,
			"figureless turn end pays no upkeep, got %d" % saved_signals.n) and ok

	# --- §4: manifest + real signal emission ---------------------------
	var affordances: Dictionary = bot.get_reward_affordances()
	ok = _expect(affordances.get("signals", {}).has("weapon_saved"),
			"manifest declares 'weapon_saved'") and ok
	ok = _expect(bot.has_signal("weapon_saved"),
			"controller really emits 'weapon_saved'") and ok

	print("ISSUE654 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
