extends Node
## Regression check for issue #688: "Implement Runtime BotController
## Injection for Dynamically Spawned Characters" — computer-played
## figures must receive their RL policy controller at RUNTIME (created
## in code, never attached in the editor), configured for native ncnn
## inference and stepped by an injected NcnnSync without any Python
## server; human-played teams must keep their input brain and get NO
## controller; authored RL scenes (levels instanced under an NcnnSync)
## must be left untouched.
##
##  1. DECODE (compact): the retrained policy bakes the per-head argmax
##     into the graph — out0 holds ONE chosen index per head, in the
##     alphabetical order SB3 exports use. ActionDecode must map
##     output[i] onto the i-th sorted head, clamping corrupt values.
##  2. DECODE (flat legacy): a logits-sized output still slices per key
##     in insertion order — the pre-#688 nets' path is unchanged.
##  3. DECODE (mismatch): a wrong-size output against a non-matching
##     head count stays the empty-dict sentinel.
##  4. INJECTION (computer default): a directly-run level (fresh boot
##     config — every team plays the computer) ends with every live
##     Npc-brained figure carrying a BotController child, pinned to it
##     (figure_path resolves to the parent), NCNN_INFERENCE mode, the
##     deployed model paths, auto_reset OFF, the scripted AI stood down
##     (rl_controlled), and exactly one NcnnSync driving them all.
##  5. DECISIONS: the injected sync actually steps the policy natively
##     — inference_step fires with the REAL deployed net, no Python.
##  6. INJECTION (human teams): with every configured team set to
##     "player" no figure receives a controller and no sync is added.
##  7. INJECTION (authored RL scene): a level instanced UNDER an
##     NcnnSync (the training/eval/inference-demo staging) is skipped —
##     no injected bots, no second sync.
##
## Run headless: godot --headless res://tests/test_issue688.tscn
## Exit code 0 = pass.

const ActionDecode := preload("res://addons/godot_native_rl/controllers/action_decode.gd")
const BotControllerScript := preload("res://scripts/BotController.gd")
const Level1Scene := preload("res://scenes/levels/Level1.tscn")
const Level2Scene := preload("res://scenes/levels/Level2.tscn")
const SyncScript := preload("res://addons/godot_native_rl/sync.gd")

var failures := 0
var decisions := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## The full BotController action declaration (issue #607): five discrete
## heads in wire order, sizes 6/3/11/4/5 = 29 flat slots.
func _bot_action_space() -> Dictionary:
	return {
		"move": {"size": 6, "action_type": "discrete"},
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 11, "action_type": "discrete"},
		"target": {"size": 4, "action_type": "discrete"},
		"tool": {"size": 5, "action_type": "discrete"},
	}


## The live Npc-brained figures of a level (the injection candidates).
func _computer_figures(level: Node) -> Array:
	var figures: Array = []
	for group in ["player_team", "enemy_team"]:
		for figure in get_tree().get_nodes_in_group(group):
			if figure != null and figure is Node2D \
					and not figure.is_queued_for_deletion() \
					and level.is_ancestor_of(figure) \
					and figure.has_method("_shoot"):
				figures.append(figure)
	return figures


## The BotController child of a figure, or null.
func _rl_bot(figure: Node) -> Node:
	for child in figure.get_children():
		var script: Script = child.get_script()
		if script != null and script.resource_path == "res://scripts/BotController.gd":
			return child
	return null


func _reset_game_config() -> void:
	GameConfig.teams = []
	GameConfig.team_size = 0
	GameConfig.enemy_count = 0
	GameConfig.menu_team_sizes = false


func _ready() -> void:
	# --- 1. Compact per-head-index decode -------------------------------
	var compact := ActionDecode.decode_actions(
		PackedFloat32Array([1, 2, 3, 0, 4]), _bot_action_space())
	_check(compact.get("aim", -1) == 1 and compact.get("attack", -1) == 2
			and compact.get("move", -1) == 3 and compact.get("target", -1) == 0
			and compact.get("tool", -1) == 4,
			"compact output must map to the alphabetically sorted heads (got %s)"
			% str(compact))
	# Corrupt values clamp into each head's legal range, not error.
	var clamped := ActionDecode.decode_actions(
		PackedFloat32Array([9, -1, 3, 0, 4]), _bot_action_space())
	_check(clamped.get("aim", -1) == 2 and clamped.get("attack", -1) == 0
			and clamped.get("tool", -1) == 4,
			"out-of-range compact values must clamp into the head (got %s)"
			% str(clamped))

	# --- 2. Flat logits decode unchanged ---------------------------------
	var flat := PackedFloat32Array()
	flat.resize(29)
	flat.fill(0.0)
	flat[1] = 9.0    # move segment (0..5): index 1
	flat[8] = 9.0    # aim segment (6..8): index 2
	flat[19] = 9.0   # attack segment (9..19): index 10
	flat[21] = 9.0   # target segment (20..23): index 1
	flat[28] = 9.0   # tool segment (24..28): index 4
	var flat_decoded := ActionDecode.decode_actions(flat, _bot_action_space())
	_check(flat_decoded.get("move", -1) == 1 and flat_decoded.get("aim", -1) == 2
			and flat_decoded.get("attack", -1) == 10
			and flat_decoded.get("target", -1) == 1
			and flat_decoded.get("tool", -1) == 4,
			"flat logits output must still slice per key in insertion order (got %s)"
			% str(flat_decoded))

	# --- 3. Real mismatch stays the empty sentinel -----------------------
	var bad := ActionDecode.decode_actions(
		PackedFloat32Array([1, 2, 3]), _bot_action_space())
	_check(bad.is_empty(),
			"a wrong-size output against a non-matching head count must stay {}")

	# --- 4. Production injection: computer default -----------------------
	_reset_game_config()
	var level := Level1Scene.instantiate()
	add_child(level)
	await _frames(3)
	var figures := _computer_figures(level)
	_check(figures.size() >= 4,
			"a directly-run level must field computer figures (got %d)"
			% figures.size())
	var bots := 0
	for figure in figures:
		var bot := _rl_bot(figure)
		if bot == null:
			_check(false, "computer figure '%s' has no BotController child"
					% str(figure.name))
			continue
		bots += 1
		_check(bot.figure_path != null and not bot.figure_path.is_empty()
				and bot.get_node_or_null(bot.figure_path) == figure,
				"bot on '%s' must be pinned to its figure" % str(figure.name))
		_check(int(bot.control_mode) == 3,
				"bot on '%s' must be NCNN_INFERENCE (got %d)"
				% [str(figure.name), int(bot.control_mode)])
		_check(str(bot.model_param_path) == GameConfig.RL_MODEL_PARAM
				and str(bot.model_bin_path) == GameConfig.RL_MODEL_BIN
				and str(bot.obs_norm_stats_path) == GameConfig.RL_OBS_NORM_STATS,
				"bot on '%s' must carry the deployed model paths" % str(figure.name))
		_check(bool(figure.get("rl_controlled")) == true,
				"figure '%s' scripted AI must be stood down" % str(figure.name))
		_check(bool(bot.get("auto_reset")) == false,
				"bot on '%s' must not auto-reset a production match"
				% str(figure.name))
	_check(bots == figures.size(),
			"every computer figure must carry a bot (%d/%d)" % [bots, figures.size()])
	var sync: Node = null
	for child in level.get_children():
		if child is NcnnSync:
			sync = child
	_check(sync != null, "the level must host exactly one NcnnSync")
	var waited := 0
	while sync != null and not sync.initialized and waited < 300:
		await _frames(1)
		waited += 1
	_check(sync != null and sync.initialized,
			"the injected sync must initialize (no Python server needed)")
	_check(sync != null and sync.agents_inference.size() == bots,
			"the sync must drive every injected bot (%d/%d)"
			% [sync.agents_inference.size() if sync != null else -1, bots])

	# --- 5. The deployed net decides natively ----------------------------
	decisions = 0
	var probe_bot := _rl_bot(figures[0])
	if probe_bot != null:
		probe_bot.inference_step.connect(func(_payload) -> void: decisions += 1)
		# Issue #688: the NCNN-mode space lists the heads in the deployed
		# net's alphabetical emit order; the training wire order stays
		# move/aim/attack/target/tool.
		var deploy_keys: Array = probe_bot.get_action_space().keys()
		_check(deploy_keys == ["aim", "attack", "move", "target", "tool"],
				"NCNN-mode action space must be alphabetical (got %s)"
				% str(deploy_keys))
	var wire_bot = BotControllerScript.new()
	var wire_keys: Array = wire_bot.get_action_space().keys()
	_check(wire_keys == ["move", "aim", "attack", "target", "tool"],
			"training-mode action space must keep the ACTION_SPEC wire order (got %s)"
			% str(wire_keys))
	wire_bot.free()
	await _frames(120)
	_check(decisions >= 1,
			"the deployed ncnn policy must produce decisions (got %d)" % decisions)

	level.queue_free()
	await _frames(3)

	# --- 6. Human teams get no controllers --------------------------------
	_reset_game_config()
	GameConfig.load_teams()
	for team in GameConfig.teams:
		team["controller"] = "player"
	var level2 := Level2Scene.instantiate()
	add_child(level2)
	await _frames(3)
	var stray_bots := 0
	for group in ["player_team", "enemy_team"]:
		for figure in get_tree().get_nodes_in_group(group):
			if figure is Node2D and level2.is_ancestor_of(figure) \
					and _rl_bot(figure) != null:
				stray_bots += 1
	var stray_sync := 0
	for child in level2.get_children():
		if child is NcnnSync:
			stray_sync += 1
	_check(stray_bots == 0, "human teams must receive no RL controller (got %d)"
			% stray_bots)
	_check(stray_sync == 0, "an all-human level needs no NcnnSync (got %d)"
			% stray_sync)

	level2.queue_free()
	await _frames(3)

	# --- 7. Authored RL scenes are skipped --------------------------------
	_reset_game_config()
	var authored_sync: NcnnSync = SyncScript.new()
	authored_sync.control_mode = NcnnSync.ControlModes.TRAINING
	add_child(authored_sync)
	var level3 := Level1Scene.instantiate()
	authored_sync.add_child(level3)
	await _frames(3)
	var authored_bots := 0
	for figure in _computer_figures(level3):
		if _rl_bot(figure) != null:
			authored_bots += 1
	var injected_sync := 0
	for child in level3.get_children():
		if child is NcnnSync:
			injected_sync += 1
	_check(authored_bots == 0,
			"a level under an authored NcnnSync must not get injected bots (got %d)"
			% authored_bots)
	_check(injected_sync == 0,
			"a level under an authored NcnnSync must not get a second sync (got %d)"
			% injected_sync)

	if failures == 0:
		print("PASS: issue #688 runtime BotController injection")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
