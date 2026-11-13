extends RefCounted
## Issue #448: one-agent-per-step turn sequencing for turn-based training
## scenes.
##
## The default NcnnSync step is a BATCH: it collects get_obs() from every
## agent in agents_training, ships them to the Python server, and applies
## the returned actions to every agent at once — the standard parallel
## godot_rl loop. A TURN-BASED game needs one actor per decision step:
## this coordinator keeps the explicit turn queue the issue asks for and
## exposes current_agent() — the only bot whose set_action() the Sync
## applies. record_action_and_advance() is called by the Sync in the SAME
## step as the active bot's set_action(), so the turn advances BEFORE the
## next get_obs() batch: the tree is unpaused in between and the world
## ticks action_repeat physics frames with the applied action, so no bot
## ever observes a state its predecessor's action has not updated.
##
## One entry per applied turn lands in the turn log; a ROUND is one full
## cycle through the queue (every bot acted once — Worms round
## semantics), and every log entry carries {round, slot, agent} so
## "each bot acting exactly once per round" is verifiable from the log
## (tests/test_issue448.gd pins it).
##
## Pure logic (RefCounted, no scene): NcnnSync owns and drives it; nothing
## here touches the tree, the socket, or the paused state.

## Stable turn order — agents_training in tree order at setup() time.
var _queue: Array = []
## Index in _queue of the agent whose turn it is right now.
var _index := 0
## One full cycle through the queue = one round (starts at 1).
var current_round := 1
## One {round: int, slot: int, agent: String} per APPLIED turn, oldest
## first. The agent is snapshotted as a NAME at log time, so the log
## stays readable even after a figure is freed mid-episode.
var _log: Array[Dictionary] = []

## (Re)build the turn order over `agents` (stable input order, the first
## agent acts first) and clear the round counter and the log. Called at
## episode start, and by NcnnSync._reset_agents() for a fresh episode.
func setup(agents: Array) -> void:
	_queue = agents.duplicate()
	_index = 0
	current_round = 1
	_log.clear()

## The agent whose turn it is — the only controller the Sync lets act.
## Null when the queue is empty or every agent was freed mid-episode.
## Freed agents are skipped forward: a dead bot's turn passes, the next
## alive bot plays.
func current_agent() -> Node:
	if not _skip_freed_forward():
		return null
	return _queue[_index]

## Log the just-applied turn of the current agent, then advance to the
## next agent; wrapping past the end of the queue starts a new round.
## Returns the log entry, or {} when nobody could act (empty/dead queue).
func record_action_and_advance() -> Dictionary:
	if not _skip_freed_forward():
		return {}
	var actor: Node = _queue[_index]
	var entry := {"round": current_round, "slot": _index, "agent": str(actor.name)}
	_log.append(entry)
	_index = (_index + 1) % _queue.size()
	if _index == 0:
		current_round += 1
	return entry

## The structured turn log — one entry per applied turn, oldest first.
## This is the issue's "turn log": it shows each bot acting exactly once
## per round when the sequencing is healthy.
func get_turn_log() -> Array[Dictionary]:
	return _log

## Agent-name counts within one round — the Definition-of-Done check
## reads this (every alive bot exactly 1). Freed agents simply do not
## appear in the round they missed.
func turn_counts(target_round: int) -> Dictionary:
	var counts := {}
	for entry in _log:
		if entry["round"] == target_round:
			var key: String = entry["agent"]
			counts[key] = int(counts.get(key, 0)) + 1
	return counts

## Fresh episode: same queue, round 1, first agent to act, empty log.
func reset() -> void:
	setup(_queue)

## Park _index on the next still-valid agent. Returns false when the
## queue is empty or every entry was freed (nobody can act).
func _skip_freed_forward() -> bool:
	if _queue.is_empty():
		return false
	var n := _queue.size()
	for step in n:
		var idx := (_index + step) % n
		if is_instance_valid(_queue[idx]):
			_index = idx
			return true
	return false
