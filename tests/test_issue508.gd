extends Node
## Issue #508 checks: the automated ncnn deployment evaluation runs REAL
## whole-match episodes end-to-end through the deployed pipeline — fresh
## Level (scripted Npc side) + InferenceBot (ncnn model + VecNormalize
## sidecar + #410 masks) per episode, sequential matches under the global
## TurnController — and produces a structured results JSON with the Phase 6
## comparison metrics: per-episode outcome / survival time / side damage +
## per-head action distributions + the full (raw obs -> action) stream the
## Python baseline replays (eval_baseline.py).
##
## This test runs a MINI eval (2 episodes, short turn timer, tight frame
## cap) headless in the editor via the same scene the exported build boots
## (eval_scene.tscn — the "Eval (Linux)" preset packs eval_build.marker and
## TrainingBoot routes to it; issue #508's exported-build requirement is
## exercised by the documented command in DEPLOYMENT_REPORT.md).
##
## Definition of Done (issue #508, harness half): episodes actually run and
## terminate with a recorded outcome, decisions were taken by the live ncnn
## path (>= 1 per episode, valid + mask-legal indices), every metric family
## is present in the JSON, and the results file parses back.
##
## Run headless: godot --headless res://tests/test_issue508.tscn
## Exit code 0 = pass; the printed ISS508 ok= verdict is authoritative.

const SCENE_PATH := "res://scenes/testing/eval_scene.tscn"
const RESULTS_PATH := "user://test_issue508_results.json"

var _results: Dictionary = {}


func _ready() -> void:
	var ok := true
	var scene: PackedScene = load(SCENE_PATH)
	var runner = scene.instantiate()
	runner.episodes = 2
	runner.episode_turn_time = 2.0
	runner.reset_after = 4000
	runner.episode_max_frames = 900  # ~15 sim s per episode — fast mini run
	runner.results_path = RESULTS_PATH
	runner.eval_tag = "test"
	runner.quit_when_done = false
	runner.eval_completed.connect(_on_done)
	add_child(runner)
	await runner.eval_completed
	while not runner.is_done():
		await get_tree().process_frame

	# --- Episodes: every requested one ran, each with a valid outcome. ---
	var eps: Array = _results.get("episodes", [])
	ok = _expect(eps.size() == 2, "two episodes recorded (got %d)" % eps.size()) and ok
	for ep in eps:
		ok = _expect(ep.get("outcome") in ["player", "enemy", "draw", "timeout"],
				"episode %s has a valid outcome (%s)" % [str(ep.get("index")), str(ep.get("outcome"))]) and ok
		ok = _expect(int(ep.get("frames", 0)) > 0 and float(ep.get("sim_seconds", 0.0)) > 0.0,
				"episode %s recorded survival time" % str(ep.get("index"))) and ok
		ok = _expect(ep.has("player_health_lost") and ep.has("enemy_health_lost"),
				"episode %s recorded side damage" % str(ep.get("index"))) and ok

	# --- Live ncnn decisions with valid, distribution-counted heads. ---
	var heads := {}
	var decisions := 0
	for ep in eps:
		decisions += int(ep.get("decisions", 0))
		for head in (ep.get("action_dist", {}) as Dictionary).keys():
			if not heads.has(head):
				heads[head] = (ep["action_dist"][head] as Array).duplicate()
			else:
				for i in (ep["action_dist"][head] as Array).size():
					heads[head][i] += ep["action_dist"][head][i]
	ok = _expect(decisions >= 2, "ncnn decisions recorded (got %d)" % decisions) and ok
	var violations := 0
	var stream_entries := 0
	for ep in eps:
		violations += int(ep.get("mask_violations", 0))
		stream_entries += (ep.get("decision_stream", []) as Array).size()
	ok = _expect(violations == 0, "no mask-illegal deployed actions (got %d)" % violations) and ok
	ok = _expect(stream_entries == decisions, "decision stream fully recorded (%d/%d)" % [stream_entries, decisions]) and ok
	ok = _expect(heads.keys().size() == 4 and heads.has("aim") and heads.has("attack")
			and heads.has("move") and heads.has("target"),
			"all four heads distributed (got %s)" % str(heads.keys())) and ok
	for head in heads.keys():
		var counts: Array = heads[head]
		var summed := 0
		for c in counts:
			summed += int(c)
		ok = _expect(summed == decisions_from_eps(eps),
				"head %s counts cover every decision (%d/%d)" % [head, summed, decisions_from_eps(eps)]) and ok

	# --- Summary aggregate + results file round-trip. ---
	var summary: Dictionary = _results.get("summary", {})
	ok = _expect(int(summary.get("episodes", 0)) == 2, "summary episode count") and ok
	ok = _expect(summary.has("win_rate_player") and summary.has("timeout_frac")
			and summary.has("avg_sim_seconds") and summary.has("action_dist_all"),
			"summary carries the Phase 6 comparison families") and ok
	var text := FileAccess.get_file_as_string(RESULTS_PATH)
	var reparsed = JSON.parse_string(text)
	ok = _expect(reparsed is Dictionary and (reparsed as Dictionary).has("episodes"),
			"results file parses back as JSON") and ok

	print("ISS508 ok=", ok)
	get_tree().quit(0 if ok else 1)


func decisions_from_eps(eps: Array) -> int:
	var total := 0
	for ep in eps:
		total += int(ep.get("decisions", 0))
	return total


func _on_done(results: Dictionary) -> void:
	_results = results


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
