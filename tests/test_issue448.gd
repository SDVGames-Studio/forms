extends Node
## Regression check for issue #448: one-agent-per-step turn sequencing
## under NcnnSync. The Sync's stock loop batches every agent in the
## "AGENT" group (obs from all, actions applied to all, simultaneously);
## a turn-based game must let ONE bot act per decision step, advance the
## turn before the next obs batch, and show each bot acting exactly once
## per round in the turn log.
##
## Pins the Definition of Done against the real code paths:
##   - TurnCoordinator cycles the queue in stable order, advancing the
##     turn only after record_action_and_advance() (so at the NEXT obs
##     collection — next decision step, after the world ticked the
##     applied action — the next bot is active).
##   - NcnnSync._set_agent_actions() with turn_based_sequencing applies
##     ONLY the active bot's action; with it off, the stock batch applies
##     every agent's action (parallel single-bot environments unchanged).
##   - The structured turn log holds one entry per applied turn and each
##     bot appears exactly once per round.
##   - A freed (fallen) bot's turn passes to the next alive bot.
##   - NcnnSync._reset_agents() restarts the turn order for a fresh
##     episode.
##
## Run headless: godot --headless res://tests/test_issue448.tscn
## Exit code 0 = pass.

const TurnCoordinatorScript := preload("res://addons/godot_native_rl/training/turn_coordinator.gd")
const NcnnSyncScript := preload("res://addons/godot_native_rl/sync.gd")

## Minimal agent stand-in: records every applied action, carries the
## needs_reset flag NcnnSync._reset_agents() writes.
class FakeAgent extends Node2D:
	var applied: Array = []
	var needs_reset := false

	func set_action(action) -> void:
		applied.append(action)

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	_check_coordinator_cycles_in_order()
	_check_each_bot_once_per_round()
	_check_reset_restarts_order()
	_check_freed_agent_passes_turn()
	_check_sync_gates_to_active_agent()
	_check_sync_stock_batch_unchanged()
	_check_sync_reset_restarts_turn_order()
	_check_turn_advances_before_next_obs()
	_report()

func _agent(agent_name: String) -> FakeAgent:
	var a := FakeAgent.new()
	a.name = agent_name
	add_child(a)
	return a

## Assign the agent batch to a bare (not-in-tree) NcnnSync instance.
## agents_training is a typed Array[Node] — a plain array literal assigned
## at runtime is REJECTED ("Invalid assignment ... with value of type
## 'Array'") and aborts the calling function, so the arrays are built and
## validated explicitly via assign().
func _bind_training(sync, agents: Array) -> void:
	var typed: Array[Node] = []
	typed.assign(agents)
	sync.agents_training = typed
	sync.all_agents = agents.duplicate()

func _expect(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)

## The queue cycles in stable order: A, B, C, then A again in round 2.
## current_agent() never moves on its own — only record_action_and_advance().
func _check_coordinator_cycles_in_order() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var c := _agent("BotC")
	var tc = TurnCoordinatorScript.new()
	tc.setup([a, b, c])
	_expect(tc.current_agent() == a, "first active agent must be BotA")
	_expect(tc.current_round == 1, "episode starts at round 1")
	tc.record_action_and_advance()
	_expect(tc.current_agent() == b, "after BotA acts, BotB must be active")
	tc.record_action_and_advance()
	_expect(tc.current_agent() == c, "after BotB acts, BotC must be active")
	tc.record_action_and_advance()
	_expect(tc.current_agent() == a, "after BotC acts the queue wraps to BotA")
	_expect(tc.current_round == 2, "a full cycle through the queue starts round 2")
	a.free(); b.free(); c.free()

## DoD: drive two full rounds and read the structured turn log — every
## alive bot appears EXACTLY once per round.
func _check_each_bot_once_per_round() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var c := _agent("BotC")
	var tc = TurnCoordinatorScript.new()
	tc.setup([a, b, c])
	for i in 6:
		tc.record_action_and_advance()
	var entries: Array = tc.get_turn_log()
	_expect(entries.size() == 6, "two rounds of three bots must log 6 turns, got %d" % entries.size())
	for round_index in [1, 2]:
		var counts: Dictionary = tc.turn_counts(round_index)
		_expect(counts.size() == 3, "round %d must list 3 agents, got %d" % [round_index, counts.size()])
		for agent_name in ["BotA", "BotB", "BotC"]:
			_expect(int(counts.get(agent_name, 0)) == 1,
				"round %d: %s must act exactly once, got %d" % [round_index, agent_name, int(counts.get(agent_name, 0))])
	a.free(); b.free(); c.free()

## reset() = fresh episode: same queue, round 1, first agent active, log cleared.
func _check_reset_restarts_order() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var tc = TurnCoordinatorScript.new()
	tc.setup([a, b])
	tc.record_action_and_advance()
	tc.reset()
	_expect(tc.current_agent() == a, "after reset BotA must be active again")
	_expect(tc.current_round == 1, "after reset the round counter must be 1, got %d" % tc.current_round)
	_expect(tc.get_turn_log().is_empty(), "after reset the turn log must be empty")
	a.free(); b.free()

## A freed (fallen) bot's turn passes — current_agent() skips forward to
## the next alive bot; the freed one never appears in that round's log.
func _check_freed_agent_passes_turn() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var c := _agent("BotC")
	var tc = TurnCoordinatorScript.new()
	tc.setup([a, b, c])
	tc.record_action_and_advance()  # BotA acted, BotB is active
	b.free()
	_expect(tc.current_agent() == c, "a freed BotB must pass the turn to BotC")
	var entry: Dictionary = tc.record_action_and_advance()
	_expect(entry.get("agent", "") == "BotC", "the logged actor after BotB fell must be BotC")
	_expect(int(tc.turn_counts(1).get("BotB", 0)) == 0, "freed BotB must not appear in round 1's log")
	a.free(); c.free()

## The Sync integration: with turn_based_sequencing on, one decision step
## applies ONLY the active bot's action and advances the turn.
func _check_sync_gates_to_active_agent() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var c := _agent("BotC")
	var sync = NcnnSyncScript.new()
	sync.turn_based_sequencing = true
	_bind_training(sync, [a, b, c])
	sync._ensure_turn_coordinator()
	# Decision step 1: the trainer returns one action per agent slot; only BotA's applies.
	sync._set_agent_actions([10, 20, 30], sync.agents_training)
	_expect(a.applied == [10] and b.applied.is_empty() and c.applied.is_empty(),
		"step 1 must apply ONLY BotA's action (BotB/BotC must stay idle)")
	# Decision step 2: only BotB.
	sync._set_agent_actions([11, 21, 31], sync.agents_training)
	_expect(b.applied == [21] and a.applied.size() == 1 and c.applied.is_empty(),
		"step 2 must apply ONLY BotB's action")
	# Decision step 3: only BotC — round 1 complete, each bot exactly once.
	sync._set_agent_actions([12, 22, 32], sync.agents_training)
	_expect(c.applied == [32] and a.applied.size() == 1 and b.applied.size() == 1,
		"step 3 must apply ONLY BotC's action")
	# Decision step 4: back to BotA in round 2.
	sync._set_agent_actions([13, 23, 33], sync.agents_training)
	_expect(a.applied == [10, 13], "step 4 must wrap the turn back to BotA (round 2)")
	var counts: Dictionary = sync._turn_coordinator.turn_counts(1)
	_expect(counts.size() == 3 and int(counts.get("BotA", 0)) == 1
			and int(counts.get("BotB", 0)) == 1 and int(counts.get("BotC", 0)) == 1,
		"round 1 turn log must show each bot acting exactly once, got %s" % str(counts))
	sync.free()
	a.free(); b.free(); c.free()

## Default off: the stock batched loop applies EVERY agent's action every
## decision step (parallel single-bot environments like training_scene.tscn
## depend on this — the flag must not change them).
func _check_sync_stock_batch_unchanged() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var sync = NcnnSyncScript.new()
	sync._set_agent_actions([7, 8], [a, b])
	_expect(a.applied == [7] and b.applied == [8],
		"with sequencing OFF every agent's action must still apply (stock batch)")
	_expect(sync.get_current_turn_agent() == null,
		"with sequencing OFF there must be no active-turn agent")
	sync.free()
	a.free(); b.free()

## The trainer's "reset" message path (_reset_agents) restarts the turn
## order for the fresh episode.
func _check_sync_reset_restarts_turn_order() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var sync = NcnnSyncScript.new()
	sync.turn_based_sequencing = true
	_bind_training(sync, [a, b])
	sync._ensure_turn_coordinator()
	sync._set_agent_actions([1, 2], sync.agents_training)  # BotA acted
	sync._reset_agents()
	_expect(sync.get_current_turn_agent() == a,
		"after a trainer reset the turn order must restart at BotA")
	_expect(sync._turn_coordinator.current_round == 1,
		"after a trainer reset the round counter must be 1")
	_expect(a.needs_reset and b.needs_reset,
		"the stock reset behavior (needs_reset on every agent) must be preserved")
	sync.free()
	a.free(); b.free()

## DoD ordering half: the turn advances in the SAME step as the active
## bot's set_action() — so at the NEXT get_obs() collection the NEXT bot
## is already active and the world has ticked the applied action (the
## tree unpauses between decision steps). Assert: after a gated step, the
## Sync's current turn agent is the bot that did NOT just act.
func _check_turn_advances_before_next_obs() -> void:
	var a := _agent("BotA")
	var b := _agent("BotB")
	var sync = NcnnSyncScript.new()
	sync.turn_based_sequencing = true
	_bind_training(sync, [a, b])
	sync._ensure_turn_coordinator()
	sync._set_agent_actions([1, 2], sync.agents_training)  # BotA's step
	# This is the agent whose get_obs() the next decision step collects FIRST.
	_expect(sync.get_current_turn_agent() == b,
		"the turn must advance to BotB before the next obs collection")
	_expect(a.applied.size() == 1 and b.applied.is_empty(),
		"only the just-active BotA's action was applied in its step")
	sync.free()
	a.free(); b.free()

func _report() -> void:
	if failures.is_empty():
		print("ISSUE448 OK: one-agent-per-step turn sequencing — active-only action gating, turn advances before next obs, each bot exactly once per round in the turn log")
	else:
		for f in failures:
			print("ISSUE448 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
