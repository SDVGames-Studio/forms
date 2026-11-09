extends Node
## Regression check for issue #435: the REWARD_SPEC.md §2 penalty
## components — friendly fire (§2.6), idling (§2.7) and the danger-tile
## turn end (§2.8) — applied as negative reward on the agent controller.
##
## The penalty paths themselves landed with #433 (combat attribution)
## and #434 (turn-end audits); this slice verifies the issue's DoD
## against them end to end:
##  - a friendly-fire event produces a NET-NEGATIVE reward for that
##    step, and the §2.6 per-step floor mirrors the §2.1 per-step cap
##    (|−0.30| = +0.30 — the spec's encoding of the issue's "penalty ≥
##    damage-dealt reward": the worst careless step can never outweigh
##    the best clean damage step, REWARD_SPEC §3);
##  - idling for consecutive turns produces an INCREASINGLY NEGATIVE
##    total (−0.05 per audited idle turn, flat per turn — alternating
##    idle with action cannot launder it, every idle turn pays its own);
##  - the danger-zone end-of-turn penalty is triggered in this scripted
##    scenario (open ground under a clear enemy fire line) and stays
##    silent when a wall occludes the fire line (Φ = 1, cover);
##  - the three penalty signals are declared in
##    get_reward_affordances() and really emitted (§4 manifest).
##
## Run headless: godot --headless res://tests/test_issue435.tscn
## Exit code 0 = pass.

const Bot := preload("res://BotController.gd")

## Exact expectations, magnitudes straight from REWARD_SPEC.md §2:
const SURVIVAL_FULL := 0.02    # §2.4 at hp 100/100
const FF_20 := -0.10 * 0.20    # §2.6 for 20 damage
## One open-ground idle turn: +0.02 survival − 0.05 idle − 0.05 danger
## (ΔΦ = 0 shapes nothing; the enemy is in reach with a clear line).
const IDLE_TURN_NET := SURVIVAL_FULL - 0.05 - 0.05


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


## A wall on the world collision layer — the tile/props data the cover
## check occludes fire lines with (the #434 convention).
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
	var ok := true

	# --- §2.6: a friendly-fire event is a net-negative step ----------
	var ff_bot: Node2D = Bot.new()
	ff_bot.position = Vector2(0, 0)
	add_child(ff_bot)
	var shooter := FakeFigure.new()
	shooter.position = Vector2(10, 0)
	shooter.add_to_group("enemy_team")
	add_child(shooter)
	var ally := FakeFigure.new()
	ally.position = Vector2(300, 0)
	ally.add_to_group("enemy_team")  # the shooter's own team
	add_child(ally)

	var ff_fired := {"n": 0}
	ff_bot.friendly_fire.connect(func(_applied: float) -> void: ff_fired.n += 1)

	ally.take_damage(20, shooter)
	ok = _expect(ff_bot.reward < 0.0,
			"§2.6 friendly-fire step is net-negative, got %s" % ff_bot.reward) and ok
	ok = _expect(is_equal_approx(ff_bot.reward, FF_20),
			"§2.6 20 friendly dmg pays %.3f, got %s" % [FF_20, ff_bot.reward]) and ok
	ok = _expect(ff_fired.n == 1, "friendly_fire emitted, got %d" % ff_fired.n) and ok
	# The issue's "penalty ≥ damage-dealt reward" per REWARD_SPEC: the
	# §2.6 per-STEP floor mirrors the §2.1 per-STEP cap, so a careless
	# blast can never outweigh the best clean damage step.
	ok = _expect(absf(Bot.FRIENDLY_FIRE_STEP_FLOOR) >= Bot.DAMAGE_REWARD_STEP_CAP,
			"§2.6 floor %.2f ≥ §2.1 cap %.2f" % [
					absf(Bot.FRIENDLY_FIRE_STEP_FLOOR),
					Bot.DAMAGE_REWARD_STEP_CAP]) and ok

	# --- §2.7: consecutive idle turns — increasingly negative ---------
	var idle_bot: Node2D = Bot.new()
	idle_bot.position = Vector2(10000, 0)
	add_child(idle_bot)
	var fig := FakeFigure.new()
	fig.position = Vector2(10010, 0)
	fig.add_to_group("player_team")
	add_child(fig)
	var enemy := FakeFigure.new()
	enemy.position = Vector2(10300, 0)  # 290 px: inside ATTACK_REACH
	enemy.add_to_group("enemy_team")
	add_child(enemy)

	var idle_fired := {"n": 0}
	var danger_fired := {"n": 0}
	idle_bot.idle_turn.connect(func(_applied: float) -> void: idle_fired.n += 1)
	idle_bot.danger_tile_turn_end.connect(func(_applied: float) -> void: danger_fired.n += 1)

	# The cover/danger rays need the wall shapes synced into the physics
	# space (#434 convention) — build the cover scenario BEFORE waiting.
	var cover_bot: Node2D = Bot.new()
	cover_bot.position = Vector2(20000, 0)
	add_child(cover_bot)
	var cover_fig := FakeFigure.new()
	cover_fig.position = Vector2(20010, 0)
	cover_fig.add_to_group("player_team")
	add_child(cover_fig)
	var cover_enemy := FakeFigure.new()
	cover_enemy.position = Vector2(20300, 0)
	cover_enemy.add_to_group("enemy_team")
	add_child(cover_enemy)
	_make_wall(Vector2(20150, 0))  # between the figure and its enemy

	await get_tree().physics_frame
	await get_tree().physics_frame

	ok = _expect(is_equal_approx(idle_bot.get_tile_quality(), 0.0),
			"open-ground Φ = 0 (enemy holds a clear fire line), got %s" % idle_bot.get_tile_quality()) and ok

	for turn in 3:
		idle_bot.set_action({"move": 0, "action": 0})  # the policy chose: all-neutral
		idle_bot.on_own_turn_started()
		var before_end: float = idle_bot.reward
		idle_bot.on_own_turn_ended()
		ok = _expect(idle_bot.reward < before_end,
				"idle turn %d drops the total: %s < %s" % [turn + 1, idle_bot.reward, before_end]) and ok
		ok = _expect(is_equal_approx(idle_bot.reward, IDLE_TURN_NET * (turn + 1)),
				"%d idle turns total %.2f, got %s" % [turn + 1, IDLE_TURN_NET * (turn + 1), idle_bot.reward]) and ok
	ok = _expect(idle_fired.n == 3, "idle_turn emitted 3×, got %d" % idle_fired.n) and ok

	# --- §2.8: the danger-zone penalty, scripted ----------------------
	# Every open-ground turn above ended inside the enemy's clear
	# line-of-fire band — the issue's danger-zone DoD scenario:
	ok = _expect(danger_fired.n == 3, "danger_tile_turn_end emitted 3×, got %d" % danger_fired.n) and ok

	# Negative control: a turn ended in COVER (the wall occludes the
	# fire line, Φ = 1) pays neither turn-end penalty — only survival.
	ok = _expect(is_equal_approx(cover_bot.get_tile_quality(), 1.0),
			"cover Φ = 1 behind the wall, got %s" % cover_bot.get_tile_quality()) and ok
	cover_bot.set_action({"move": 1, "action": 0})  # movement, not idling
	cover_bot.on_own_turn_started()
	cover_bot.on_own_turn_ended()
	ok = _expect(is_equal_approx(cover_bot.reward, SURVIVAL_FULL),
			"covered moving turn pays only survival %.2f, got %s" % [SURVIVAL_FULL, cover_bot.reward]) and ok

	# --- §4: manifest + real signal emission --------------------------
	var affordances: Dictionary = idle_bot.get_reward_affordances()
	for signal_name in ["friendly_fire", "idle_turn", "danger_tile_turn_end"]:
		ok = _expect(affordances.get("signals", {}).has(signal_name),
				"manifest declares '%s'" % signal_name) and ok
		ok = _expect(idle_bot.has_signal(signal_name),
				"controller really emits '%s'" % signal_name) and ok

	print("ISSUE435 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
