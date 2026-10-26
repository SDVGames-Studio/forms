extends Node
## Issue #65: turn-based game flow for playable levels.
##
## Only active inside scenes carrying the "level" group (menus are never
## affected). When a level starts, a visual random generator rolls team
## colors and the winning color's team moves first. A turn gives the team
## TURN_TIME seconds to pick a character, move it and make ONE shot; firing
## ends the turn (after a short follow-up delay), as does the timer or the
## active character dying. The game runs until only one team is alive.

const TURN_TIME := 30.0
const AFTER_SHOT_DELAY := 1.5
const ROLL_STEPS := 10
const ROLL_STEP_TIME := 0.12

const TEAM_PLAYER := "player"
const TEAM_ENEMY := "enemy"
const TEAM_NAMES := {
	TEAM_PLAYER: "PLAYER TEAM",
	TEAM_ENEMY: "ENEMY TEAM",
}
## Body colors match the scene-authored team tints (issue #60).
const TEAM_COLORS := {
	TEAM_PLAYER: Color(1.0, 0.84, 0.2, 1.0),
	TEAM_ENEMY: Color(0.75, 0.2, 0.45, 1.0),
}

## Team whose turn it is ("" between turns / outside levels).
var active_team := ""
## Character currently allowed to move and shoot.
var active_member: Node2D = null
## True once one team eliminated the other.
var game_over := false

var _level: Node = null
var _turn_left := 0.0
## True while the post-shot delay runs — input is frozen.
var _switching := false
## Bumped on every shot; stale post-shot timers carry an old serial and
## are ignored so they can't cut a fresh turn short (issue #85).
var _shot_serial := 0
## Issue #85: stall watchdogs — if the first-team roll or the post-shot
## handover never completes (tween killed, timer lost, node freed
## mid-animation), the game force-recovers instead of freezing forever.
const ROLL_WATCHDOG := 3.0
const SWITCH_WATCHDOG := 5.0
var _roll_wait := 0.0
var _switch_wait := 0.0
## Issue #85 rework 2: seconds spent with no active team — if the roll
## stalls for any reason, the hard recovery in _process_watchdog fires.
var _stall_wait := 0.0
## Issue #104: once the active team member has moved or aimed during its
## turn, character switching (N/P) is locked until the turn ends.
var _switch_locked := false
var _layer: CanvasLayer
var _label: Label
var _hint_label: Label
var _roll_tween: Tween
## Issue #87: one-line hint of what the player should do right now.
const HINT_ROLL := "Rolling for the first team..."
const HINT_PLAYER := "Move: A/D or arrows • Jump: Space • Aim: W/S or Up/Down • Shoot: F • Character: N/P • Weapon: 1-4 • Skip turn: Tab"
const HINT_ENEMY := "Enemy turn — wait for your move..."
const HINT_SWITCH := "Shot fired — passing the turn..."


func _process(delta: float) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if level != _level:
		_level = level
		_on_level_changed()
	# Issue #85: stall watchdogs run even while switching / before the
	# first turn, so a lost tween or timer can never freeze the game.
	_process_watchdog(delta)
	if _level == null or game_over or _switching:
		return
	# The active character died mid-turn — hand over immediately.
	# queue_free()d members must be treated as dead too (issue #85).
	if active_member != null:
		var hp = active_member.get("health") if is_instance_valid(active_member) else 0
		if not (hp is int) or hp <= 0:
			_end_turn()
			return
	_turn_left = maxf(0.0, _turn_left - delta)
	_update_label()
	if _turn_left == 0.0:
		_end_turn()


func _unhandled_input(event: InputEvent) -> void:
	# Issue #102: Tab skips the current player turn. Only while the
	# player team is actually moving — never during the shot handover,
	# the enemy turn, the roll or after game over.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_TAB:
		if _level != null and not game_over and not _switching \
				and active_team == TEAM_PLAYER:
			get_viewport().set_input_as_handled()
			_end_turn()


## Issue #104: the active player member reports a move or aim action —
## from that moment character switching is locked until the turn ends.
func notify_member_action() -> void:
	if _level != null and not game_over and not _switching \
			and active_team == TEAM_PLAYER:
		_switch_locked = true


## Issue #104: true while N/P character switching is locked for the turn.
func is_switch_locked() -> bool:
	return _switch_locked and active_team == TEAM_PLAYER


## Weapon._fire reports every shot (player and NPC alike) — the shot ends
## the move, so after a short delay the turn passes to the other team.
func notify_shot() -> void:
	if _level == null or game_over or _switching or active_team == "":
		return
	_switching = true
	_shot_serial += 1
	_switch_wait = 0.0
	_update_label()
	get_tree().create_timer(AFTER_SHOT_DELAY).timeout.connect(
		_end_turn.bind(_shot_serial))


func _on_level_changed() -> void:
	if _level == null:
		# Back in a menu: drop the HUD and the state.
		if _layer != null:
			_layer.queue_free()
			_layer = null
			_label = null
			_hint_label = null
		active_team = ""
		active_member = null
		game_over = false
		_switching = false
		_shot_serial = 0
		_roll_wait = 0.0
		_switch_wait = 0.0
		_stall_wait = 0.0
		return
	_start_round()


func _start_round() -> void:
	game_over = false
	_switching = false
	# A fresh round must never inherit a wedged transition (issue #85).
	_stall_wait = 0.0
	active_team = ""
	active_member = null
	_build_ui()
	_roll_wait = 0.0
	# Visual random generator: the banner flickers between team colors,
	# then settles on a random team — that team moves first.
	# Kill any leftover roll tween before starting a new one (issue #85).
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	var roll := create_tween()
	_roll_tween = roll
	for i in ROLL_STEPS:
		var team := TEAM_PLAYER if i % 2 == 0 else TEAM_ENEMY
		roll.tween_callback(_show_roll.bind(team))
		roll.tween_interval(ROLL_STEP_TIME)
	roll.tween_callback(_finish_roll)


func _show_roll(team: String) -> void:
	# A stale roll tween (killed round, forced recovery) must never
	# overwrite an already started turn (issue #85 rework 2).
	if _label == null or active_team != "":
		return
	_label.text = "PICKING FIRST TEAM..."
	_label.add_theme_color_override("font_color", TEAM_COLORS[team])


func _process_watchdog(delta: float) -> void:
	if _level == null or game_over:
		return
	# HARD recovery: if no team is active and we are not passing a shot,
	# the first-team roll has stalled — force-clear everything and start
	# a turn. The recovery is not gated by any transition flag on purpose.
	if active_team == "" and not _switching:
		_stall_wait += delta
		if _stall_wait > ROLL_WATCHDOG:
			_stall_wait = 0.0
			_roll_wait = 0.0
			_switching = false
			_finish_roll()
			return
	else:
		_stall_wait = 0.0
	if _switching:
		# A shot handover must never outlive its delay (issue #85).
		_switch_wait += delta
		if _switch_wait > SWITCH_WATCHDOG:
			_switch_wait = 0.0
			_end_turn()
		return
	# Belt-and-braces roll fallback (kept from the first rework).
	if active_team == "":
		_roll_wait += delta
		if _roll_wait > ROLL_WATCHDOG:
			_roll_wait = 0.0
			_finish_roll()


func _finish_roll() -> void:
	# State-based guard: once a team is active the roll is done; guards can
	# the roll is done; the flag itself must never block recovery.
	if active_team != "" or _level == null or game_over:
		return
	_roll_wait = 0.0
	var first: String = [TEAM_PLAYER, TEAM_ENEMY].pick_random()
	# Note: no transition flag is held across the call — a runtime error
	# inside _begin_turn must never wedge the flow forever (issue #85).
	_begin_turn(first)


func _begin_turn(team: String) -> void:
	# Guards are state-based (active_team) — no transition flag that could
	# wedge and block the first turn forever (issue #85 reworks).
	if _level == null or game_over:
		return
	active_team = team
	_switching = false
	# Issue #104: a fresh turn always starts with switching unlocked.
	_switch_locked = false
	_turn_left = TURN_TIME
	var group := "player_team" if team == TEAM_PLAYER else "enemy_team"
	var members := _alive(group)
	if members.is_empty():
		_check_win()
		return
	# Issue #101: every member of the team starting its turn gets its
	# full shot quota back (per-weapon limits live in Weapon.gd).
	for member in members:
		var weapon: Node = member.get_node_or_null("Weapon")
		if weapon != null and weapon.has_method("reset_shots"):
			weapon.reset_shots()
	if team == TEAM_PLAYER:
		# The player keeps whichever character is currently controlled…
		for member in members:
			if member.get("controlled") == true:
				active_member = member
				break
	else:
		active_member = members.pick_random()
	if active_member == null:
		active_member = members[0]
		# …but if the controlled member died, hand control to a survivor,
		# otherwise the player team could never act again (issue #85).
		if team == TEAM_PLAYER and active_member.has_method("set_controlled"):
			active_member.set_controlled(true)
	_update_label()


func _end_turn(from_serial: int = -1) -> void:
	if _level == null or game_over or active_team == "":
		return
	# A stale post-shot timer must not cut a fresh turn short (issue #85).
	if from_serial != -1 and from_serial != _shot_serial:
		return
	_switch_wait = 0.0
	_switching = false
	_check_win()
	if not game_over:
		_begin_turn(TEAM_ENEMY if active_team == TEAM_PLAYER else TEAM_PLAYER)


func _alive(group: String) -> Array:
	var result: Array = []
	for member in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(member):
			continue
		var hp = member.get("health")
		if hp is int and hp > 0:
			result.append(member)
	return result


func _check_win() -> void:
	var players := _alive("player_team").size()
	var enemies := _alive("enemy_team").size()
	if players > 0 and enemies > 0:
		return
	game_over = true
	active_team = ""
	active_member = null
	if _label != null:
		var winner := TEAM_ENEMY if players == 0 else TEAM_PLAYER
		_label.text = "%s WINS!" % TEAM_NAMES[winner]
		_label.add_theme_color_override("font_color", TEAM_COLORS[winner])
	if _hint_label != null:
		_hint_label.text = ""


func _build_ui() -> void:
	if _layer != null:
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.offset_top = 8.0
	_label.offset_bottom = 40.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_layer.add_child(_label)
	_hint_label = Label.new()
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.offset_top = 40.0
	_hint_label.offset_bottom = 64.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_layer.add_child(_hint_label)
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	if active_team == "":
		if not game_over:
			_label.text = ""
			if _hint_label != null:
				_hint_label.text = HINT_ROLL
		return
	var team_name: String = TEAM_NAMES[active_team]
	_label.text = "%s — %d s" % [team_name, ceili(_turn_left)]
	_label.add_theme_color_override("font_color", TEAM_COLORS[active_team])
	_update_hint()


## Issue #87: context hint under the turn timer.
func _update_hint() -> void:
	if _hint_label == null:
		return
	if _switching:
		_hint_label.text = HINT_SWITCH
	elif active_team == TEAM_PLAYER:
		_hint_label.text = HINT_PLAYER
	else:
		_hint_label.text = HINT_ENEMY
