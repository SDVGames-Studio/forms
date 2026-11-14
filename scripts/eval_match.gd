extends Node2D
## Automated ncnn deployment evaluation (issue #508).
##
## Runs whole-match episodes of the DEPLOYED ncnn policy (InferenceBot,
## the #506 deploy twin: models/policy.ncnn.{param,bin} + the #503
## VecNormalize sidecar) inside a standard Level match — the scripted
## Npc side plays itself, exactly like the shipped game — and records the
## Phase 6 comparison metric set per episode:
##
##   outcome            player / enemy / draw (TurnController._check_win)
##                      or "timeout" (episode frame cap)
##   survival time      episode length in physics ticks / sim seconds
##   damage             per-side health lost totals (polled per frame)
##   action dist        per-head decision counts from the live
##                      inference_step payloads (aim/attack/move/target)
##   mask violations    decisions whose chosen index was mask-ILLEGAL
##                      (must stay 0 — #507 applies masks before argmax;
##                      the count is the (c)-culprit probe of #508)
##   decisions          the full (raw obs -> chosen action) stream
##                      ("decision_stream"), for the Python-inference
##                      baseline replay (eval_baseline.py — SB3/onnxruntime
##                      parity)
##
## Episodes are SEQUENTIAL: TurnController drives exactly one live level
## (get_first_node_in_group("level")), so each episode instances a fresh
## Environment (Level + InferenceBot), plays it to a terminal state, then
## frees it — freeing swaps the "level" group node, which re-triggers
## TurnController._on_level_changed() for the next episode's clean start.
## The NcnnSync agent list is repointed at each fresh InferenceBot
## (agent discovery runs once at init; _inference_process iterates the
## public agents_inference array).
##
## Runs in the EXPORTED standalone build ("Eval (Linux)" preset packs
## eval_build.marker; the TrainingBoot autoload routes to eval_scene.tscn
## — the file-packing / no-editor path issue #508 explicitly targets) and
## headless in the editor for tests:
##
##   builds/eval/forms_eval.x86_64 --headless -- episodes=20 \
##       results=/abs/path/eval_results.json speedup=8
##
## Exit 0 = every requested episode ran and the results JSON was written;
## exit 1 = harness failure (model not loadable, zero episodes, watchdog).
## Emits eval_completed(results) right before quitting (test hook).

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/Level.tscn")
const BotScript := preload("res://scripts/InferenceBot.gd")
const RunSpeed := preload("res://addons/godot_native_rl/training/run_speed.gd")

## inference_scene.tscn's spawn point (arena center).
const SPAWN := Vector2(576, 400)
const PHYSICS_HZ := 60.0

signal eval_completed(results: Dictionary)

## Scene-level defaults; `key=value` cmdline tokens override (same
## convention as the training loop — RunSpeed.parse_cmdline_args).
@export var episodes := 20
@export var episode_turn_time := 3.0
@export var reset_after := 4000
## 0 = auto: reset_after * NcnnSync.action_repeat + 1200 (roll/handover margin).
@export var episode_max_frames := 0
@export var results_path := "user://eval_results.json"
@export var max_wall_sec := 2400.0
@export var eval_tag := "exported"
## The exported build quits by itself (exit code = success); tests embed the
## runner as a child, keep the tree alive and quit from their own verdict.
@export var quit_when_done := true

var _sync: Node = null
var _env: Node = null
var _bot: Node = null
var _figures: Array = []
var _state := 0  # 0 wait-sync | 1 running | 2 ending
var _ep_index := -1
var _ep_start_frames := 0
var _ep_start_wall_ms := 0
var _ep_decisions: Array = []
var _ep_mask_violations := 0
var _ep_action_dist := {}
var _ep_health_prev := {}
var _ep_health_lost := {"player": 0, "enemy": 0}
var _ep_outcome := "timeout"
var _run_start_wall_ms := 0
var _results: Dictionary = {}
var _cfg := {}


func _ready() -> void:
	_sync = get_node("NcnnSync")
	var args := RunSpeed.parse_cmdline_args()
	# `-- key=value` user args (the editor-testable form — positional args in
	# an EDITOR run would be mistaken for scene paths; exported runs accept
	# both, so the harness honors the user-arg form too).
	for ua in OS.get_cmdline_user_args():
		if ua.find("=") > -1:
			var kv := ua.split("=")
			args[kv[0].lstrip("--")] = kv[1]
	_cfg = {
		"episodes": _int_arg(args, "episodes", episodes),
		"turn_time": _float_arg(args, "turn-time", episode_turn_time),
		"reset_after": _int_arg(args, "reset-after", reset_after),
		"cap_frames": _int_arg(args, "cap-frames", episode_max_frames),
		"results_path": str(args.get("results", results_path)),
		"max_wall_sec": _float_arg(args, "max-wall-sec", max_wall_sec),
		"eval_tag": str(args.get("eval-tag", eval_tag)),
	}
	if _cfg["cap_frames"] <= 0:
		_cfg["cap_frames"] = int(_cfg["reset_after"]) * int(_sync.action_repeat) + 1200
	# Compress the idle player turns (nobody drives the human side in an
	# unattended run); TurnController honors GameConfig.turn_time per turn.
	GameConfig.turn_time = _cfg["turn_time"]
	_run_start_wall_ms = Time.get_ticks_msec()
	_init_results()


func _process(_delta: float) -> void:
	if _state == 0:
		if _sync.initialized and not get_tree().paused:
			_start_episode()
		return
	if _state == 1:
		_poll_health()
		var wall_sec := float(Time.get_ticks_msec() - _run_start_wall_ms) / 1000.0
		if TurnController.game_over:
			_end_episode(_outcome_from_alive())
		elif _ep_frames() >= int(_cfg["cap_frames"]):
			_end_episode("timeout")
		elif wall_sec >= float(_cfg["max_wall_sec"]):
			push_error("EvalMatch: wall watchdog (%s s) hit at episode %d"
					% [str(_cfg["max_wall_sec"]), _ep_index + 1])
			_end_episode("timeout", true)
		return
	# state 2: the environment was freed — start the next episode or finish.
	if not is_instance_valid(_env):
		if _ep_index + 1 < int(_cfg["episodes"]):
			_start_episode()
		else:
			_finish(true)


func _start_episode() -> void:
	_ep_index += 1
	_env = LEVEL_SCENE.instantiate()
	_sync.add_child(_env)
	_bot = BotScript.new()
	_bot.position = SPAWN
	_bot.control_mode = NcnnAIController2D.ControlModes.NCNN_INFERENCE
	_bot.reset_after = int(_cfg["reset_after"])
	_env.add_child(_bot)
	# Agent discovery ran once at sync init — repoint the inference list
	# at the fresh bot so _inference_process drives this episode's agent.
	_sync.agents_inference = [_bot]
	_bot.inference_step.connect(_on_inference_step)
	_figures = []
	for child in _env.get_children():
		if child.get("health") != null:
			_figures.append({
				"node": child,
				"side": "enemy" if child.is_in_group("enemy_team") else "player",
			})
	_ep_health_prev = {}
	_ep_health_lost = {"player": 0, "enemy": 0}
	_ep_decisions = []
	_ep_mask_violations = 0
	_ep_action_dist = {}
	for key in _bot.get_action_space().keys():
		var counts: Array = []
		counts.resize(int(_bot.get_action_space()[key]["size"]))
		counts.fill(0)
		_ep_action_dist[key] = counts
	_ep_start_frames = Engine.get_physics_frames()
	_ep_start_wall_ms = Time.get_ticks_msec()
	_state = 1
	print("EVAL episode %d/%d started" % [_ep_index + 1, int(_cfg["episodes"])])


func _end_episode(outcome: String, aborted := false) -> void:
	_ep_outcome = outcome
	var alive := _alive_counts()
	var episode := {
		"index": _ep_index,
		"outcome": outcome,
		"alive_player": alive["player"],
		"alive_enemy": alive["enemy"],
		"frames": _ep_frames(),
		"sim_seconds": _ep_frames() / PHYSICS_HZ,
		"wall_seconds": float(Time.get_ticks_msec() - _ep_start_wall_ms) / 1000.0,
		"decisions": _ep_decisions.size(),
		"decision_stream": _ep_decisions,
		"mask_violations": _ep_mask_violations,
		"player_health_lost": _ep_health_lost["player"],
		"enemy_health_lost": _ep_health_lost["enemy"],
		"action_dist": _ep_action_dist,
	}
	if outcome != "timeout":
		episode["winner"] = outcome
	_results["episodes"].append(episode)
	print("EVAL episode %d/%d %s in %d ticks (%.1f sim s), decisions=%d, alive p/e=%d/%d"
			% [_ep_index + 1, int(_cfg["episodes"]), outcome, episode["frames"],
				episode["sim_seconds"], episode["decisions"],
				alive["player"], alive["enemy"]])
	if _bot != null and is_instance_valid(_bot):
		if _bot.inference_step.is_connected(_on_inference_step):
			_bot.inference_step.disconnect(_on_inference_step)
	_sync.agents_inference = []
	_bot = null
	_env.queue_free()
	_figures = []
	if aborted:
		_ep_index = int(_cfg["episodes"])  # skip remaining episodes
	_state = 2


func _finish(ok: bool) -> void:
	_state = 3
	# Engine throughput state AFTER NcnnSync._initialize applied the speedup
	# (at _ready time it was still the 1.0 baseline).
	_results["build"]["time_scale"] = Engine.time_scale
	_results["build"]["physics_ticks_per_second"] = Engine.physics_ticks_per_second
	_results["build"]["max_physics_steps_per_frame"] = Engine.max_physics_steps_per_frame
	_summarize()
	var text := JSON.stringify(_results, "  ")
	var path := str(_cfg["results_path"])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("EvalMatch: cannot write results to '%s' (error %d)"
				% [path, FileAccess.get_open_error()])
		_quit(1)
		return
	f.store_string(text)
	f.close()
	print("EVAL results written to %s" % ProjectSettings.globalize_path(path))
	print("EVAL summary: %s" % JSON.stringify(_results["summary"]))
	eval_completed.emit(_results)
	if quit_when_done:
		_quit(0 if ok and _results["episodes"].size() >= int(_cfg["episodes"]) else 1)


func _quit(code: int) -> void:
	get_tree().quit(code)


func is_done() -> bool:
	return _state == 3


func _on_inference_step(_debug: Dictionary) -> void:
	# Fires before set_action applies, so get_obs() is the exact RAW vector
	# this decision consumed (same contract tests/test_issue506.gd relies on).
	if _bot == null or not is_instance_valid(_bot):
		return
	var joint := {}
	var raw: Array = _bot.get_obs()["obs"]
	var mask: Dictionary = _debug.get("action_mask", {})
	for key in _bot.get_action_space().keys():
		var idx := clampi(int(_debug["action"][key]), 0,
				int(_ep_action_dist[key].size()) - 1)
		joint[key] = idx
		_ep_action_dist[key][idx] += 1
		# #507 audit: the deployed argmax must never land on a masked-ILLEGAL
		# slot (ActionMask rewrites them to -1e9 before decode). Counting the
		# violations surfaces culprit (c) of #508 from real exported matches.
		if mask.has(key) and not bool(mask[key][idx]):
			_ep_mask_violations += 1
	_ep_decisions.append({"obs": raw, "action": joint})


func _poll_health() -> void:
	for entry in _figures:
		# Untyped first: a dead figure is queue_free()d after its death tween,
		# and assigning a Variant holding a FREED instance to a typed Node var
		# throws before any is_instance_valid guard can run.
		var fig = entry["node"]
		if fig == null or not is_instance_valid(fig):
			continue
		var health = fig.get("health")
		if health == null:
			continue
		var key: int = fig.get_instance_id()
		var prev = _ep_health_prev.get(key, health)
		var delta := int(prev) - int(health)
		if delta > 0:
			_ep_health_lost[entry["side"]] += delta
		_ep_health_prev[key] = health


func _alive_counts() -> Dictionary:
	var counts := {"player": 0, "enemy": 0}
	for entry in _figures:
		# Untyped-first (see _poll_health): freed figures must not be assigned
		# to a typed Node variable.
		var fig = entry["node"]
		if fig == null or not is_instance_valid(fig):
			continue
		var health = fig.get("health")
		if health != null and int(health) > 0:
			counts[entry["side"]] += 1
	return counts


func _outcome_from_alive() -> String:
	var alive := _alive_counts()
	if alive["player"] > 0 and alive["enemy"] == 0:
		return "player"
	if alive["enemy"] > 0 and alive["player"] == 0:
		return "enemy"
	if alive["player"] == 0 and alive["enemy"] == 0:
		return "draw"
	return "timeout"  # game_over with both sides alive (banner race)


func _ep_frames() -> int:
	return Engine.get_physics_frames() - _ep_start_frames


func _init_results() -> void:
	_results = {
		"schema_version": 1,
		"tag": str(_cfg["eval_tag"]),
		"build": {
			"kind": "editor" if OS.has_feature("editor") else "exported",
			"godot": Engine.get_version_info()["string"],
			"time_scale": Engine.time_scale,
			"physics_ticks_per_second": Engine.physics_ticks_per_second,
			"turn_time": _cfg["turn_time"],
			"reset_after": _cfg["reset_after"],
			"cap_frames": _cfg["cap_frames"],
			"action_repeat": _sync.action_repeat,
			"model_param": "res://models/policy.ncnn.param",
			"model_bin": "res://models/policy.ncnn.bin",
			"obs_norm_stats": "res://models/vecnormalize_stats.json",
			"spawn": [SPAWN.x, SPAWN.y],
			"started_at": Time.get_datetime_string_from_system(true),
		},
		"config": _cfg.duplicate(),
		"episodes": [],
		"summary": {},
	}


func _summarize() -> void:
	var outcomes := {"player": 0, "enemy": 0, "draw": 0, "timeout": 0}
	var sim_secs: Array[float] = []
	var walls: Array[float] = []
	var decisions := 0
	var mask_violations := 0
	var health := {"player": 0, "enemy": 0}
	var dist := {}
	for episode in _results["episodes"]:
		outcomes[episode["outcome"]] += 1
		sim_secs.append(float(episode["sim_seconds"]))
		walls.append(float(episode["wall_seconds"]))
		decisions += int(episode["decisions"])
		mask_violations += int(episode.get("mask_violations", 0))
		health["player"] += int(episode["player_health_lost"])
		health["enemy"] += int(episode["enemy_health_lost"])
		for head in episode["action_dist"].keys():
			if not dist.has(head):
				dist[head] = (episode["action_dist"][head] as Array).duplicate()
			else:
				for i in (episode["action_dist"][head] as Array).size():
					dist[head][i] += episode["action_dist"][head][i]
	var n: int = _results["episodes"].size()
	var decided: int = outcomes["player"] + outcomes["enemy"] + outcomes["draw"]
	_results["summary"] = {
		"episodes": n,
		"outcomes": outcomes,
		"win_rate_player": float(outcomes["player"]) / decided if decided > 0 else null,
		"win_rate_enemy": float(outcomes["enemy"]) / decided if decided > 0 else null,
		"timeout_frac": float(outcomes["timeout"]) / n if n > 0 else null,
		"avg_sim_seconds": _mean(sim_secs),
		"avg_wall_seconds": _mean(walls),
		"total_decisions": decisions,
		"avg_decisions": float(decisions) / n if n > 0 else null,
		"mask_violations": mask_violations,
		"player_health_lost_total": health["player"],
		"enemy_health_lost_total": health["enemy"],
		"action_dist_all": dist,
	}


func _mean(values: Array) -> Variant:
	if values.is_empty():
		return null
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _int_arg(args: Dictionary, key: String, fallback: int) -> int:
	if not args.has(key):
		return fallback
	var raw := str(args[key])
	if not raw.is_valid_int() or int(raw) < 1:
		push_error("EvalMatch: cmdline %s=%s is not a positive integer" % [key, raw])
		return fallback
	return int(raw)


func _float_arg(args: Dictionary, key: String, fallback: float) -> float:
	if not args.has(key):
		return fallback
	var raw := str(args[key])
	if not raw.is_valid_float() or raw.to_float() <= 0.0:
		push_error("EvalMatch: cmdline %s=%s is not a positive number" % [key, raw])
		return fallback
	return raw.to_float()
