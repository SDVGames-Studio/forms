extends Node
## Regression check for issue #437: episode termination vs. truncation with
## correct reset signaling.
##
## - Termination (elimination): notify_episode_outcome() flags done=true +
##   needs_reset for the framework restart (consumed by the agent's own
##   loop), truncated stays false, §2.9 outcome ±0.50 rides the accumulator —
##   a WIN pays +0.50, a LOSS (draw included) pays −0.50, and a winner-side
##   controller whose own figure died mid-win still collects the win.
## - Truncation (turn limit): crossing reset_after flags truncated=true +
##   done=true with NO terminal reward and a full self-reset — a timeout is
##   never a victory, and a win pays measurably more than a timeout (DoD).
## - Same-frame race: game_over() before the horizon keeps truncated=false;
##   a horizon that fired first is never upgraded into a paid win/loss.
##
## Run headless: godot --headless res://tests/test_issue437.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")
const Stats := preload("res://scripts/CharacterStats.gd")

const SPAWN := Vector2(300, 200)


## Figure stand-in — the same duck-typed surface the #409 stand-in
## carries (obs features + reset() restores + outcome attribution all
## duck-type onto it).
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

	func set_shielded(value: bool) -> void:
		shielded = value


func _ready() -> void:
	var ok := true

	# --- Scenario 1: elimination — one controller per side ----------------
	var winner_bot = Bot.new()
	add_child(winner_bot)
	var winner_figure := FakeFigure.new()
	winner_figure.position = SPAWN
	add_child(winner_figure)
	winner_figure.add_to_group("player_team")
	winner_bot.figure_path = winner_bot.get_path_to(winner_figure)

	var loser_bot = Bot.new()
	add_child(loser_bot)
	var loser_figure := FakeFigure.new()
	loser_figure.position = SPAWN + Vector2(200, 0)
	add_child(loser_figure)
	loser_figure.add_to_group("enemy_team")
	loser_bot.figure_path = loser_bot.get_path_to(loser_figure)

	# The training loop always observes first — that captures the spawn
	# snapshot the outcome attribution resolves the side from.
	winner_bot.get_obs()
	loser_bot.get_obs()
	ok = _expect(winner_bot.owns_figure(winner_figure),
			"winner bot owns its figure") and ok
	ok = _expect(loser_bot.owns_figure(loser_figure),
			"loser bot owns its figure") and ok

	var events := {"won": 0, "lost": 0}
	winner_bot.episode_won.connect(func(_delta): events["won"] += 1)
	winner_bot.episode_lost.connect(func(_delta): events["lost"] += 1)

	# The player team is the sole survivor (enemy side fully eliminated —
	# the loser's figure is dead, exactly what the alive-only resolution
	# must NOT mis-attribute to the other side).
	loser_figure.health = 0
	loser_figure._dead = true
	Bot.notify_episode_outcome("player")

	ok = _expect(winner_bot.get_done() and not winner_bot.get_truncated(),
			"winner: done=true, truncated=false") and ok
	ok = _expect(winner_bot.needs_reset,
			"winner: needs_reset raised for the framework restart") and ok
	ok = _expect(is_equal_approx(winner_bot.reward, 0.50),
			"winner pays +0.50, got %s" % winner_bot.reward) and ok
	ok = _expect(is_equal_approx(
			float(winner_bot.reward_component_log.get("episode_outcome", 0.0)), 0.50),
			"winner outcome logged in the component log") and ok
	winner_bot._physics_process(1.0 / 60.0)  # the agent's own loop tick
	ok = _expect(not winner_bot.needs_reset,
			"winner: needs_reset consumed by the agent's own loop (reset ran)") and ok
	ok = _expect(events["won"] == 1 and events["lost"] == 0,
			"episode_won emitted exactly once (got %d/%d)"
			% [events["won"], events["lost"]]) and ok

	ok = _expect(loser_bot.get_done() and not loser_bot.get_truncated(),
			"loser: done=true, truncated=false") and ok
	ok = _expect(is_equal_approx(loser_bot.reward, -0.50),
			"loser pays -0.50, got %s" % loser_bot.reward) and ok

	# Idempotent: a second notify on the same ended episode pays nothing.
	Bot.notify_episode_outcome("player")
	ok = _expect(is_equal_approx(winner_bot.reward, 0.50),
			"second notify never double-pays (reward %s)" % winner_bot.reward) and ok

	# A dead winner-side figure still wins: the side is resolved from the
	# link/snapshot even after the figure's own death.
	var dead_hero_bot = Bot.new()
	add_child(dead_hero_bot)
	var dead_hero := FakeFigure.new()
	add_child(dead_hero)
	dead_hero.add_to_group("player_team")
	dead_hero_bot.figure_path = dead_hero_bot.get_path_to(dead_hero)
	dead_hero_bot.get_obs()  # snapshot captured while alive
	dead_hero.health = 0
	dead_hero._dead = true
	Bot.notify_episode_outcome("player")
	ok = _expect(is_equal_approx(dead_hero_bot.reward, 0.50),
			"dead winner-side figure still collects the win (+0.50), got %s"
			% dead_hero_bot.reward) and ok

	# Draw (mutual wipe): the own side is wiped, so §2.9 pays the loss.
	var draw_bot = Bot.new()
	add_child(draw_bot)
	var draw_figure := FakeFigure.new()
	add_child(draw_figure)
	draw_figure.add_to_group("enemy_team")
	draw_bot.figure_path = draw_bot.get_path_to(draw_figure)
	draw_bot.get_obs()  # snapshot captured while alive
	draw_figure.health = 0
	draw_figure._dead = true
	Bot.notify_episode_outcome("")
	ok = _expect(is_equal_approx(draw_bot.reward, -0.50),
			"mutual wipe pays the loss (-0.50), got %s" % draw_bot.reward) and ok

	# --- Scenario 2: truncation — the reset_after horizon -----------------
	var timeout_bot = Bot.new()
	add_child(timeout_bot)
	var timeout_figure := FakeFigure.new()
	timeout_figure.position = SPAWN
	add_child(timeout_figure)
	timeout_figure.add_to_group("enemy_team")
	timeout_bot.figure_path = timeout_bot.get_path_to(timeout_figure)
	timeout_bot.get_obs()  # snapshot at the clean start
	# Dirty the world like a long indecisive episode: moved and wounded.
	timeout_figure.position = Vector2(640, 480)
	timeout_figure.health = 17
	timeout_bot.n_steps = timeout_bot.reset_after
	timeout_bot._physics_process(1.0 / 60.0)  # horizon frame: step + self-reset

	ok = _expect(timeout_bot.get_done() and timeout_bot.get_truncated(),
			"horizon: done=true AND truncated=true") and ok
	ok = _expect(not timeout_bot.needs_reset,
			"horizon: needs_reset consumed by the agent's own loop") and ok
	ok = _expect(timeout_figure.position == SPAWN,
			"horizon self-reset restored the figure to spawn") and ok
	ok = _expect(timeout_figure.health == Stats.MAX_HEALTH,
			"horizon self-reset healed the figure") and ok
	ok = _expect(is_equal_approx(timeout_bot.reward, 0.0),
			"truncation pays NO terminal reward, got %s" % timeout_bot.reward) and ok
	ok = _expect(not timeout_bot.reward_component_log.has("episode_outcome"),
			"truncation logs no episode_outcome component") and ok
	ok = _expect(winner_bot.reward > timeout_bot.reward,
			"DoD: a win (+%s) is measurably higher than a timeout (%s)"
			% [winner_bot.reward, timeout_bot.reward]) and ok

	# --- Scenario 3: the same-frame race — terminal outranks the horizon --
	var racer = Bot.new()
	add_child(racer)
	var racer_figure := FakeFigure.new()
	add_child(racer_figure)
	racer_figure.add_to_group("player_team")
	racer.figure_path = racer.get_path_to(racer_figure)
	racer.get_obs()  # snapshot
	racer.n_steps = racer.reset_after
	racer.game_over(0.50)               # terminal first...
	racer._physics_process(1.0 / 60.0)  # ...then the horizon frame
	ok = _expect(racer.get_done() and not racer.get_truncated(),
			"terminal set before the horizon stays a TERMINATION") and ok
	ok = _expect(is_equal_approx(racer.reward, 0.50),
			"the raced episode pays exactly once, got %s" % racer.reward) and ok

	# The horizon-first race: a truncation already ended the episode, so a
	# late terminal notify must not upgrade the timeout into a paid win.
	racer.set_done_false()
	racer.reward = 0.0
	racer.n_steps = racer.reset_after + 1
	racer._physics_process(1.0 / 60.0)  # truncated=true, done=true
	racer.on_episode_outcome("player")
	ok = _expect(racer.get_done() and racer.get_truncated(),
			"truncation is never upgraded into a termination") and ok
	ok = _expect(is_equal_approx(racer.reward, 0.0),
			"a truncated episode never pays the win/loss reward") and ok

	print("ISSUE437 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
