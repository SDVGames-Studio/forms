extends Node
## Regression check for issue #445: shared policies by role — every bot of
## the same role reports the SAME policy_name, and every agent sharing a
## policy_name returns IDENTICAL observation/action spaces.
##
## - Scene config: training_scene.tscn (instantiated WITHOUT entering the
##   tree, so NcnnSync never attempts the training-server connection) stages
##   exactly 3 bot agents, each carrying the explicit role policy
##   "soldier" — the single-role team deathmatch of today reports ONE
##   distinct policy to the Python trainer.
## - Critical constraint: within a policy_name group, every agent's
##   get_action_space() dictionary and get_obs() key set + vector widths
##   must match exactly — the trainer builds the wire spaces from the first
##   agent of the group and any drift is a space-mismatch failure at
##   runtime. _policy_space_violations() is the guard.
## - Negative control: a hypothetical second role (MedicBot, different
##   action space) under the SAME policy_name is flagged; under its OWN
##   policy_name it is legal — two roles, two distinct policies.
##
## Run headless: godot --headless res://tests/test_issue445.tscn
## Exit code 0 = pass.

const PolicyNames := preload("res://addons/godot_native_rl/policy_names.gd")
const TrainingBotScript := preload("res://scripts/TrainingBot.gd")

## A hypothetical second role (issue #445's "medic"): same obs contract, a
## DIFFERENT action space — legal only under its own distinct policy_name.
class MedicBot extends "res://scripts/TrainingBot.gd":
	func get_action_space() -> Dictionary:
		return {
			"move": {"size": 6, "action_type": "discrete"},
			"aim": {"size": 3, "action_type": "discrete"},
			"heal": {"size": 2, "action_type": "discrete"},
		}


func _ready() -> void:
	var ok := true

	# --- Scenario 1: the shipped scene — one role, one shared policy ------
	var scene: Node = load("res://scenes/testing/training_scene.tscn").instantiate()
	var agents := _collect_bot_agents(scene)
	ok = _expect(agents.size() == 3,
			"training_scene.tscn stages 3 bot agents, got %d" % agents.size()) and ok

	var policy_list := PolicyNames.policy_names_from_agents(agents, false)
	var distinct := {}
	for i in agents.size():
		var agent_name: String = policy_list[i]
		distinct[agent_name] = true
		ok = _expect(agent_name == "soldier",
				"bot %d carries the role policy_name 'soldier', got '%s'" % [i, agent_name]) and ok
	ok = _expect(distinct.size() == 1,
			"single-role scene exposes exactly 1 distinct policy, got %d" % distinct.size()) and ok

	# --- Scenario 2: same policy_name => identical spaces ------------------
	var violations := _policy_space_violations(agents)
	ok = _expect(violations.is_empty(),
			"all 'soldier' agents return identical obs/action spaces, got %s" % str(violations)) and ok

	# --- Scenario 3: negative control — mismatch under a SHARED name ------
	var soldier := TrainingBotScript.new()
	var medic := MedicBot.new()  # a different role under the WRONG name
	for bot in [soldier, medic]:
		bot.set("policy_name", "soldier")
	violations = _policy_space_violations([soldier, medic])
	ok = _expect(violations.size() == 1,
			"a second action space under the same policy_name is flagged, got %s" % str(violations)) and ok

	# --- Scenario 4: the same medic under its OWN name is legal -----------
	medic.set("policy_name", "medic")
	violations = _policy_space_violations([soldier, medic])
	ok = _expect(violations.is_empty(),
			"distinct roles under distinct policy_names need no space match") and ok
	distinct = {}
	for n in PolicyNames.policy_names_from_agents([soldier, medic], false):
		distinct[n] = true
	ok = _expect(distinct.size() == 2,
			"two roles report two distinct policies, got %d" % distinct.size()) and ok

	scene.free()
	soldier.free()
	medic.free()

	print("ISSUE445 ok=", ok)
	get_tree().quit(1 if not ok else 0)


## Depth-first walk collecting nodes whose script is TrainingBot.gd or a
## subclass of it (MedicBot), so instanced Level internals are skipped.
func _collect_bot_agents(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is TrainingBotScript:
			found.append(child)
		found.append_array(_collect_bot_agents(child))
	return found


## Issue #445's critical constraint: agents sharing a policy_name must
## return IDENTICAL spaces. Returns one "<policy>: <agent>" entry per group
## member whose action-space dict, obs keys, or obs widths differ from the
## group's first member (the one the Python trainer builds the wire spaces
## from).
func _policy_space_violations(agents: Array) -> Array[String]:
	var by_policy := {}
	for agent in agents:
		var agent_policy: String = PolicyNames.policy_names_from_agents([agent], false)[0]
		if not by_policy.has(agent_policy):
			by_policy[agent_policy] = []
		by_policy[agent_policy].append(agent)

	var violations: Array[String] = []
	for policy in by_policy:
		var group: Array = by_policy[policy]
		var sig0 := _space_signature(group[0])
		for agent in group.slice(1):
			if _space_signature(agent) != sig0:
				violations.append("%s: %s" % [policy, str(agent)])
	return violations


## Comparable per-agent space fingerprint: the full action-space dictionary
## plus each obs vector's width keyed by its obs key (width + key set, not
## values — values differ per agent by design).
func _space_signature(agent: Node) -> Dictionary:
	var obs: Dictionary = agent.get_obs()
	var widths := {}
	for key in obs:
		widths[key] = obs[key].size()
	return {"action_space": agent.get_action_space(), "obs_widths": widths}


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		print("FAIL ", what)
	return cond
