extends Node
## Regression check for issue #607: BotController's action repertoire
## covers the full game — every movement command (jump, backflip, skip
## turn included), aiming, all 10 WeaponInventory slots, nearest-first
## target selection and all 4 ToolInventory tools.
##
##  1. DECLARATION: get_action_space() declares five discrete heads —
##     move 6, aim 3, attack 11, target 4, tool 5 — in wire order, and
##     the attack/tool enums are pinned to the inventories' slot counts.
##  2. TRANSLATION: set_action() maps every head's index into
##     pending_command (move_dir included), unknown legacy heads are
##     ignored, garbage degrades per head, and consume_pending_command()
##     hands the joint order over once and resets to all-neutral.
##  3. MASK: without enemies every attack slot but hold-fire and every
##     target slot but none is illegal while move/aim stay fully
##     legal; with two enemies in reach the attack head opens up and
##     target k is legal exactly while the k-th nearest enemy exists
##     (nearest-first, the observation vector's order).
##  4. IDLE AUDIT: §2.7's neutral command now spans all five heads.
##
## Run headless: godot --headless res://tests/test_issue607.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")
const WeaponInventoryScript := preload("res://scripts/WeaponInventory.gd")
const ToolInventoryScript := preload("res://scripts/ToolInventory.gd")

var failures := 0


## Duck-typed battlefield figure (the #433/#434 test convention):
## alive, placed, team-grouped.
class FakeFigure extends Node2D:
	var health := 100
	var shielded := false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)


func _ready() -> void:
	# --- 1) declaration -------------------------------------------
	var bot: Node2D = Bot.new()
	var space: Dictionary = bot.get_action_space()
	_check(space.keys() == ["move", "aim", "attack", "target", "tool"],
			"wire order move/aim/attack/target/tool, got %s" % str(space.keys()))
	var want := {"move": 6, "aim": 3, "attack": 11, "target": 4, "tool": 5}
	for head in want:
		_check(space[head]["size"] == want[head]
				and space[head]["action_type"] == "discrete",
				"%s head: size %d discrete, got %s" % [head, want[head], str(space[head])])
	_check(Bot.AttackCommand.size() - 1 == WeaponInventoryScript.WEAPONS.size(),
			"attack enum tracks WeaponInventory.WEAPONS (%d slots)"
			% WeaponInventoryScript.WEAPONS.size())
	_check(Bot.ToolCommand.size() - 1 == ToolInventoryScript.TOOLS.size(),
			"tool enum tracks ToolInventory.TOOLS (%d tools)"
			% ToolInventoryScript.TOOLS.size())
	bot.free()

	# --- 2) translation -------------------------------------------
	bot = Bot.new()
	_check(bot._command_all_neutral(bot.pending_command),
			"fresh bot is all-neutral across the five heads")
	# Every head's non-neutral index maps to its concrete command.
	bot.set_action({"move": 3, "aim": 2, "attack": 5, "target": 2, "tool": 4})
	var order: Dictionary = bot.pending_command
	_check(order["move"] == Bot.MoveCommand.JUMP and order["move_dir"] == Vector2.ZERO,
			"move 3 = JUMP with a zero walk dir, got %s" % str(order))
	_check(order["aim"] == Bot.AimCommand.DOWN, "aim 2 = DOWN, got %s" % str(order["aim"]))
	_check(order["attack"] == Bot.AttackCommand.FIRE_WEAPON_5,
			"attack 5 = FIRE_WEAPON_5 (Mine, WEAPONS[4])")
	_check(order["target"] == Bot.TargetCommand.ENEMY_2, "target 2 = ENEMY_2")
	_check(order["tool"] == Bot.ToolCommand.USE_ROCK, "tool 4 = USE_ROCK")
	# The remaining move commands exist and carry no walk direction.
	for idx in [MoveIdx.BACKFLIP, MoveIdx.SKIP_TURN]:
		bot.set_action({"move": idx})
		_check(bot.pending_command["move"] == idx
				and bot.pending_command["move_dir"] == Vector2.ZERO,
				"move %d keeps a zero walk dir" % idx)
	# A legacy #407-era payload: the unknown "action" head is ignored,
	# the other heads stay neutral.
	bot.set_action({"move": 1, "action": 3})
	var legacy: Dictionary = bot.pending_command
	_check(legacy["move"] == Bot.MoveCommand.RIGHT and not legacy.has("action")
			and legacy["aim"] == Bot.AimCommand.HOLD
			and legacy["attack"] == Bot.AttackCommand.HOLD_FIRE
			and legacy["target"] == Bot.TargetCommand.NONE
			and legacy["tool"] == Bot.ToolCommand.NONE,
			"legacy 'action' head ignored, others neutral")
	# Out-of-range / non-coercible heads degrade to neutral.
	bot.set_action({"move": -3, "aim": 99, "attack": "x", "target": 7, "tool": -1})
	var degraded: Dictionary = bot.pending_command
	_check(degraded["move"] == Bot.MoveCommand.HOLD
			and degraded["aim"] == Bot.AimCommand.HOLD
			and degraded["attack"] == Bot.AttackCommand.HOLD_FIRE
			and degraded["target"] == Bot.TargetCommand.NONE
			and degraded["tool"] == Bot.ToolCommand.NONE,
			"out-of-range heads degrade to neutral")
	# Float indices truncate (foreign decoders emit them), not degrade.
	bot.set_action({"tool": 1.9, "attack": 7.7})
	_check(bot.pending_command["tool"] == Bot.ToolCommand.USE_SWITCH
			and bot.pending_command["attack"] == Bot.AttackCommand.FIRE_WEAPON_7,
			"float indices truncate to the int slot")
	# Non-dictionary payloads fall back to the full idle command.
	bot.set_action(null)
	_check(bot._command_all_neutral(bot.pending_command), "null payload idles")
	bot.set_action("walk")
	_check(bot._command_all_neutral(bot.pending_command), "scalar payload idles")
	# Consume hands the joint order over once, then neutralizes the bot.
	bot.set_action({"move": 5, "attack": 10, "target": 3, "aim": 1})
	var consumed: Dictionary = bot.consume_pending_command()
	_check(consumed["move"] == Bot.MoveCommand.SKIP_TURN
			and consumed["attack"] == Bot.AttackCommand.FIRE_WEAPON_10
			and consumed["target"] == Bot.TargetCommand.ENEMY_3
			and consumed["aim"] == Bot.AimCommand.UP,
			"consume returns the stored joint order")
	_check(bot._command_all_neutral(bot.pending_command),
			"bot neutralizes after consume")
	bot.free()

	# --- 3) mask ---------------------------------------------------
	# The controller fights for the side its figure is NOT in: an
	# enemy_team figure makes player_team figures its enemies.
	var scene_bot: Node2D = Bot.new()
	scene_bot.position = Vector2(0, 0)
	add_child(scene_bot)
	var own := FakeFigure.new()
	own.position = Vector2(10, 0)
	own.add_to_group("enemy_team")
	add_child(own)
	var mask: Dictionary = scene_bot.get_action_mask()
	_check(mask.keys() == ["move", "aim", "attack", "target", "tool"],
			"mask covers the five heads in wire order, got %s" % str(mask.keys()))
	for head in ["move", "aim"]:
		_check(mask[head].size() == want[head] and mask[head].all(func(v): return v),
				"%s fully legal with no enemy in reach" % head)
	# Issue #659: tool orders have no executor yet — every tool slot is
	# masked illegal (only NONE) so the policy never wastes a decision
	# (or a turn) on an order the game would ignore.
	_check(mask["tool"].size() == want["tool"] and mask["tool"][0]
				and not mask["tool"].slice(1).has(true),
				"tool head masked to NONE until tool execution lands (#659)")
	_check(mask["attack"][0] == true and not mask["attack"].slice(1).has(true),
			"no enemy: hold fire legal, weapon slots illegal")
	_check(mask["target"][0] == true and not mask["target"].slice(1).has(true),
			"no enemy: no-target legal, enemy slots illegal")
	# Two enemies in reach (nearest at 300, farther at 500 — both inside
	# ATTACK_REACH 620): attack opens up, target k legal while the k-th
	# nearest enemy exists.
	var near := FakeFigure.new()
	near.position = Vector2(300, 0)
	near.add_to_group("player_team")
	add_child(near)
	var far := FakeFigure.new()
	far.position = Vector2(500, 0)
	far.add_to_group("player_team")
	add_child(far)
	mask = scene_bot.get_action_mask()
	_check(mask["attack"].all(func(v): return v),
			"an enemy in reach makes every weapon slot legal")
	_check(mask["target"][1] == true and mask["target"][2] == true
			and mask["target"][3] == false,
			"two enemies: target 1-2 legal, target 3 illegal")
	var visible: Array = scene_bot._visible_enemies_nearest_first()
	_check(visible.size() == 2 and visible[0] == near and visible[1] == far,
			"targets are nearest-first (300 before 500)")

	# --- 4) idle audit ----------------------------------------------
	var neutral: Dictionary = {
		"move": Bot.MoveCommand.HOLD, "move_dir": Vector2.ZERO,
		"aim": Bot.AimCommand.HOLD, "attack": Bot.AttackCommand.HOLD_FIRE,
		"target": Bot.TargetCommand.NONE, "tool": Bot.ToolCommand.NONE,
	}
	_check(scene_bot._command_all_neutral(neutral),
			"all-neutral across five heads reads neutral")
	var actives := {
		"move": Bot.MoveCommand.JUMP, "aim": Bot.AimCommand.UP,
		"attack": Bot.AttackCommand.FIRE_WEAPON_1,
		"target": Bot.TargetCommand.ENEMY_1,
		"tool": Bot.ToolCommand.USE_SHIELD,
	}
	for head in actives:
		var active: Dictionary = neutral.duplicate()
		active[head] = actives[head]
		_check(not scene_bot._command_all_neutral(active),
				"a non-neutral %s head breaks the idle audit" % head)

	print("ISSUE607 failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)


## Move indices that only exist since #607 (kept out of the loop above
## so a plain int literal stays readable).
enum MoveIdx { BACKFLIP = 4, SKIP_TURN = 5 }
