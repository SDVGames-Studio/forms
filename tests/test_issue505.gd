extends Node
## Issue #505 checks: the pnnx-converted ncnn policy (models/policy.ncnn.param +
## models/policy.ncnn.bin, converted from models/policy-logits.onnx per
## DEPLOYMENT.md §3) loads into the NcnnRunner GDExtension from BUFFERS — the
## path that works in the editor and inside an exported .pck — and, fed the
## Issue 7.1/#502 dummy observation (seed 0, RAW pre-normalization vector from
## export_onnx.py) through the exact deploy-side replay (ObsNormalize on
## models/vecnormalize_stats.json), returns the same per-head MultiDiscrete
## action as the Python ONNX reference.
##
## The deployed ncnn graph outputs per-head LOGITS (3+8+6+4 = 21 values), NOT
## argmaxed actions: the bundled NcnnRunner statically links ncnn WITHOUT the
## ArgMax layer, so models with ArgMax baked in cannot even load (that is the
## upstream godot-native-rl convention — argmax runs caller-side, e.g.
## NcnnRunner.run_discrete_action / InferenceMath.argmax). This test mirrors
## that selection: argmax per head, first index wins on ties.
##
## Reference values were computed Python-side (hardcoded so the GDScript path
## is checked against ONNX, not against itself):
##   dummy_raw = np.random.seed(0).uniform(-1, 1, (1, 2))
##             = [0.0976270078546495, 0.43037873274483895]
##   normalized (SB3 VecNormalize, issue471_check stats; dim 1 clips to -clip_obs)
##             = [-4.1044158935546875, -10.0]
##   onnxruntime argmax per MultiDiscrete([3, 8, 6, 4]) head — identical on the
##   reference graph models/policy.onnx (#502) and the logits variant
##   models/policy-logits.onnx, and matched by ncnn on 51/51 probe inputs
##             = [1, 5, 1, 1]
##
## Run headless: godot --headless res://tests/test_issue505.tscn
## Exit code 0 = pass; the printed ISS505 ok= verdict is authoritative.

const ObsNormalize := preload("res://addons/godot_native_rl/controllers/obs_normalize.gd")
const InferenceMath := preload("res://addons/godot_native_rl/controllers/inference_math.gd")

const PARAM_PATH := "res://models/policy.ncnn.param"
const BIN_PATH := "res://models/policy.ncnn.bin"
const STATS_PATH := "res://models/vecnormalize_stats.json"

const INPUT_BLOB := "in0"   # pnnx export convention (godot-rl defaults)
const OUTPUT_BLOB := "out0"

const DUMMY_RAW := [0.0976270078546495, 0.43037873274483895]
const EXPECT_NORM := [-4.1044158935546875, -10.0]
const HEAD_SIZES := [3, 8, 6, 4]  # MultiDiscrete heads (ACTION_SPEC.md)
const EXPECT_ACTIONS := [1, 5, 1, 1]

func _ready() -> void:
	var ok := true

	# --- NcnnRunner node + buffer load (exported-.pck path). ---
	var runner := NcnnRunner.new()
	runner.input_blob_name = INPUT_BLOB
	runner.output_blob_name = OUTPUT_BLOB
	add_child(runner)
	var param_bytes := FileAccess.get_file_as_bytes(PARAM_PATH)
	var bin_bytes := FileAccess.get_file_as_bytes(BIN_PATH)
	var files_ok: bool = not param_bytes.is_empty() and not bin_bytes.is_empty()
	var loaded: bool = files_ok and runner.load_model_from_buffers(param_bytes, bin_bytes)
	var loaded_flag: bool = loaded and runner.is_model_loaded()
	print("ISS505 model_files_readable=", files_ok, " loaded_from_buffers=", loaded,
		" is_model_loaded=", loaded_flag)
	ok = ok and loaded_flag
	if not ok:
		print("ISS505 ok=", false)
		get_tree().quit(1)
		return

	# --- Normalize the dummy obs with the exact deploy-side replay. ---
	var stats_text := FileAccess.get_file_as_string(STATS_PATH)
	var stats: Dictionary = JSON.parse_string(stats_text)
	var stats_ok: bool = stats is Dictionary and ObsNormalize.validate(stats)
	print("ISS505 stats_valid=", stats_ok)
	ok = ok and stats_ok
	var norm := PackedFloat32Array()
	if stats_ok:
		var typed := ObsNormalize.to_typed(stats)
		norm = ObsNormalize.normalize(PackedFloat32Array(DUMMY_RAW),
			typed["mean"], typed["var"], typed["epsilon"], typed["clip_obs"])
		var norm_ok: bool = norm.size() == 2 \
			and absf(norm[0] - EXPECT_NORM[0]) < 1e-5 and absf(norm[1] - EXPECT_NORM[1]) < 1e-5
		print("ISS505 norm_replay_matches_sb3=", norm_ok, " (got ", norm, ")")
		ok = ok and norm_ok
	else:
		print("ISS505 ok=", false)
		get_tree().quit(1)
		return

	# --- Inference: per-head argmax of the logits must match the ONNX
	# reference (the run_discrete_action selection: first index wins on ties). ---
	var logits: PackedFloat32Array = runner.run_inference(norm)
	var logits_ok: bool = logits.size() == HEAD_SIZES.reduce(func(a: int, b: int) -> int: return a + b, 0)
	var actions := []
	if logits_ok:
		var offset := 0
		for head_size in HEAD_SIZES:
			actions.append(InferenceMath.argmax(logits.slice(offset, offset + head_size)))
			offset += head_size
	var actions_ok: bool = logits_ok and actions.size() == EXPECT_ACTIONS.size()
	if actions_ok:
		for i in EXPECT_ACTIONS.size():
			if int(actions[i]) != EXPECT_ACTIONS[i]:
				actions_ok = false
				break
	print("ISS505 actions_match_onnx=", actions_ok, " (got ", actions, ", expected ",
		EXPECT_ACTIONS, ", logits ", logits, ")")
	ok = ok and logits_ok and actions_ok

	runner.queue_free()
	print("ISS505 ok=", ok)
	get_tree().quit(0 if ok else 1)
