extends Node
## Issue #506 checks: the bot's NcnnAIController2D node is configured for
## NATIVE ncnn inference — control_mode = NCNN_INFERENCE with the
## res://models/policy.ncnn.{param,bin} pair (#502–#505) and the Issue 7.2
## (#503) VecNormalize sidecar — and it acts with NO Python training server:
## in inference_scene.tscn the NcnnSync (control_mode = 2, NCNN_INFERENCE)
## has zero training agents, so it never opens the trainer socket; the
## runner is loaded from buffers, every decision feeds the RAW get_obs()
## vector through the VecNormalize replay (models/vecnormalize_stats.json)
## before run_inference, and the flat 21-logit output is decoded through
## get_action_space() insertion-ordered to the training-time MultiDiscrete
## layout [aim(3), attack(8), move(6), target(4)] (pinned vs ONNX by
## tests/test_issue505.gd).
##
## Definition of Done (issue #506): with the Python training server
## completely stopped the bot still takes actions, and they are not all
## zeros or constant — varied observations produce varied logits (the net is
## really queried each decision) and at least two distinct decoded actions.
##
## Run headless: godot --headless res://tests/test_issue506.tscn
## Exit code 0 = pass; the printed ISS506 ok= verdict is authoritative.

const ObsNormalize := preload("res://addons/godot_native_rl/controllers/obs_normalize.gd")

const SCENE_PATH := "res://scenes/testing/inference_scene.tscn"
const STATS_PATH := "res://models/vecnormalize_stats.json"
const EXPECT_HEAD_ORDER := ["aim", "attack", "move", "target"]  # SB3 MultiDiscrete([3,8,6,4])
const EXPECT_HEAD_SIZES := [3, 8, 6, 4]
# Distinct arena positions (TrainingBot obs = position/ARENA_W, /ARENA_H).
const SWEEP := [
	Vector2(112.0, 323.0), Vector2(1000.0, 640.0), Vector2(288.0, 188.0),
	Vector2(864.0, 560.0), Vector2(576.0, 400.0), Vector2(480.0, 300.0),
	Vector2(720.0, 500.0), Vector2(200.0, 700.0),
]

var _bot = null
var _raw_obs_seen: Array[PackedFloat32Array] = []
var _norm_obs_seen: Array[PackedFloat32Array] = []
var _masks_seen: Array[Dictionary] = []
var _logits_hashes := {}
var _actions_seen := {}

func _ready() -> void:
	var ok := true

	# --- VecNormalize sidecar loads and is active (#503 replay input). ---
	var stats_text := FileAccess.get_file_as_string(STATS_PATH)
	var stats = JSON.parse_string(stats_text)
	var stats_ok: bool = stats is Dictionary and ObsNormalize.validate(stats) \
		and bool(stats.get("norm_obs", false))
	print("ISS506 vecnormalize_stats_valid=", stats_ok)
	ok = ok and stats_ok

	# --- The inference scene: no training agents -> no trainer socket. ---
	var scene: PackedScene = load(SCENE_PATH)
	var world = scene.instantiate()
	add_child(world)
	var sync = world.get_node("NcnnSync")
	_bot = world.get_node("NcnnSync/Environment/Bot")
	var config_ok: bool = _bot != null and sync != null \
		and _bot.control_mode == NcnnAIController2D.ControlModes.NCNN_INFERENCE \
		and _bot.model_param_path == "res://models/policy.ncnn.param" \
		and _bot.model_bin_path == "res://models/policy.ncnn.bin" \
		and _bot.obs_norm_stats_path == STATS_PATH
	print("ISS506 node_config_ncnn_inference=", config_ok)
	ok = ok and config_ok

	# --- Action space = the training-time MultiDiscrete layout (#506). ---
	var space: Dictionary = _bot.get_action_space()
	var order: Array = space.keys()
	var sizes := []
	for key in order:
		sizes.append(int(space[key]["size"]))
	var space_ok: bool = order == EXPECT_HEAD_ORDER and sizes == EXPECT_HEAD_SIZES \
		and sizes.reduce(func(a: int, b: int) -> int: return a + b, 0) == 21
	print("ISS506 action_space_training_layout=", space_ok, " (order ", order, ", sizes ", sizes, ")")
	ok = ok and space_ok

	# --- Runner loaded natively (editor path: buffers -> net). ---
	var runner = _bot._ncnn_runner
	var runner_ok: bool = runner != null and runner.is_model_loaded()
	print("ISS506 ncnn_runner_loaded=", runner_ok)
	ok = ok and runner_ok

	# --- Let NcnnSync initialize (it pauses the tree ~1 s), then drive. ---
	_bot.inference_step.connect(_on_step)
	await get_tree().create_timer(2.0).timeout
	var no_trainer: bool = sync.agents_training.is_empty() and not sync.connected
	print("ISS506 no_python_trainer=", no_trainer, " (training_agents ", sync.agents_training.size(), ")")
	ok = ok and no_trainer

	for pos in SWEEP:
		_bot.position = pos
		await get_tree().create_timer(0.35).timeout

	# --- Decisions actually happened; the model is really queried. ---
	var steps_ok: bool = _raw_obs_seen.size() >= 8
	print("ISS506 decisions_collected=", steps_ok, " (n=", _raw_obs_seen.size(), ")")
	ok = ok and steps_ok

	# --- VecNormalize preprocessing: fed obs = replay(raw obs), NOT raw. ---
	var typed := ObsNormalize.to_typed(stats) if stats_ok else {}
	var norm_ok := steps_ok and not typed.is_empty()
	if norm_ok:
		for i in _raw_obs_seen.size():
			var expected := ObsNormalize.normalize(_raw_obs_seen[i],
				typed["mean"], typed["var"], typed["epsilon"], typed["clip_obs"])
			if expected.size() != _norm_obs_seen[i].size():
				norm_ok = false
				break
			for j in expected.size():
				if absf(expected[j] - _norm_obs_seen[i][j]) > 1e-6:
					norm_ok = false
					break
			if not norm_ok:
				break
	print("ISS506 vecnormalize_applied_before_runner=", norm_ok)
	ok = ok and norm_ok

	# --- Output decoded through the space: valid + mask-legal every step. ---
	var valid_ok := steps_ok
	for i in _actions_seen.size():
		var joint: Dictionary = _actions_seen.values()[i]
		var mask: Dictionary = _masks_seen[i] if i < _masks_seen.size() else {}
		for key in EXPECT_HEAD_ORDER:
			var idx: int = int(joint[key])
			if idx < 0 or idx >= int(space[key]["size"]):
				valid_ok = false
			elif mask.has(key) and not bool(mask[key][idx]):
				valid_ok = false  # decoded index must be legal where a mask shipped
	print("ISS506 actions_valid_per_head=", valid_ok)
	ok = ok and valid_ok

	# --- Not constant: >= 2 distinct logits vectors and decoded actions. ---
	var live_ok: bool = _logits_hashes.size() >= 2 and _actions_seen.size() >= 2
	print("ISS506 not_constant=", live_ok,
		" (distinct logits ", _logits_hashes.size(),
		", distinct actions ", _actions_seen.size(), ")")
	ok = ok and live_ok

	print("ISS506 ok=", ok)
	get_tree().quit(0 if ok else 1)

func _on_step(debug: Dictionary) -> void:
	# Fires before set_action moves the bot, so get_obs() here is the exact
	# RAW vector this decision consumed.
	_raw_obs_seen.append(PackedFloat32Array(_bot.get_obs()["obs"]))
	_norm_obs_seen.append(debug["obs"])
	_masks_seen.append(debug["action_mask"])
	_logits_hashes[str(debug["logits"]).hash()] = true
	var joint := {}
	var key_str := ""
	for key in debug["action_space"].keys():
		joint[key] = int(debug["action"][key])
		key_str += ("|" if not key_str.is_empty() else "") + str(joint[key])
	_actions_seen[key_str] = joint
