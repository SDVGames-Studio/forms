extends Node
## Regression check for issue #659: combat interactions and reward
## triggers in training.
##
## DoD coverage:
##  - the training scene instances the small flat TrainingArena.tscn
##    (one indestructible ground slab, no walls/hills) and the staged
##    teams stand within 200 px of each other;
##  - the turn executor CONSUMES the pending order on the bot's own
##    turn and actuates it: walk (Character.move), jump, and the attack
##    order (target resolve → view slew → Weapon npc_fire with the
##    ordered WeaponInventory slot);
##  - an impossible attack (no visible enemy, or npc_fire refusal)
##    degrades to a finished turn instead of stalling;
##  - the action mask is budget-aware: a spent weapon slot is illegal,
##    the infinite spear stays legal, tool slots are masked out until
##    tool execution lands;
##  - a landed hit still credits the attacker's controller
##    (damage_dealt / enemy_killed — the reward trigger path).
##
## Run headless: godot --headless res://tests/test_issue659.tscn
## Exit code 0 = pass.

const Bot := preload("res://scripts/BotController.gd")

## WeaponInventory.WEAPONS slot indices the mask/executor map to.
const SLOT_SHOTGUN := 0
const SLOT_SPEAR := 3

## Figure stand-in: alive, teamable, and the exact actuation surface the
## executor speaks (move/aim/jump + view_angle).
class FakeFigure extends Node2D:
	var health := 100
	var view_angle := 0.0
	var move_log: Array = []
	var jump_count := 0

	func move(axis: float) -> void:
		move_log.append(axis)

	func aim(delta_angle: float) -> void:
		view_angle = clampf(view_angle + delta_angle, -1.2, 1.2)

	func jump() -> bool:
		jump_count += 1
		return true

## Weapon stand-in: the npc_fire contract Weapon.gd exposes.
class FakeWeapon extends Node:
	var selected_weapon := 0
	var npc_target: Node2D = null
	var fired_count := 0
	var refuse := false

	func npc_fire() -> bool:
		if refuse:
			return false
		fired_count += 1
		return true

func _ready() -> void:
	var ok := true
	ok = _test_arena() and ok
	var exec_ok: bool = await _test_execution()
	ok = exec_ok and ok
	ok = _test_mask() and ok
	ok = _test_credit() and ok
	print("ISSUE659 ok=", ok)
	get_tree().quit(1 if not ok else 0)

## Task 3: the training arena is small, flat and wall-free, teams close.
func _test_arena() -> bool:
	var ok := true
	var scene_text := FileAccess.get_file_as_string(
			"res://scenes/testing/training_scene.tscn")
	ok = _expect(scene_text.contains("res://scenes/testing/TrainingArena.tscn"),
			"training_scene.tscn instances TrainingArena.tscn") and ok
	ok = _expect(not scene_text.contains("Level1.tscn"),
			"training_scene.tscn no longer instances Level1.tscn") and ok

	var arena: Node2D = load("res://scenes/testing/TrainingArena.tscn").instantiate()
	var grounds := 0
	var destructible := 0
	var figures := {}
	for child in arena.get_children():
		var script: Script = child.get_script()
		if script == null:
			continue
		match script.resource_path:
			"res://scripts/IndestructibleGround.gd":
				grounds += 1
			"res://scripts/DestructibleGround.gd":
				destructible += 1
			"res://scripts/Character.gd":
				figures[str(child.name)] = child
	ok = _expect(grounds == 1,
			"the arena fields exactly one ground slab, got %d" % grounds) and ok
	ok = _expect(destructible == 0,
			"the arena has no destructible geometry") and ok
	ok = _expect(figures.size() == 3,
			"the arena stages three figures, got %d" % figures.size()) and ok
	if figures.has("Player") and figures.has("Team2mate1"):
		var gap: float = (figures["Player"] as Node2D).position.distance_to(
				(figures["Team2mate1"] as Node2D).position)
		ok = _expect(gap <= 200.0,
				"the staged teams are within 200 px, got %.0f" % gap) and ok
	arena.free()
	return ok

## Task 1: the executor consumes and actuates the pending order.
func _test_execution() -> bool:
	var ok := true
	var bot: Node2D = Bot.new()
	bot.position = Vector2(0, 0)
	add_child(bot)
	var fig := FakeFigure.new()
	fig.position = Vector2(10, 0)
	fig.add_to_group("player_team")
	add_child(fig)
	var weapon := FakeWeapon.new()
	weapon.name = "Weapon"
	fig.add_child(weapon)
	var foe := FakeFigure.new()
	foe.position = Vector2(180, 0)
	foe.add_to_group("enemy_team")
	add_child(foe)
	bot.figure_path = bot.get_path_to(fig)

	# --- walk order: consumed + move() driven --------------------------
	bot.set_action({"move": 1})  # RIGHT
	TurnController.active_member = fig
	TurnController.active_team = "player"
	# The physics_frame signal fires BEFORE the physics callbacks of that
	# step — one warm-up await so the assert reads the state AFTER the
	# executor's tick (the setup above ran inside _ready, before any
	# physics step at all).
	await get_tree().physics_frame
	await get_tree().physics_frame
	ok = _expect(int(bot.pending_command["move"]) == 0,
			"walk order was consumed at turn start") and ok
	ok = _expect(fig.move_log.size() >= 1 and float(fig.move_log.back()) > 0.0,
			"walk right order drives Character.move(+1)") and ok
	TurnController.active_member = null
	await get_tree().physics_frame

	# --- jump order: the one-shot actuation ----------------------------
	fig.move_log.clear()
	bot.set_action({"move": 3})  # JUMP
	TurnController.active_member = fig
	await get_tree().physics_frame
	ok = _expect(fig.jump_count == 1,
			"jump order jumps exactly once, got %d" % fig.jump_count) and ok
	TurnController.active_member = null
	await get_tree().physics_frame

	# --- attack order: target resolve + slot select + fire -------------
	fig.jump_count = 0
	bot.set_action({"attack": 2, "target": 1})  # FIRE_WEAPON_2 → WEAPONS[1]
	TurnController.active_member = fig
	await get_tree().physics_frame
	ok = _expect(weapon.fired_count == 1,
			"attack order fires through Weapon.npc_fire, got %d"
					% weapon.fired_count) and ok
	ok = _expect(weapon.selected_weapon == 1,
			"attack index 2 selects WeaponInventory slot 1, got %d"
					% weapon.selected_weapon) and ok
	ok = _expect(weapon.npc_target == foe,
			"the ordered target is handed to the weapon") and ok
	TurnController.active_member = null
	await get_tree().physics_frame

	# --- refused fire: degrade, never stall ----------------------------
	weapon.fired_count = 0
	weapon.refuse = true
	bot.set_action({"attack": 1})
	TurnController.active_member = fig
	await get_tree().physics_frame
	await get_tree().physics_frame
	ok = _expect(weapon.fired_count == 0,
			"a refused npc_fire does not loop-fire") and ok
	ok = _expect(int(bot.pending_command["attack"]) == 0,
			"the refused order was still consumed (turn moves on)") and ok
	TurnController.active_member = null
	await get_tree().physics_frame

	# --- no visible enemy: the attack degrades -------------------------
	foe.position = Vector2(5000, 0)
	bot.set_action({"attack": 1})
	TurnController.active_member = fig
	await get_tree().physics_frame
	ok = _expect(weapon.fired_count == 0,
			"no visible enemy ⇒ no fire attempted") and ok
	TurnController.active_member = null
	TurnController.active_team = ""
	await get_tree().physics_frame

	foe.free()
	fig.free()
	bot.free()
	return ok

## Task 4: budget-aware attack mask, tools masked until executed.
func _test_mask() -> bool:
	var ok := true
	var bot: Node2D = Bot.new()
	add_child(bot)
	var fig := FakeFigure.new()
	fig.position = Vector2(0, 0)
	fig.add_to_group("player_team")
	add_child(fig)
	var foe := FakeFigure.new()
	foe.position = Vector2(150, 0)
	foe.add_to_group("enemy_team")
	add_child(foe)
	bot.figure_path = bot.get_path_to(fig)

	WeaponInventory.reset_uses()
	var mask: Dictionary = bot.get_action_mask()
	var attack: Array = mask["attack"]
	ok = _expect(bool(attack[1]) and bool(attack[SLOT_SPEAR + 1]),
			"attack slots legal with an enemy in reach and budget left") and ok
	for i in range(1, 5):
		ok = _expect(not bool(mask["tool"][i]),
				"tool slot %d masked out until tool execution lands" % i) and ok
	ok = _expect(bool(mask["tool"][0]),
			"tool NONE stays legal") and ok

	# Spend the whole shotgun budget → the slot turns illegal.
	for _i in range(5):
		WeaponInventory.spend_weapon(TurnController.TEAM_PLAYER, SLOT_SHOTGUN)
	mask = bot.get_action_mask()
	attack = mask["attack"]
	ok = _expect(not bool(attack[SLOT_SHOTGUN + 1]),
			"a spent weapon slot is masked illegal") and ok
	ok = _expect(bool(attack[SLOT_SPEAR + 1]),
			"the infinite spear slot stays legal") and ok

	# Enemy out of reach → every firing slot illegal.
	foe.position = Vector2(2000, 0)
	mask = bot.get_action_mask()
	attack = mask["attack"]
	var any_legal := false
	for i in range(1, attack.size()):
		any_legal = any_legal or bool(attack[i])
	ok = _expect(not any_legal,
			"no enemy in reach ⇒ every firing slot illegal") and ok

	foe.free()
	fig.free()
	bot.free()
	return ok

## Task 2: a landed hit credits the attacker's controller.
func _test_credit() -> bool:
	var ok := true
	var bot: Node2D = Bot.new()
	add_child(bot)
	var fig := FakeFigure.new()
	fig.position = Vector2(0, 0)
	fig.add_to_group("player_team")
	add_child(fig)
	var foe := FakeFigure.new()
	foe.position = Vector2(100, 0)
	foe.add_to_group("enemy_team")
	add_child(foe)
	bot.figure_path = bot.get_path_to(fig)

	var damage_signals := {"n": 0}
	bot.damage_dealt.connect(func(_applied: float) -> void: damage_signals.n += 1)
	var kill_signals := {"n": 0}
	bot.enemy_killed.connect(func() -> void: kill_signals.n += 1)

	Bot.credit_combat_reward(fig, foe, 30)
	ok = _expect(damage_signals.n == 1 and bot.reward > 0.0,
			"a landed hit credits damage_dealt to the attacker's bot") and ok

	foe.health = 0
	Bot.credit_combat_reward(fig, foe, 30)
	ok = _expect(kill_signals.n == 1,
			"the killing blow pays the kill bonus") and ok

	foe.free()
	fig.free()
	bot.free()
	return ok

func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
