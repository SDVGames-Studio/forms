extends Node
## Regression check for issue #410: illegal actions are masked before the
## policy selects an action.
##
## Covers the three consumers of the mask:
##   1. ActionMask (pure): validate() rejects wrong-size / missing-head /
##      unknown-key / all-illegal / continuous-head masks and accepts the
##      well-formed one; apply_to_logits() overwrites only the illegal
##      slots with ILLEGAL_LOGIT and never mutates its input.
##   2. The ncnn inference path (NcnnControllerCore): with every enemy out
##      of range, a fake runner whose raw logits FAVOR the attack slots
##      still decodes to "hold fire" — deterministically (argmax) and over
##      300 stochastic draws — and the mask is logged alongside the action
##      in the inference_step payload (action_mask + effective logits). An
##      invalid mask skips the step loudly (set_action never fires).
##   3. The training wire: NcnnAIController2D.get_info() ships
##      info["action_mask"], JSON-round-tripping the per-head booleans, and
##      TrainingBot.get_action_mask() computes real legality from the
##      battlefield (enemy distance vs ATTACK_REACH, alive figures only,
##      the opposing side only).
##
## Run headless: godot --headless res://tests/test_issue410.tscn
## Exit code 0 = pass.

const ActionMask := preload("res://addons/godot_native_rl/controllers/action_mask.gd")
const ActionDecode := preload("res://addons/godot_native_rl/controllers/action_decode.gd")
const InferenceMath := preload("res://addons/godot_native_rl/controllers/inference_math.gd")
const NcnnControllerCore := preload("res://addons/godot_native_rl/controllers/ncnn_controller_core.gd")
const Bot := preload("res://TrainingBot.gd")

## Attack-favoring raw policy output for TrainingBot's action space
## (move 6 | aim 3 | attack 5): the weapon-fire slots 1-4 carry the highest
## logits, so WITHOUT a mask every path picks an attack action.
const ATTACK_FAVORING := [0.5, 0.4, 0.3, 0.2, 0.1, 0.0, 0.5, 0.3, 0.1, 0.2, 4.0, 4.1, 4.2, 4.3]

## Fake deploy-side runner: reports a loaded model and returns fixed logits.
class FakeRunner extends RefCounted:
	var logits: PackedFloat32Array = PackedFloat32Array()

	func is_model_loaded() -> bool:
		return true

	func run_inference(_obs: PackedFloat32Array) -> PackedFloat32Array:
		return logits

## Fake figure for the battlefield mask tests — a Node2D with the `health`
## property the duck-typed alive check reads.
class FakeFigure extends Node2D:
	var health: float = 100.0

func _ready() -> void:
	var ok := true
	var space := {
		"move": {"size": 6, "action_type": "discrete"},
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 5, "action_type": "discrete"},
	}
	var no_fire := {
		"move": [true, true, true, true, true, true],
		"aim": [true, true, true],
		"attack": [true, false, false, false, false],
	}

	# --- 1. ActionMask.validate ---
	ok = _expect(ActionMask.validate(no_fire, space),
			"well-formed mask validates") and ok
	ok = _expect(not ActionMask.validate({}, space),
			"empty mask is invalid (use no key at all for 'no mask')") and ok
	ok = _expect(not ActionMask.validate({
		"move": [true, true, true, true, true],
		"aim": [true, true, true],
		"attack": [true, false, false, false, false],
	}, space), "wrong-size entry is invalid") and ok
	ok = _expect(not ActionMask.validate({
		"aim": [true, true, true],
		"attack": [true, false, false, false, false],
	}, space), "missing head is invalid") and ok
	ok = _expect(not ActionMask.validate({
		"move": [true, true, true, true, true, true],
		"aim": [true, true, true],
		"attack": [true, false, false, false, false],
		"extra": [true],
	}, space), "unknown head key is invalid") and ok
	ok = _expect(not ActionMask.validate({
		"move": [false, false, false, false, false, false],
		"aim": [true, true, true],
		"attack": [true, false, false, false, false],
	}, space), "all-illegal head is invalid (neutral index must stay legal)") and ok
	ok = _expect(not ActionMask.validate({
		"move": [true, true, true, true, true, true],
		"aim": [true, true, true],
		"attack": [true, false, false, false, false],
		"throttle": [true, false],
	}, {
		"move": {"size": 6, "action_type": "discrete"},
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 5, "action_type": "discrete"},
		"throttle": {"size": 2, "action_type": "continuous"},
	}), "mask entry for a continuous head is invalid") and ok
	ok = _expect(ActionMask.validate({
		"move": [1, 1, 1, 1, 1, 1],
		"aim": [1, 1, 1],
		"attack": [1, 0, 0, 0, 0],
	}, space), "0/1 numbers validate (the JSON wire round-trip)") and ok

	# --- 2. ActionMask.apply_to_logits ---
	var raw := PackedFloat32Array(ATTACK_FAVORING)
	var masked := ActionMask.apply_to_logits(raw, no_fire, space)
	# Layout: move 0-5, aim 6-8, attack 9-13. Fire slots 10-13 -> ILLEGAL_LOGIT.
	for i in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]:
		ok = _expect(is_equal_approx(masked[i], raw[i]),
				"legal slot %d untouched (got %s, want %s)" % [i, masked[i], raw[i]]) and ok
	for i in [10, 11, 12, 13]:
		ok = _expect(masked[i] == ActionMask.ILLEGAL_LOGIT,
				"illegal slot %d set to ILLEGAL_LOGIT (got %s)" % [i, masked[i]]) and ok
	ok = _expect(is_equal_approx(raw[12], 4.2), "apply_to_logits never mutates its input") and ok

	# --- 3. Masked decode: argmax and sampling never pick an attack ---
	ok = _expect(ActionDecode.decode_actions(masked, space, true)["attack"] == 0,
			"deterministic decode of masked logits holds fire") and ok
	var unmasked_dict := ActionDecode.decode_actions(raw, space, true)
	var unmasked_action := int(unmasked_dict["attack"])
	ok = _expect(unmasked_action == 4,
			"sanity: the same logits WITHOUT the mask do pick an attack (got %s)" % unmasked_action) and ok
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var sampled_attack := false
	for _i in 300:
		var action := ActionDecode.decode_actions(masked, space, false, rng)
		if int(action["attack"]) != 0:
			sampled_attack = true
	ok = _expect(not sampled_attack,
			"300 stochastic draws from the masked softmax never fire (DoD)") and ok

	# --- 4. The full inference path with a fake runner ---
	var bot := Bot.new()
	bot.position = Vector2(576, 400)
	add_child(bot)  # in-tree: no player_team figure exists here -> fire illegal
	var runner := FakeRunner.new()
	runner.logits = PackedFloat32Array(ATTACK_FAVORING)
	bot.set_ncnn_runner_for_test(runner)
	var payloads: Array = []
	bot.inference_step.connect(func(debug): payloads.append(debug))

	bot.infer_and_act()  # deterministic argmax
	ok = _expect(bot.position.x == 576.0,
			"masked decision holds fire and position (no walk order)") and ok
	ok = _expect(payloads.size() == 1, "inference_step emitted once") and ok
	if payloads.size() == 1:
		var debug: Dictionary = payloads[0]
		ok = _expect(debug.has("action_mask"),
				"payload logs the mask alongside the action (DoD)") and ok
		var logged: Array = debug["action_mask"].get("attack", [])
		ok = _expect(logged == [true, false, false, false, false],
				"logged attack mask is [hold only], got %s" % [logged]) and ok
		ok = _expect(debug["logits"][12] == ActionMask.ILLEGAL_LOGIT,
				"logged logits are the effective (post-mask) ones") and ok
		ok = _expect(int(debug["action"]["attack"]) == 0,
				"decoded action in the payload holds fire") and ok

	# Stochastic end to end: the sampled path through the core also never fires
	# (the decoded action is in every emitted payload; move/aim heads stay legal).
	bot.set_stochastic_for_test(false, 4242)
	var e2e_fired := false
	for _i in 300:
		bot.infer_and_act()
	for debug in payloads:
		if int(debug["action"]["attack"]) != 0:
			e2e_fired = true
	ok = _expect(not e2e_fired,
			"300 stochastic end-to-end decisions never fire (DoD)") and ok

	# An invalid mask must skip the step loudly: set_action never runs.
	var core := NcnnControllerCore.new()
	var bad_agent := BadMaskAgent.new()
	add_child(bad_agent)
	core.choose_and_apply_action(bad_agent, runner)
	ok = _expect(bad_agent.actions_received == 0,
			"invalid mask skips the action (set_action not called)") and ok
	var good_agent := NoMaskAgent.new()
	add_child(good_agent)
	core.choose_and_apply_action(good_agent, runner)
	ok = _expect(good_agent.actions_received == 1
			and int(good_agent.last_action["attack"]) == 4,
			"agent without get_action_mask keeps the stock unmasked path") and ok

	# --- 5. TrainingBot battlefield legality + the training wire ---
	var near := FakeFigure.new()
	near.position = Vector2(576 + 600, 400)  # 600 <= ATTACK_REACH 620
	add_child(near)
	near.add_to_group("player_team")
	ok = _expect(bot.get_action_mask()["attack"] == [true, true, true, true, true],
			"enemy in reach legalizes the fire actions") and ok
	near.position = Vector2(576 + 700, 400)  # 700 > 620
	ok = _expect(bot.get_action_mask()["attack"] == [true, false, false, false, false],
			"enemy beyond reach re-masks the fire actions") and ok
	near.position = Vector2(576 + 100, 400)
	near.health = 0.0
	ok = _expect(bot.get_action_mask()["attack"] == [true, false, false, false, false],
			"downed enemy never legalizes firing") and ok
	near.health = 100.0
	near.remove_from_group("player_team")
	near.add_to_group("enemy_team")
	ok = _expect(bot.get_action_mask()["attack"] == [true, false, false, false, false],
			"same-side figure never legalizes firing") and ok
	near.queue_free()

	var info: Dictionary = bot.get_info()
	ok = _expect(info.has("action_mask"), "get_info() ships the mask on the wire") and ok
	var round_trip = JSON.parse_string(JSON.stringify(info))
	ok = _expect(round_trip is Dictionary
			and round_trip["action_mask"]["attack"] == [true, false, false, false, false],
			"the wire mask JSON-round-trips as booleans") and ok
	var plain := PlainInfoAgent.new()
	add_child(plain)
	ok = _expect(plain.get_info().is_empty(),
			"agent without get_action_mask keeps an empty info dict") and ok

	print("ISSUE410 ok=", ok)
	get_tree().quit(1 if not ok else 0)


## Duck-typed inference agent whose mask breaks the contract (wrong size):
## the core must refuse the step instead of acting on a broken mask.
class BadMaskAgent extends Node2D:
	var actions_received := 0

	signal inference_step(debug: Dictionary)

	func get_obs() -> Dictionary:
		return {"obs": PackedFloat32Array([0.0, 0.0])}

	func get_action_space() -> Dictionary:
		return {
			"move": {"size": 6, "action_type": "discrete"},
			"aim": {"size": 3, "action_type": "discrete"},
			"attack": {"size": 5, "action_type": "discrete"},
		}

	func get_action_mask() -> Dictionary:
		return {
			"move": [true, true, true, true, true, true],
			"aim": [true, true, true],
			"attack": [true, false],
		}

	func get_inference_image() -> Image:
		return null

	func set_action(_action) -> void:
		actions_received += 1


## Duck-typed inference agent with NO mask: the stock unmasked path.
class NoMaskAgent extends Node2D:
	var actions_received := 0
	var last_action: Dictionary = {}

	signal inference_step(debug: Dictionary)

	func get_obs() -> Dictionary:
		return {"obs": PackedFloat32Array([0.0, 0.0])}

	func get_action_space() -> Dictionary:
		return {
			"move": {"size": 6, "action_type": "discrete"},
			"aim": {"size": 3, "action_type": "discrete"},
			"attack": {"size": 5, "action_type": "discrete"},
		}

	func get_inference_image() -> Image:
		return null

	func set_action(action) -> void:
		actions_received += 1
		last_action = action


## Minimal NcnnAIController2D subclass with no mask: proves get_info() stays
## empty for agents that don't opt in.
class PlainInfoAgent extends NcnnAIController2D:
	func get_obs() -> Dictionary:
		return {"obs": PackedFloat32Array([0.0, 0.0])}

	func get_reward() -> float:
		return 0.0

	func get_action_space() -> Dictionary:
		return {"move": {"size": 2, "action_type": "discrete"}}

	func set_action(_action) -> void:
		pass


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
