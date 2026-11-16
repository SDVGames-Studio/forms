extends Node
## Regression check for issue #407: set_action() translates discrete policy
## action indices into concrete game commands stored on the bot, and must
## interpret the issue's sample dictionary correctly while surviving any
## type/range garbage without script errors. The bot is instantiated but
## never added to the tree: set_action() is pure state translation.
##
## Issue #607 widened the two-head contract to five discrete heads
## (move/aim/attack/target/tool — see test_issue607.gd); this file keeps
## guarding the original #407 half: robust index translation and the
## consume-once execution model.
##
## Run headless: godot --headless res://tests/test_issue407.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")


func _ready() -> void:
	var ok := true
	var bot: Node2D = Bot.new()

	# A fresh bot idles until the first policy step arrives.
	ok = _check(bot, "fresh bot idles", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.HOLD_FIRE,
		"move_dir": Vector2.ZERO,
	}) and ok

	# The issue's own sample: {"move": 2, ...} -> walk left, hold fire.
	bot.set_action({"move": 2, "attack": 0})
	ok = _check(bot, "sample {move:2, attack:0}", {
		"move": Bot.MoveCommand.LEFT,
		"attack": Bot.AttackCommand.HOLD_FIRE,
		"move_dir": Vector2.LEFT,
	}) and ok

	# Every command slot maps to its concrete order.
	bot.set_action({"move": 1, "attack": 3})
	ok = _check(bot, "walk right + fire weapon 3", {
		"move": Bot.MoveCommand.RIGHT,
		"attack": Bot.AttackCommand.FIRE_WEAPON_3,
		"move_dir": Vector2.RIGHT,
	}) and ok
	bot.set_action({"move": 0, "attack": 10})
	ok = _check(bot, "fire weapon 10 (circular saw)", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.FIRE_WEAPON_10,
	}) and ok
	bot.set_action({"move": 0, "aim": 2, "tool": 3})
	ok = _check(bot, "aim down + shield", {
		"move": Bot.MoveCommand.HOLD,
		"aim": Bot.AimCommand.DOWN,
		"tool": Bot.ToolCommand.USE_SHIELD,
		"move_dir": Vector2.ZERO,
	}) and ok

	# Range safety: out-of-range indices degrade to the neutral 0 command.
	bot.set_action({"move": 99, "attack": -7})
	ok = _check(bot, "out-of-range indices degrade", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.HOLD_FIRE,
		"move_dir": Vector2.ZERO,
	}) and ok

	# Type safety: float truncates, numeric string coerces — no errors.
	bot.set_action({"move": 1.9, "attack": "2"})
	ok = _check(bot, "float/string coercion", {
		"move": Bot.MoveCommand.RIGHT,
		"attack": Bot.AttackCommand.FIRE_WEAPON_2,
		"move_dir": Vector2.RIGHT,
	}) and ok

	# Missing heads read as the neutral command, not an error.
	bot.set_action({})
	ok = _check(bot, "empty dictionary", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.HOLD_FIRE,
		"move_dir": Vector2.ZERO,
	}) and ok

	# Non-dictionary payloads (null, scalar) fall back to idle — no crash.
	bot.set_action(null)
	ok = _check(bot, "null payload", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.HOLD_FIRE,
	}) and ok
	bot.set_action(3)
	ok = _check(bot, "scalar payload", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.HOLD_FIRE,
	}) and ok

	# The game loop consumes the stored order once, then the bot idles.
	bot.set_action({"move": 1, "attack": 4})
	var consumed: Dictionary = bot.consume_pending_command()
	if consumed.get("move") != Bot.MoveCommand.RIGHT \
			or consumed.get("attack") != Bot.AttackCommand.FIRE_WEAPON_4:
		print("FAIL consume_pending_command returned ", consumed)
		ok = false
	ok = _check(bot, "bot idles after consume", {
		"move": Bot.MoveCommand.HOLD,
		"attack": Bot.AttackCommand.HOLD_FIRE,
		"move_dir": Vector2.ZERO,
	}) and ok

	print("ISSUE407 ok=", ok)
	get_tree().quit(1 if not ok else 0)


## Assert every key of `want` on the bot's pending_command; prints the
## first mismatch. Vector2 values compare approximately.
func _check(bot: Node2D, what: String, want: Dictionary) -> bool:
	var got: Dictionary = bot.pending_command
	for key in want:
		var got_value = got.get(key)
		var want_value = want[key]
		var matches := false
		if want_value is Vector2:
			matches = got_value is Vector2 and (got_value as Vector2).is_equal_approx(want_value)
		else:
			matches = got_value == want_value
		if not matches:
			print("FAIL %s: pending_command[%s] = %s, want %s" % [what, key, got_value, want_value])
			return false
	return true
