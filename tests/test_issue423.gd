extends Node
## Regression check for issue #423: the action mask is applied before
## policy sampling and inference, and the mask arrays are logged alongside
## the chosen actions.
##
## #410 shipped the mask computation (TrainingBot.get_action_mask), the
## ncnn inference application (ActionMask.apply_to_logits before the
## decode) and info["action_mask"] on the training wire. #423 completes
## the convention on both remaining sides:
##   1. Cross-language parity: ActionMask.ILLEGAL_LOGIT is pinned to -1e9 —
##      the exact constant the Python wrapper substitutes
##      (rl_action_mask.ILLEGAL_LOGIT; rl_action_mask_check.py parses this
##      literal out of action_mask.gd each run, so neither side can drift).
##   2. Debug logging: PolicyDebug renders one compact mask row per
##      discrete head right under the head header — a no-enemies payload
##      shows "mask 1 0 0 0 0 0 0 0" on attack with the chosen marker on
##      slot 0 (hold fire), a payload without a mask renders the stock
##      rows unchanged, and a wrong-size mask entry is skipped safely.
##      0/1 numbers (the JSON wire round-trip) render identically to bools.
##   3. End to end: TrainingBot + a fake runner with attack-favoring
##      logits and an empty battlefield — the emitted inference_step
##      payload holds fire (attack 0) and renders through PolicyDebug with
##      the mask arrays visible next to the chosen actions.
##
## The Python-side sampling DoD (20000 draws never select an illegal
## action) lives in rl_action_mask_check.py.
##
## Run headless: godot --headless res://tests/test_issue423.tscn
## Exit code 0 = pass.

const ActionMask := preload("res://addons/godot_native_rl/controllers/action_mask.gd")
const PolicyDebug := preload("res://addons/godot_native_rl/debug/policy_debug.gd")
const Bot := preload("res://TrainingBot.gd")

## Attack-favoring raw policy output for TrainingBot's action space
## (move 6 | aim 3 | attack 8 | target 4, issue #422) — the same fixture
## as tests/test_issue410.gd and rl_action_mask_check.py, so every path
## pins the same logits: the weapon-fire slots 1-7 of the attack head
## carry the highest values, so WITHOUT a mask every path picks an attack.
const ATTACK_FAVORING := [0.5, 0.4, 0.3, 0.2, 0.1, 0.0, 0.5, 0.3, 0.1, 0.2, 4.0, 4.1, 4.2, 4.3, 1.0, 0.9, 0.8, 0.3, 0.25, 0.2, 0.15]

## Fake deploy-side runner: reports a loaded model and returns fixed logits.
class FakeRunner extends RefCounted:
	var logits: PackedFloat32Array = PackedFloat32Array()

	func is_model_loaded() -> bool:
		return true

	func run_inference(_obs: PackedFloat32Array) -> PackedFloat32Array:
		return logits

func _ready() -> void:
	var ok := true
	var space := {
		"move": {"size": 6, "action_type": "discrete"},
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 8, "action_type": "discrete"},
		"target": {"size": 4, "action_type": "discrete"},
	}
	var no_fire := {
		"move": [true, true, true, true, true, true],
		"aim": [true, true, true],
		"attack": [true, false, false, false, false, false, false, false],
		"target": [true, false, false, false],
	}
	var logits := PackedFloat32Array(ATTACK_FAVORING)

	# --- 1. cross-language parity of the ILLEGAL_LOGIT convention ---
	ok = _expect(ActionMask.ILLEGAL_LOGIT == -1.0e9,
			"ILLEGAL_LOGIT pinned to -1e9 (parity with rl_action_mask.ILLEGAL_LOGIT)") and ok

	# --- 2. mask rows render alongside the chosen actions ---
	# Production truth: the core emits the EFFECTIVE (post-mask) logits
	# (NcnnControllerCore applies ActionMask.apply_to_logits before decoding),
	# so this fixture masks them the same way before rendering.
	var chosen := {"move": 0, "aim": 0, "attack": 0, "target": 0}
	var rows := PolicyDebug.action_rows(ActionMask.apply_to_logits(logits, no_fire, space), space, chosen, 8, no_fire)
	ok = _expect("  mask  1 0 0 0 0 0 0 0" in rows,
			"attack mask array renders under its head") and ok
	ok = _expect("  mask  1 0 0 0" in rows,
			"target mask array renders under its head") and ok
	ok = _expect("  mask  1 1 1 1 1 1" in rows and "  mask  1 1 1" in rows,
			"unconstrained heads render their all-legal arrays too") and ok
	var mask_rows := 0
	for row in rows:
		if String(row).contains("  mask  "):
			mask_rows += 1
	ok = _expect(mask_rows == 4, "exactly one mask row per discrete head (got %d)" % mask_rows) and ok
	# The chosen marker sits on the LEGAL slot: masked attack softmax is
	# 100% hold-fire, so slot 0 carries both the probability and the choice.
	ok = _expect("  0  100%  ########  <-chosen" in rows,
			"chosen marker rides the legal attack slot (hold fire, 100%% post-mask)") and ok

	# No mask at all -> the stock rows, unchanged (back-compat).
	var plain := PolicyDebug.action_rows(logits, space, chosen, 8, {})
	var plain_mask_rows := 0
	for row in plain:
		if String(row).contains("  mask  "):
			plain_mask_rows += 1
	ok = _expect(plain_mask_rows == 0,
			"payload without a mask renders no mask rows") and ok
	var plain_chosen := 0
	for row in plain:
		if String(row).contains("<-chosen"):
			plain_chosen += 1
	ok = _expect(plain_chosen == 4, "chosen markers still render without a mask") and ok

	# A wrong-size mask entry is skipped safely (rendering never indexes
	# out of range; the core has already validated before emitting).
	var drifted := PolicyDebug.action_rows(logits, space, chosen, 8, {"attack": [true, false]})
	var drifted_mask_rows := 0
	for row in drifted:
		if String(row).contains("  mask  "):
			drifted_mask_rows += 1
	ok = _expect(drifted_mask_rows == 0,
			"wrong-size mask entry skips its row instead of crashing") and ok

	# 0/1 numbers (the JSON wire round-trip) render the same rows as bools.
	var wire_mask = JSON.parse_string(JSON.stringify(no_fire))
	var wire_rows := PolicyDebug.action_rows(logits, space, chosen, 8, wire_mask)
	ok = _expect("  mask  1 0 0 0 0 0 0 0" in wire_rows,
			"wire-round-tripped mask (0/1 ints) renders identically") and ok

	# --- 3. end to end: the payload logs mask + chosen together ---
	var bot := Bot.new()
	bot.position = Vector2(576, 400)
	add_child(bot)  # in-tree, no player_team figures -> empty battlefield
	var runner := FakeRunner.new()
	runner.logits = logits
	bot.set_ncnn_runner_for_test(runner)
	var payloads: Array = []
	bot.inference_step.connect(func(debug): payloads.append(debug))
	bot.infer_and_act()  # deterministic argmax
	ok = _expect(payloads.size() == 1, "inference_step emitted once") and ok
	if payloads.size() == 1:
		var debug: Dictionary = payloads[0]
		ok = _expect(int(debug["action"]["attack"]) == 0,
				"masked decision holds fire (never an attack)") and ok
		var rendered := "\n".join(PolicyDebug.render_lines(debug,
				{"policy_name": "TrainingBot", "model": "fake", "deterministic": true}, {}, 8))
		ok = _expect(rendered.contains("  mask  1 0 0 0 0 0 0 0"),
				"rendered decision shows the attack mask array") and ok
		ok = _expect(rendered.contains("<-chosen"),
				"rendered decision shows the chosen action next to it") and ok
		ok = _expect(bot.position.x == 576.0,
				"hold-fire decision actuates nothing") and ok

	print("ISSUE423 ok=", ok)
	get_tree().quit(1 if not ok else 0)


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
