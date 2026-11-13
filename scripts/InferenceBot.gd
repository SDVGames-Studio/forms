extends "res://scripts/TrainingBot.gd"

## Native-ncnn deploy twin of TrainingBot (issue #506).
##
## Everything — raw get_obs() vector, reward scaffold, #410 action masking,
## set_action — is inherited from the training scaffold unchanged. Only the
## action-space HEAD ORDER differs, and that difference is the whole point:
## NcnnAIController2D decodes the policy's flat 21-value output by slicing
## one contiguous segment per get_action_space() key in dict insertion order
## (ActionDecode.decode_actions), and the deployed net
## (models/policy.ncnn.*, issues #502–#505) emits the heads exactly as the
## trainer's SB3 MultiDiscrete laid them out — alphabetically,
## [aim(3), attack(8), move(6), target(4)]; tests/test_issue505.gd pins that
## layout against the ONNX reference. TrainingBot.gd keeps the ACTION_SPEC.md
## §1 wire order (move, aim, attack, target) for the Python training bridge
## and masks, so this deploy-side override re-orders the SAME heads (same
## names, sizes and action_type) into the network's output layout — the
## multi-discrete structure used during training — so the ncnn path
## interprets the network's output correctly (issue #506).

func _init() -> void:
	# Deploy defaults (issue #506): the res://models/ artifacts from
	# #502–#505. inference_scene.tscn sets these properties explicitly too;
	# the defaults make a dropped-in InferenceBot work out of the box.
	model_param_path = "res://models/policy.ncnn.param"
	model_bin_path = "res://models/policy.ncnn.bin"
	obs_norm_stats_path = "res://models/vecnormalize_stats.json"

func get_action_space() -> Dictionary:
	# Issue #506: same four heads as TrainingBot (ACTION_SPEC.md §1), but
	# insertion-ordered to the deployed policy's output layout —
	# MultiDiscrete([3, 8, 6, 4]) = aim, attack, move, target — so
	# ActionDecode slices the network's logits onto the right heads.
	# get_action_mask() (inherited) iterates these keys by name, so the
	# mask stays correct under the reordering.
	return {
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 8, "action_type": "discrete"},
		"move": {"size": 6, "action_type": "discrete"},
		"target": {"size": 4, "action_type": "discrete"},
	}
