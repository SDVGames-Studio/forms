extends Node
## Regression check for issue #422: get_action_space() is a valid
## multi-discrete action space — one discrete head per independent
## decision dimension, every size grounded in the game's actual legal
## options — and the mask/decode paths stay consistent with it.
##
## 1. Space contract: exactly four heads (move/aim/attack/target), each
##    {"size": int, "action_type": "discrete"}; attack == 1 + the 9 real
##    weapon slots (WeaponInventory.WEAPONS; the pistol joined as slot 8,
##    #526), target == 1 + the enemy-team
##    cap (GameConfig.MAX_TEAM_MEMBERS) — the minimal justified sizes.
## 2. Wire shape: the dict JSON-round-trips with every head/size/type
##    intact (env_info ships exactly this to the Python trainer, which
##    builds one spaces.Discrete per head -> a single spaces.MultiDiscrete
##    input; flat width == sum of sizes == 21).
## 3. Trainer encoding parity: NcnnSync.extract_action_dict decodes the
##    flat 23-slot policy output into one integer per head, in head order
##    — the exact per-head slicing the trainer's MultiDiscrete mirrors.
## 4. Mask consistency: ActionMask.validate() accepts the built mask in
##    every battlefield state; "target" legalizes exactly the existing
##    visible enemies (k-th index = k-th alive, opposing, in-reach figure
##    in stable group order); dead or same-side figures never leak into
##    the target set; the mask ships through get_info() with all heads.
##
## Run headless: godot --headless res://tests/test_issue422.tscn
## Exit code 0 = pass.

const ActionMask := preload("res://addons/godot_native_rl/controllers/action_mask.gd")
const Sync := preload("res://addons/godot_native_rl/sync.gd")
const Bot := preload("res://scripts/TrainingBot.gd")
const Weapons := preload("res://scripts/WeaponInventory.gd")
const Config := preload("res://scripts/GameConfig.gd")

## Fake figure for the battlefield mask tests — a Node2D with the `health`
## property the duck-typed alive check reads (same pattern as #410).
class FakeFigure extends Node2D:
	var health: float = 100.0

func _ready() -> void:
	var ok := true
	var bot := Bot.new()
	bot.position = Vector2(576, 400)
	add_child(bot)  # in-tree, no player_team figures yet -> empty battlefield
	var space: Dictionary = bot.get_action_space()

	# --- 1. Space contract + grounded minimal sizes ---
	var expected := {
		"move": 6,
		"aim": 3,
		"attack": 1 + Weapons.WEAPONS.size(),
		"target": 1 + Config.MAX_TEAM_MEMBERS,
	}
	ok = _expect(space.keys() == ["move", "aim", "attack", "target"],
			"four independent heads in order, got %s" % [space.keys()]) and ok
	for key in space.keys():
		var head = space[key]
		ok = _expect(head is Dictionary and head.has("size") and head.has("action_type"),
				"head '%s' declares size + action_type" % key) and ok
		if head is Dictionary and head.has("size"):
			ok = _expect(typeof(head["size"]) == TYPE_INT and int(head["size"]) == expected[key],
					"head '%s' size %s == grounded %d (1 neutral + %d legal options)"
					% [key, head["size"], expected[key], expected[key] - 1]) and ok
			ok = _expect(int(head["size"]) >= 2,
					"head '%s' has a real choice set (size >= 2)" % key) and ok
		ok = _expect(head is Dictionary and head.get("action_type", "") == "discrete",
				"head '%s' is discrete (the multi-discrete contract)" % key) and ok
	ok = _expect(Weapons.WEAPONS.size() == 9 and Config.MAX_TEAM_MEMBERS == 3,
			"sanity: the game still has 9 weapon slots and a 3-figure enemy cap") and ok

	# --- 2. Wire shape: JSON round-trip + flat width ---
	# (Head ORDER is not asserted across the JSON round-trip: Godot's parser
	# does not guarantee key order; the flat layout order is what section 3
	# pins to the head order.)
	var wire = JSON.parse_string(JSON.stringify(space))
	var wire_ok: bool = wire is Dictionary and wire.keys().size() == 4
	var flat_width := 0
	var joint := 1
	for key in space.keys():
		var size: int = space[key]["size"]
		flat_width += size
		joint *= size
		if wire_ok and not (int(wire[key]["size"]) == size
				and wire[key]["action_type"] == "discrete"):
			wire_ok = false
	ok = _expect(wire_ok, "every head survives the wire with size + discrete type") and ok
	ok = _expect(flat_width == 6 + 3 + 10 + 4,
			"flat policy output width == sum of head sizes == %d (got %d)"
			% [6 + 3 + 10 + 4, flat_width]) and ok
	ok = _expect(joint == 6 * 3 * 10 * 4,
			"joint cardinality == product of head sizes == %d, not a fused Discrete (got %d)"
			% [6 * 3 * 10 * 4, joint]) and ok

	# --- 3. Trainer flat encoding parity (the exact layout the trainer's
	# MultiDiscrete flattening mirrors: move 0-5, aim 6-8, attack 9-18,
	# target 19-22; one integer decoded per head) ---
	var sync := Sync.new()
	var flat: Array = []
	flat.resize(flat_width)
	for i in flat.size():
		flat[i] = i  # slot index as its own value: decode must read each head's FIRST slot
	var decoded: Dictionary = sync.extract_action_dict(flat, space)
	ok = _expect(decoded.keys() == ["move", "aim", "attack", "target"],
			"extract_action_dict yields one value per head, in head order") and ok
	ok = _expect(decoded["move"] == 0 and decoded["aim"] == 6
			and decoded["attack"] == 9 and decoded["target"] == 19,
			"per-head decode reads the head-start offsets (got %s)" % [decoded]) and ok
	sync.free()

	# --- 4. Mask consistency across battlefield states ---
	var mask: Dictionary = bot.get_action_mask()
	ok = _expect(mask.keys() == space.keys(),
			"mask has exactly the space's heads, same shape") and ok
	ok = _expect(ActionMask.validate(mask, space),
			"empty-battlefield mask validates") and ok
	ok = _expect(mask["attack"] == [true, false, false, false, false, false, false, false, false, false],
			"no visible enemy: only hold-fire is legal") and ok
	ok = _expect(mask["target"] == [true, false, false, false],
			"no visible enemy: no target may be selected") and ok

	var near1 := FakeFigure.new()
	near1.position = Vector2(576 + 600, 400)  # 600 <= ATTACK_REACH 620
	add_child(near1)
	near1.add_to_group("player_team")
	mask = bot.get_action_mask()
	ok = _expect(mask["target"] == [true, true, false, false],
			"one visible enemy legalizes target index 1 only") and ok
	ok = _expect(ActionMask.validate(mask, space), "one-enemy mask validates") and ok

	var near2 := FakeFigure.new()
	near2.position = Vector2(576 - 500, 400)  # 500 <= 620
	add_child(near2)
	near2.add_to_group("player_team")
	mask = bot.get_action_mask()
	ok = _expect(mask["target"] == [true, true, true, false],
			"two visible enemies legalize target indices 1-2, never the empty 4th") and ok
	ok = _expect(mask["attack"] == [true, true, true, true, true, true, true, true, true, true],
			"at least one visible enemy legalizes every fire slot") and ok

	# Visibility compaction: a THIRD enemy beyond reach must NOT shift the
	# k-th index onto itself — index k stays the k-th IN-REACH figure.
	var far := FakeFigure.new()
	far.position = Vector2(576 + 3000, 400)  # way beyond 620
	add_child(far)
	far.add_to_group("player_team")
	mask = bot.get_action_mask()
	ok = _expect(mask["target"] == [true, true, true, false],
			"out-of-reach enemy adds no legal target index") and ok
	ok = _expect(mask["attack"] == [true, true, true, true, true, true, true, true, true, true],
			"firing legality still holds (the two in-reach enemies)") and ok

	# Dead figures never count as visible.
	near1.health = 0.0
	mask = bot.get_action_mask()
	ok = _expect(mask["target"] == [true, true, false, false]
			and mask["attack"] == [true, true, true, true, true, true, true, true, true, true],
			"downed enemy leaves the target set (compacted to the survivor)") and ok
	near1.health = 100.0

	# Same-side figures never count as visible.
	near1.remove_from_group("player_team")
	near1.add_to_group("enemy_team")
	mask = bot.get_action_mask()
	ok = _expect(mask["target"] == [true, true, false, false],
			"same-side figure never enters the target set") and ok
	near1.queue_free()
	near2.queue_free()
	far.queue_free()

	mask = bot.get_action_mask()
	ok = _expect(ActionMask.validate(mask, space),
			"back-to-empty mask still validates") and ok

	# The wire mask ships with every head (info["action_mask"]; key order
	# across the JSON round-trip is not guaranteed, only head presence).
	var info: Dictionary = bot.get_info()
	var round_trip = JSON.parse_string(JSON.stringify(info))
	var wire_mask_ok: bool = round_trip is Dictionary \
			and round_trip["action_mask"].keys().size() == 4
	for key in ["move", "aim", "attack", "target"]:
		if wire_mask_ok and not round_trip["action_mask"].has(key):
			wire_mask_ok = false
	ok = _expect(wire_mask_ok,
			"the wire mask JSON-round-trips with all four heads") and ok

	print("ISSUE422 ok=", ok, " (heads=", space.keys(), " sizes 6/3/10/4, flat=", flat_width,
			" joint=", joint, ")")
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
