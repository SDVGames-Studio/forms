extends Node
## Issue #507 checks: legal-action masks are applied on the DEPLOY ncnn
## inference path (InferenceBot, issue #506) BEFORE the per-head argmax is
## accepted — recomputed from live state at EVERY decision step, per head —
## and the mask application is logged alongside the RAW network output.
##
## Part 1 (fake runner, deterministic + stochastic): with no visible enemy,
## attack-favoring raw logits in the DEPLOY head order (aim 3 | attack 8 |
## move 6 | target 4) decode to attack=0 (hold fire): the illegal network
## choice is overridden by the highest-scoring LEGAL action of the head,
## and the inference_step payload ships raw_output (the net's unmasked
## scores) next to the post-mask logits and the per-head mask. A visible
## enemy within ATTACK_REACH flips the mask on the very NEXT decision
## (recomputed every decision step) and the same logits then fire
## (attack=4, the raw argmax); moving the enemy out of reach — or downing
## it — re-masks and the decision falls back to hold fire again.
## Part 2 (the real ncnn-powered bot): an InferenceBot configured exactly
## like inference_scene.tscn (NCNN_INFERENCE + the res://models/policy.ncnn
## pair + the #503 VecNormalize sidecar) in a no-enemy state — every
## decision's attack mask is hold-only, every decoded attack is 0 (DoD),
## and the attack slots' real network scores survive in raw_output where
## the effective logits show ILLEGAL_LOGIT.
##
## Run headless: godot --headless res://tests/test_issue507.tscn
## Exit code 0 = pass; the printed ISS507 ok= verdict is authoritative.

const ActionMask := preload("res://addons/godot_native_rl/controllers/action_mask.gd")
const Bot := preload("res://InferenceBot.gd")

## Attack-favoring raw policy output in InferenceBot's DEPLOY head order
## (aim 0-2 | attack 3-10 | move 11-16 | target 17-20): fire slots 1-7
## carry the highest logits, so WITHOUT a mask every path picks an attack.
const ATTACK_FAVORING_DEPLOY := [
	0.5, 0.3, 0.1,                                       # aim 0-2
	0.2, 4.0, 4.1, 4.2, 4.3, 4.2, 4.1, 4.0,              # attack 0-7 (flat 3-10)
	0.5, 0.4, 0.3, 0.2, 0.1, 0.0,                        # move 0-5 (flat 11-16)
	1.0, 0.9, 0.8, 0.3,                                  # target 0-3 (flat 17-20)
]
const HOLD_ONLY_ATTACK := [true, false, false, false, false, false, false, false]
## Distinct arena positions (TrainingBot obs = position/ARENA_W, /ARENA_H).
const SWEEP := [
	Vector2(112.0, 323.0), Vector2(1000.0, 640.0), Vector2(288.0, 188.0),
	Vector2(864.0, 560.0), Vector2(576.0, 400.0), Vector2(720.0, 500.0),
]

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

var _payloads: Array = []

func _ready() -> void:
	var ok := true

	# --- Part 1: the deploy path with a fake, attack-favoring runner. ---
	var bot := Bot.new()
	bot.position = Vector2(576, 400)
	add_child(bot)  # no player_team figure exists here -> every fire action illegal
	var runner := FakeRunner.new()
	runner.logits = PackedFloat32Array(ATTACK_FAVORING_DEPLOY)
	bot.set_ncnn_runner_for_test(runner)
	bot.inference_step.connect(_on_step)

	# Deterministic: the raw argmax (attack=4) is overridden by the
	# highest-scoring LEGAL action of the head — hold fire.
	bot.infer_and_act()
	ok = _expect(_payloads.size() == 1, "one payload emitted for the masked decision") and ok
	if _payloads.size() >= 1:
		var d: Dictionary = _payloads[0]
		ok = _expect(int(d["action"]["attack"]) == 0,
				"illegal raw argmax overridden: attack=0 (DoD)") and ok
		ok = _expect(d["action_mask"]["attack"] == HOLD_ONLY_ATTACK,
				"no-enemy state ships the hold-only attack mask, got %s" % [d["action_mask"]["attack"]]) and ok
		ok = _expect(d["action_mask"]["target"] == [true, false, false, false],
				"no-enemy state ships the no-target mask, got %s" % [d["action_mask"]["target"]]) and ok
		ok = _expect(d.has("raw_output") and (d["raw_output"] as PackedFloat32Array).size() == 21,
				"payload logs the raw 21-value network output (DoD)") and ok
		# Mask application alongside the raw output: the illegal fire slots
		# keep their real 4.x scores in raw_output while the effective logits
		# show ILLEGAL_LOGIT; the legal hold-fire slot is untouched.
		ok = _expect(absf(d["raw_output"][7] - 4.3) < 1e-6 and absf(d["raw_output"][10] - 4.0) < 1e-6,
				"raw_output keeps the net's fire-slot scores (4.3/4.0)") and ok
		ok = _expect(d["logits"][7] == ActionMask.ILLEGAL_LOGIT and d["logits"][10] == ActionMask.ILLEGAL_LOGIT,
				"effective logits mask the fire slots to ILLEGAL_LOGIT") and ok
		ok = _expect(absf(d["logits"][3] - 0.2) < 1e-6 and absf(d["raw_output"][3] - 0.2) < 1e-6,
				"legal hold-fire slot 3 passes through untouched") and ok
		ok = _expect(absf(d["logits"][11] - d["raw_output"][11]) < 1e-6,
				"unmasked move head passes through untouched") and ok

	# Stochastic end to end: the sampled path also never fires.
	bot.set_stochastic_for_test(false, 507)
	var fired := false
	for _i in 300:
		bot.infer_and_act()
	for d in _payloads:
		if int(d["action"]["attack"]) != 0:
			fired = true
	ok = _expect(not fired, "300 stochastic deploy decisions never fire (DoD)") and ok

	# The mask is recomputed EVERY decision step, per head: a visible enemy
	# legalizes firing on the very next decision (the same logits then pick
	# the raw argmax, attack=4); out of reach or downed re-masks instantly.
	bot.set_stochastic_for_test(true, 0)
	bot.position = Vector2(576, 400)  # pin: the stochastic block sampled walk orders
	_payloads.clear()
	var enemy := FakeFigure.new()
	enemy.position = Vector2(576 + 600, 400)  # 600 <= ATTACK_REACH 620
	add_child(enemy)
	enemy.add_to_group("player_team")
	bot.infer_and_act()
	bot.infer_and_act()
	ok = _expect(_payloads.size() == 2, "two decisions collected around the state change") and ok
	if _payloads.size() == 2:
		ok = _expect(_payloads[0]["action_mask"]["attack"] == [true, true, true, true, true, true, true, true],
				"enemy in reach legalizes the fire actions on the next decision") and ok
		ok = _expect(int(_payloads[0]["action"]["attack"]) == 4,
				"legal state: the raw argmax (attack=4) fires") and ok
		ok = _expect(_payloads[0]["action_mask"]["target"] == [true, true, false, false],
				"one visible enemy legalizes exactly target index 1") and ok
		ok = _expect(_payloads[1]["action_mask"]["attack"] == [true, true, true, true, true, true, true, true],
				"enemy left in place: mask recomputed identically per step") and ok
	enemy.position = Vector2(576 + 700, 400)  # 700 > 620
	bot.infer_and_act()
	ok = _expect(_payloads.size() == 3 and _payloads[2]["action_mask"]["attack"] == HOLD_ONLY_ATTACK
			and int(_payloads[2]["action"]["attack"]) == 0,
			"enemy beyond reach re-masks and the decision holds fire again") and ok
	enemy.position = Vector2(576 + 100, 400)
	enemy.health = 0.0
	bot.infer_and_act()
	ok = _expect(_payloads.size() == 4 and _payloads[3]["action_mask"]["attack"] == HOLD_ONLY_ATTACK
			and int(_payloads[3]["action"]["attack"]) == 0,
			"downed enemy never legalizes firing") and ok
	enemy.queue_free()

	# --- Part 2: the real ncnn-powered bot in a no-enemy state (DoD). ---
	var real_bot := Bot.new()
	real_bot.control_mode = NcnnAIController2D.ControlModes.NCNN_INFERENCE
	add_child(real_bot)  # _ready loads the real policy.ncnn pair + sidecar
	real_bot.inference_step.connect(_on_step)
	await get_tree().create_timer(1.0).timeout
	var real_ok: bool = real_bot._ncnn_runner != null and real_bot._ncnn_runner.is_model_loaded()
	print("ISS507 real_model_loaded=", real_ok)
	ok = ok and real_ok
	_payloads.clear()
	if real_ok:
		for pos in SWEEP:
			real_bot.position = pos
			real_bot.infer_and_act()
		var steps_ok: bool = _payloads.size() >= 6
		print("ISS507 real_decisions_collected=", steps_ok, " (n=", _payloads.size(), ")")
		ok = ok and steps_ok
		# Every decision: hold-only attack mask, decoded attack 0, and the raw
		# output logged next to the masked logits (flat attack slots 3-10;
		# slot 3 = hold fire stays legal, 4-10 are masked illegal).
		var dod_ok := steps_ok
		var raw_logged := steps_ok
		for d in _payloads:
			if d["action_mask"]["attack"] != HOLD_ONLY_ATTACK or int(d["action"]["attack"]) != 0:
				dod_ok = false
			var raw: PackedFloat32Array = d["raw_output"]
			var eff: PackedFloat32Array = d["logits"]
			if raw.size() != 21 or eff.size() != 21 or absf(eff[3] - raw[3]) > 1e-6:
				raw_logged = false
			else:
				for i in range(4, 11):
					if eff[i] != ActionMask.ILLEGAL_LOGIT or raw[i] == ActionMask.ILLEGAL_LOGIT:
						raw_logged = false
		print("ISS507 real_bot_never_attacks_when_illegal=", dod_ok)
		print("ISS507 mask_logged_alongside_raw_output=", raw_logged)
		ok = ok and dod_ok and raw_logged

	print("ISS507 ok=", ok)
	get_tree().quit(0 if ok else 1)

func _on_step(debug: Dictionary) -> void:
	_payloads.append(debug)

func _expect(cond: bool, what: String) -> bool:
	print("ISS507 ", "PASS " if cond else "FAIL ", what)
	return cond
