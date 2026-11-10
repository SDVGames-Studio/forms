extends Node
## Regression check for issue #364: items at the game level —
##  - the bundle rolls: a weapon bundle never rolls the spear, every
##    other weapon is possible, the shotgun drops more often than the
##    railgun; a tool bundle rolls every tool, the switch more often
##    than the teleport; neither can roll "nothing" (0 is impossible
##    only by the weight table — every roll lands on a real item).
##  - pickups: a first aid kit heals 60 HP capped at MAX_HEALTH, a
##    weapon bundle adds exactly +1 weapon use to the taking TEAM, a
##    tool bundle +1 tool use.
##  - destructibility: an item has 1 HP — one point of damage detonates
##    it with the grenade's COPIED values (100 px radius / 40 damage)
##    and chain-detonates a neighbour item.
##  - round drop: wrapping the turn order starts round 2 — one item
##    may appear (a seeded 25% roll, issue #375) right ON a ground
##    surface, where it rests.
##
## Run headless: godot --headless res://tests/test_issue364.tscn
## Exit code 0 = pass.

const SPEAR := 3
const ROLLS := 600

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE364 %s — %s" % ["ok" if ok else "FAIL", what])


## Issue #364: spawn an item of the given kind next to a figure and wait
## until it is gone (picked up or detonated) — at most ~2 s of frames.
func _pickup_item(kind: int, near: Node2D) -> void:
	var level: Node = get_tree().get_first_node_in_group("level")
	var item := LevelItem.new()
	item.kind = kind
	item.global_position = near.global_position + Vector2(34, 0)
	level.add_child(item)
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(item):
			return


## Issue #364: true when the spot 70 px LEFT of the victim keeps more
## distance to every other figure than the right one — the explosion
## pair goes to the clearer side, out of every pickup radius.
func _left_is_clearer(victim: Node2D) -> bool:
	var best_side := 1.0
	var best_clear := -1.0
	for side in [-1.0, 1.0]:
		var spot := victim.global_position + Vector2(side * 70.0, 0.0)
		var clear := 1e9
		for group in ["player_team", "enemy_team"]:
			for node in get_tree().get_nodes_in_group(group):
				var body := node as Node2D
				if body == null or body == victim or not is_instance_valid(body):
					continue
				clear = minf(clear, body.global_position.distance_to(spot))
		if clear > best_clear:
			best_clear = clear
			best_side = side
	return best_side < 0.0


func _ready() -> void:
	# Fixed seed: the statistical roll checks below are deterministic.
	seed(364)

	# 1) The weapon-bundle roll: no spear, everything else possible,
	# shotgun (easiest) beats railgun (hardest).
	var weapon_counts := {}
	for i in ROLLS:
		var w := LevelItem.roll_weapon()
		weapon_counts[w] = int(weapon_counts.get(w, 0)) + 1
	_check("weapon bundle never rolls the spear", not weapon_counts.has(SPEAR))
	for w in [0, 1, 2, 4, 5, 6]:
		_check("weapon bundle can roll weapon %d" % w,
			int(weapon_counts.get(w, 0)) > 0)
	_check("shotgun drops more often than the railgun",
		int(weapon_counts.get(0, 0)) > int(weapon_counts.get(6, 0)))

	# 2) The tool-bundle roll: every tool possible, the switch (easiest)
	# beats the teleport (hardest).
	var tool_counts := {}
	for i in ROLLS:
		var t := LevelItem.roll_tool()
		tool_counts[t] = int(tool_counts.get(t, 0)) + 1
	for t in 4:
		_check("tool bundle can roll tool %d" % t,
			int(tool_counts.get(t, 0)) > 0)
	_check("switch drops more often than the teleport",
		int(tool_counts.get(0, 0)) > int(tool_counts.get(1, 0)))

	# 3) Level scene: wait for the player's turn (an enemy team may move
	# first), like test_issue305.
	var level: Node = load("res://Level3.tscn").instantiate()
	add_child(level)
	var tc := get_node("/root/TurnController")
	var inv: Node = get_node("/root/WeaponInventory")
	var player_turn := false
	for i in 3600:
		await get_tree().physics_frame
		if tc.active_team == "player" and not tc._switching:
			player_turn = true
			break
	if not player_turn:
		print("ISSUE364 no player turn — ok=false")
		get_tree().quit(1)
		return

	# 4) Round drop: wrapping the turn order bumps the round counter
	# and (issue #375) creates an item with a 25% chance — seed(13) makes
	# that roll land under 0.25, so this wrap creates exactly one item,
	# right ON a ground surface of the level (no sky drop anymore).
	seed(13)
	tc._turn_index = tc._turn_order.size() - 1
	tc._next_alive_team()
	_check("round wrap bumps the round counter", int(tc.get("_round")) == 2)
	var dropped: Array = get_tree().get_nodes_in_group("level_items")
	_check("round 2 may create exactly one item (seeded 25% roll)",
		dropped.size() == 1)
	var dropped_item: LevelItem = dropped[0] if dropped.size() == 1 else null
	if dropped_item == null:
		_finish()
		return
	var spawn_at := dropped_item.global_position
	for i in 45:
		await get_tree().physics_frame
	var p1 := dropped_item.global_position \
			if is_instance_valid(dropped_item) else Vector2.ZERO
	for i in 15:
		await get_tree().physics_frame
	# The item is created right ON a ground surface — no sky drop — and
	# then only the level's local gravity field may tug it to its resting
	# spot (a mass above can even lift it), so: still a live body, near
	# the creation spot, and at rest.
	_check("the created item settles on the field (no sky drop)",
		is_instance_valid(dropped_item)
		and dropped_item.global_position.distance_to(spawn_at) < 300.0
		and dropped_item.global_position.distance_to(p1) < 4.0)
	if is_instance_valid(dropped_item):
		dropped_item.take_damage(1)
		await get_tree().physics_frame
		_check("1 damage detonates the item (1 HP)",
			not is_instance_valid(dropped_item))

	# 5) Pickups on a player figure at full, unshielded health.
	var figure: Node2D = null
	for node in get_tree().get_nodes_in_group("player_team"):
		if is_instance_valid(node) and int(node.get("health")) > 0:
			figure = node
			break
	if figure == null:
		print("ISSUE364 no player figure — ok=false")
		get_tree().quit(1)
		return
	if figure.has_method("heal"):
		figure.heal(100)
	if figure.has_method("set_shielded"):
		figure.set_shielded(false)

	# 5a) First aid kit: 100 - 30 damage + 60 heal, capped at 100.
	figure.take_damage(30)
	_check("figure damaged to 70", int(figure.get("health")) == 70)
	await _pickup_item(LevelItem.Kind.FIRST_AID, figure)
	_check("first aid kit heals back to the cap (70 + 60 -> 100)",
		is_instance_valid(figure) and int(figure.get("health")) == 100)

	# 5b) Weapon bundle: exactly +1 weapon use for the player team.
	var weapon_sum := 0
	for w in [0, 1, 2, 4, 5, 6]:
		weapon_sum += int(inv.weapon_uses_left("player", w))
	await _pickup_item(LevelItem.Kind.WEAPON_BUNDLE, figure)
	var weapon_sum_after := 0
	for w in [0, 1, 2, 4, 5, 6]:
		weapon_sum_after += int(inv.weapon_uses_left("player", w))
	_check("weapon bundle grants exactly +1 weapon use",
		weapon_sum_after == weapon_sum + 1)

	# 5c) Tool bundle: exactly +1 tool use for the player team.
	var tool_sum := 0
	for t in 4:
		tool_sum += int(inv.tool_uses_left("player", t))
	await _pickup_item(LevelItem.Kind.TOOL_BUNDLE, figure)
	var tool_sum_after := 0
	for t in 4:
		tool_sum_after += int(inv.tool_uses_left("player", t))
	_check("tool bundle grants exactly +1 tool use",
		tool_sum_after == tool_sum + 1)

	# 6) Explosion: one point of damage detonates the item with the
	# grenade's copied 100 px / 40 damage and chains to a neighbour item.
	var victim: Node2D = figure
	if victim.has_method("heal"):
		victim.heal(100)
	if victim.has_method("set_shielded"):
		victim.set_shielded(false)
	var side := Vector2(-1, 0) if _left_is_clearer(victim) else Vector2(1, 0)
	var level_node: Node = get_tree().get_first_node_in_group("level")
	var bomb := LevelItem.new()
	bomb.kind = LevelItem.Kind.TOOL_BUNDLE
	bomb.global_position = victim.global_position + side * 70.0
	level_node.add_child(bomb)
	var neighbour := LevelItem.new()
	neighbour.kind = LevelItem.Kind.FIRST_AID
	neighbour.global_position = victim.global_position + side * 130.0
	level_node.add_child(neighbour)
	var victim_hp := int(victim.get("health"))
	bomb.take_damage(1)
	await get_tree().physics_frame
	_check("the blast wounds the nearby figure by exactly 40 (grenade copy)",
		is_instance_valid(victim) and int(victim.get("health")) == victim_hp - 40)
	_check("the detonated item is gone", not is_instance_valid(bomb))
	_check("the blast chain-detonates the neighbour item",
		not is_instance_valid(neighbour))

	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE364 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE364 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
