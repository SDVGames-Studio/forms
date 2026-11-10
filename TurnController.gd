extends Node
## Issue #65: turn-based game flow for playable levels.
##
## Only active inside scenes carrying the "level" group (menus are never
## affected). When a level starts, a visual random generator rolls team
## colors and the winning color's team moves first. A turn gives the team
## TURN_TIME seconds to pick a character, move it and make ONE shot;
## firing ends the turn (after a short follow-up delay), as does the timer
## or the active character dying. Issue #244: however the turn ends, the
## acting character is blocked first and the next turn begins only after
## every effect is done — flying projectiles AND explosions — even when
## the timer finished first. Issue #312: a TRIGGERED mine counts as a
## pending effect too — once armed, the handover waits until it has
## exploded before the next turn begins.
## Issue #413: that rule now holds for EVERY way a turn can end — a
## shot, the expired timer, a skip, or the acting character dying
## mid-turn — and a 30-second safety timer force-starts the next turn
## if an action accidentally never completes, logging the force-fire
## to the debug action log.
## The game runs until only one team is alive.
## Issue #434: every turn boundary is also a reward boundary — the acting
## member's agent controller (if any) is notified so the REWARD_SPEC
## §2.4/§2.5/§2.7/§2.8 components fire at the right moments.

const BotController := preload("res://BotController.gd")

## Issue #192: default fallback; the configured value lives in
## GameConfig.turn_time (level configuration menu).
const TURN_TIME := 15.0
const AFTER_SHOT_DELAY := 1.5
const ROLL_STEPS := 10
const ROLL_STEP_TIME := 0.12

const TEAM_PLAYER := "player"
const TEAM_ENEMY := "enemy"
const TEAM_NAMES := {
	TEAM_PLAYER: "YELLOW TEAM",
	TEAM_ENEMY: "PINK TEAM",
}
## Body colors match the scene-authored team tints (issue #60).
## FALLBACK ONLY — see _team_color(): the banner must use the
## scene-authored team_color of the actual figures (issue #167).
const TEAM_COLORS := {
	TEAM_PLAYER: Color(1.0, 0.84, 0.2, 1.0),
	TEAM_ENEMY: Color(0.75, 0.2, 0.45, 1.0),
}
## Issue #167: palette used to NAME a team from its scene-authored
## team_color — a level may tint its teams green/blue/red/…, and the
## banner must say that color, never a hard-coded one.
const COLOR_NAMES := [
	["YELLOW", Color(1.0, 0.84, 0.2)],
	["PINK", Color(0.75, 0.2, 0.45)],
	["GREEN", Color(0.22, 0.7, 0.3)],
	["BLUE", Color(0.2, 0.5, 0.95)],
	["RED", Color(0.85, 0.2, 0.2)],
	["PURPLE", Color(0.6, 0.25, 0.65)],
	["ORANGE", Color(0.9, 0.5, 0.15)],
	["CYAN", Color(0.2, 0.7, 0.95)],
]

## Team whose turn it is ("" between turns / outside levels).
var active_team := ""
## Character currently allowed to move and shoot.
var active_member: Node2D = null
## True once one team eliminated the other.
var game_over := false
## Issue #364: current ROUND — one full cycle through the turn order
## (every team acted once). From the second round on, one random item
## (first aid kit / weapon / tool bundle) may appear on a random SURFACE
## spot of the level at each round change (LevelItems.spawn_random_item).
## Issue #375: the round drop is a 25% roll now (was 100%).
var _round := 1
## Issue #375: the chance that a round beginning creates the round
## drop (LevelItems.spawn_random_item) — a quarter of the rounds,
## down from every round.
const ROUND_DROP_CHANCE := 0.25

var _level: Node = null
var _turn_left := 0.0
## Issue #191: multi-team turn order. A team id is "player" for the player
## team; when the level has exactly ONE AI team it keeps the legacy id
## "enemy", otherwise each AI team color gets its own "enemy:<color>" id.
## _turn_order is a shuffled set of ALL team ids: the first N turns (N =
## number of teams) visit every team once in random order, then the same
## order repeats cyclically — uniform, like Worms.
var _teams: Array[String] = []
var _color_to_id := {}
var _turn_order: Array[String] = []
var _turn_index := 0
## Issue #343: per-team member rotation — the member that acted a team's
## last turn is remembered (team id -> figure) so the team's NEXT turn
## begins with the NEXT member, never the same figure twice in a row.
var _last_active := {}
## True while the post-shot delay runs — input is frozen.
var _switching := false
## Bumped on every shot; stale post-shot timers carry an old serial and
## are ignored so they can't cut a fresh turn short (issue #85).
var _shot_serial := 0
## Issue #119: after a shot, the handover first waits the short post-shot
## delay, then keeps waiting until no projectile is alive — grenades with
## a 3 s fuse must land and explode before the next turn starts.
var _after_shot_left := 0.0
## Issue #244: the handover was started by the turn TIMER running out
## (not by a shot) — only used to pick the waiting hint text.
var _timer_wait := false
## Issue #119: projectile nodes register in this group while alive.
const PROJECTILE_GROUP := "projectiles"
## Issue #244: transient explosion EFFECT nodes (blast rings still
## fading) register in this group — the handover waits for them too.
const EFFECT_GROUP := "turn_effects"
## Issue #85: stall watchdogs — if the first-team roll or the post-shot
## handover never completes (tween killed, timer lost, node freed
## mid-animation), the game force-recovers instead of freezing forever.
const ROLL_WATCHDOG := 3.0
## Issue #413: the handover's SAFETY TIMER replaces the old 5 s switch
## watchdog — effects may legitimately run long (a high grenade lob, a
## burning mine, a slow rocket), so the force-recovery waits a full
## 30 s; if an action accidentally fails to complete by then, the next
## team's turn is force-started and the force-fire is written to the
## debug action log.
const EFFECTS_SAFETY_TIME := 30.0
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
## Issue #377: the reworked controls hint — a compact closable window
## at the center of the screen's left side; when closed only a
## backgroundless "controls" word remains and it reopens on click.
var _controls_panel: PanelContainer
var _controls_word: Button
var _controls_root: Control
var _controls_hidden := false
## Issue #87: one-line hint of what the player should do right now.
const HINT_ROLL := "Rolling for the first team..."
## Issue #377: the player-turn controls list moved from the one-line top
## hint into the closable left window — one list item per line.
const CONTROL_LINES: Array[String] = [
	"Move: A/D or arrows",
	"Jump: Space",
	"Aim: W/S or Up/Down",
	"Shoot: F",
	"Camera: C",
	"Tools: 5-8",
	"Switch figure: arm 5, then N/P",
	"Weapon: 1-4, 9 (mine), 0 (jackhammer — W/S)",
	"Skip turn: Tab",
]
const HINT_ENEMY := "Enemy turn — wait for your move..."
const HINT_SWITCH := "Shot fired — waiting for the projectiles..."
## Issue #244: the timer ran out — the turn is over, the character is
## blocked and the handover waits for every effect to finish.
const HINT_EFFECTS := "Turn over — waiting for the effects..."
## Issue #222: after a win the game keeps running — nobody may move, but
## the player keeps a live view to spectate the field with the camera.
const HINT_SPECTATE := "Game over — spectate: drag to pan, +/- to zoom"


func _process(delta: float) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if level != _level:
		_level = level
		_on_level_changed()
	# Issue #85: stall watchdogs run even while switching / before the
	# first turn, so a lost tween or timer can never freeze the game.
	_process_watchdog(delta)
	# Issue #335: idle characters muse a comics line — the active figure
	# standing around without any action speaks to itself (own guards
	# inside; resets outside levels and during the handover).
	CharacterLines.tick_idle(delta)
	# Issue #119: post-shot handover — wait for the short delay AND for
	# every projectile to explode before passing the turn.
	# Issue #244: the same handover now also serves an expired turn timer,
	# and it waits for every EFFECT — live projectiles (issue #119) plus
	# explosion rings still fading — so the next turn begins only after
	# the field is quiet, even when the timer finished first.
	if _switching and not game_over:
		_after_shot_left = maxf(0.0, _after_shot_left - delta)
		if _after_shot_left <= 0.0 and _pending_effects() == 0:
			_end_turn(_shot_serial)
			return
	if _level == null or game_over or _switching:
		return
	# The active character died mid-turn — hand over. Even a death must
	# not start the next turn while actions are still running (issue
	# #413): a mine the figure stepped on is burning, its own shot may
	# still be flying. queue_free()d members count as dead too (issue #85).
	if active_member != null:
		var hp = active_member.get("health") if is_instance_valid(active_member) else 0
		if not (hp is int) or hp <= 0:
			_hand_over()
			return
	_turn_left = maxf(0.0, _turn_left - delta)
	_update_label()
	if _turn_left == 0.0:
		# Issue #244: an expired timer no longer ends the turn at once —
		# the character is blocked first and the turn passes only after
		# every effect (flying projectiles, explosions) is done.
		_begin_effects_wait()


func _unhandled_input(event: InputEvent) -> void:
	# Issue #102: Tab skips the current player turn. Only while the
	# player team is actually moving — never during the shot handover,
	# the enemy turn, the roll or after game over.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_TAB:
		if _level != null and not game_over and not _switching \
				and active_team == TEAM_PLAYER:
			get_viewport().set_input_as_handled()
			# Issue #252: debug action log — the player gave the turn up.
			var skipper: Variant = "Player"
			if active_member != null and active_member.get("display_name") != null:
				skipper = active_member.get("display_name")
			DebugInfo.log("%s skips the turn" % str(skipper))
			# Issue #413: even a skip hands over through the effects wait —
			# never start the next turn on live actions.
			_hand_over()


## Issue #221: the AI analogue of the player's Tab skip (#102) — the
## currently ACTIVE member may end its own turn early once it has
## nothing useful left to do (out of options, or every intended action
## is done). Guards mirror _unhandled_input: never during a shot
## handover or a roll, never after the game ended, and only the acting
## member's own request ends its turn.
func skip_turn(requester: Node) -> void:
	if _level == null or game_over or _switching or active_team == "":
		return
	if requester == null or requester != active_member:
		return
	# Issue #413: the AI skip hands over through the effects wait too.
	_hand_over()


## Issue #104: the active player member reports a move or aim action —
## from that moment character switching is locked until the turn ends.
func notify_member_action() -> void:
	if _level != null and not game_over and not _switching \
			and active_team == TEAM_PLAYER:
		_switch_locked = true
		# Issue #306: a move/aim action commits a pending Switch-tool
		# character change — its use is spent now.
		ToolInventory.commit_switch()
		# Issue #335: an action restarts the active figure's idle musings.
		CharacterLines.note_action()


## Issue #104: true while N/P character switching is locked for the turn.
func is_switch_locked() -> bool:
	return _switch_locked and active_team == TEAM_PLAYER


## Weapon._fire reports every shot (player and NPC alike) — the shot ends
## the move, so after a short delay the turn passes to the other team.
func notify_shot() -> void:
	if _level == null or game_over or _switching or active_team == "":
		return
	# Issue #306: a shot commits a pending Switch-tool character change
	# — its use is spent now (switch, move, aim or shoot).
	ToolInventory.commit_switch()
	# Issue #335: a shot is an action — restart the idle musings.
	CharacterLines.note_action()
	_switching = true
	# Issue #131, reworked in #143: the weapon lock is per character and
	# applied by Weapon._fire — notify_shot no longer locks the inventory
	# globally.
	_timer_wait = false
	_shot_serial += 1
	_switch_wait = 0.0
	_after_shot_left = AFTER_SHOT_DELAY
	_update_label()


## Issue #244: the turn timer ran out — block the acting character and
## hand the turn over only after every effect (live projectiles,
## explosions) has finished. Mirrors the post-shot handover (issue #119):
## the shared _switching state freezes all character input while the
## effects resolve; the #413 safety timer still force-recovers a stuck wait.
func _begin_effects_wait() -> void:
	_switching = true
	_timer_wait = true
	_after_shot_left = 0.0
	_switch_wait = 0.0
	_update_label()


## Issue #413: end the turn NOW when nothing is running, or hand it
## over through the effects wait while actions are still live (a mine
## someone stepped on before skipping, a teleport gate mid-animation,
## the acting character's own last shot). Every turn-ending path that
## is not already a handover funnels through here, so the next team's
## turn NEVER starts on a field with unfinished actions.
func _hand_over() -> void:
	if _pending_effects() > 0:
		_begin_effects_wait()
	else:
		_end_turn()


## Issue #244: true while the handover blocks ALL character input —
## Player, NPC, weapon and tools ask before acting. Covers both the
## post-shot wait (issue #119) and the expired-timer wait.
func is_input_frozen() -> bool:
	return _switching


## Issue #244: everything the handover waits for — live projectiles
## (issue #119) AND live explosion effects (blast rings still fading).
## Issue #312: an ARMED mine is a live projectile again — a triggered
## mine re-joins the "projectiles" group until it has exploded, so the
## handover holds the turn change for its fuse.
func _pending_effects() -> int:
	var count := _live_projectiles()
	for node in get_tree().get_nodes_in_group(EFFECT_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


## Issue #119: projectiles still flying/exploding (queue_free()d ones don't
## count — they are already done for gameplay purposes).
func _live_projectiles() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(PROJECTILE_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func _on_level_changed() -> void:
	if _level == null:
		# Back in a menu: drop the HUD and the state.
		if _layer != null:
			_layer.queue_free()
			_layer = null
			_label = null
			_hint_label = null
		# Issue #377 rework: the controls hint dies with the HUD — null the
		# refs so visibility updates never touch a freed instance.
		_controls_root = null
		_controls_panel = null
		_controls_word = null
		active_team = ""
		active_member = null
		game_over = false
		_switching = false
		_shot_serial = 0
		_after_shot_left = 0.0
		_timer_wait = false
		_roll_wait = 0.0
		_switch_wait = 0.0
		_stall_wait = 0.0
		_round = 1
		_teams = []
		_color_to_id = {}
		_turn_order = []
		_last_active = {}
		return
	_start_round()


## Issue #191: the id of the team a figure belongs to.
func team_id_of(member: Node) -> String:
	if member.is_in_group("player_team"):
		return TEAM_PLAYER
	var c = member.get("team_color")
	return _color_to_id.get(c, TEAM_ENEMY)


## Issue #191: true when the id names the player-controlled team.
func is_player_team(id: String) -> bool:
	return id == TEAM_PLAYER


## Issue #191: collect distinct team ids from the figures present and
## build the shuffled turn order (first N turns = random set of all N
## teams, then that exact order repeats).
func _scan_teams() -> void:
	_teams = []
	_color_to_id = {}
	var enemy_colors: Array[Color] = []
	var seen := {}
	for member in _alive("enemy_team"):
		var c = member.get("team_color")
		if c is Color and not seen.has(c):
			seen[c] = true
			enemy_colors.append(c)
	var single := enemy_colors.size() == 1
	for c in enemy_colors:
		var id := TEAM_ENEMY if single else "enemy:%s" % c.to_html()
		_color_to_id[c] = id
		_teams.append(id)
	_teams.append(TEAM_PLAYER)
	_turn_order = _teams.duplicate()
	_turn_order.shuffle()
	_turn_index = 0


## Issue #191: alive figures of one team id (from both groups).
func _alive_of(id: String) -> Array:
	var result: Array = []
	for member in _alive("player_team") + _alive("enemy_team"):
		if team_id_of(member) == id:
			result.append(member)
	return result


## Issue #343: the member AFTER the one that acted this team's last turn
## (members = the team's alive figures in stable scene order). With no
## remembered member (the team's first turn) or a dead/freed one, the
## first alive member starts the cycle.
func _next_member(team: String, members: Array) -> Node:
	if members.is_empty():
		return null
	if is_player_team(team):
		# Only CONTROLLABLE figures rotate for the player team — AI allies
		# (Npc.gd) have no input to receive (issue #121).
		var controllable: Array = []
		for member in members:
			if member.has_method("set_controlled"):
				controllable.append(member)
		if not controllable.is_empty():
			members = controllable
	var last: Node = _last_active.get(team)
	var index := -1
	if last != null and is_instance_valid(last):
		index = members.find(last)
	return members[(index + 1) % members.size()]


## Issue #191: next team in the repeating order that still has figures.
func _next_alive_team() -> String:
	if _turn_order.is_empty():
		return TEAM_ENEMY if active_team == TEAM_PLAYER else TEAM_PLAYER
	var n := _turn_order.size()
	for step in range(1, n + 1):
		var index := (_turn_index + step) % n
		var id: String = _turn_order[index]
		if not _alive_of(id).is_empty():
			# Issue #364: wrapping past the end of the order = every team
			# acted once = a new ROUND began. From the second round on, one
			# random item may appear on a random surface spot of the level
			# — a 25% roll per round now (issue #375).
			if index <= _turn_index:
				_round += 1
				if _round >= 2 and randf() < ROUND_DROP_CHANCE:
					LevelItems.spawn_random_item(_level)
			_turn_index = index
			return id
	return ""


func _start_round() -> void:
	game_over = false
	_switching = false
	# A fresh round must never inherit a wedged transition (issue #85).
	_stall_wait = 0.0
	# Issue #364: a fresh game starts at round 1 — items drop from round 2.
	_round = 1
	active_team = ""
	active_member = null
	_build_ui()
	_roll_wait = 0.0
	# Issue #191: discover all teams and shuffle the turn order.
	_scan_teams()
	# Issue #343: fresh member rotation for the new round.
	_last_active = {}
	# Issue #305: fresh budgets — every team starts the round with 5 uses
	# of each weapon and each tool (the spear is infinite).
	WeaponInventory.reset_uses()
	# Visual random generator: the banner flickers between team colors,
	# then settles on a random team — that team moves first.
	# Kill any leftover roll tween before starting a new one (issue #85).
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	var roll := create_tween()
	_roll_tween = roll
	var fallback: Array[String] = _teams
	if fallback.is_empty():
		fallback = [TEAM_PLAYER, TEAM_ENEMY]
	for i in ROLL_STEPS:
		var team: String = fallback[i % fallback.size()]
		roll.tween_callback(_show_roll.bind(team))
		roll.tween_interval(ROLL_STEP_TIME)
	roll.tween_callback(_finish_roll)


func _show_roll(team: String) -> void:
	# A stale roll tween (killed round, forced recovery) must never
	# overwrite an already started turn (issue #85 rework 2) — nor the
	# win banner: game_over clears active_team, so without this guard a
	# roll callback racing the end of the game would eat the "WINS!"
	# banner (issue #222).
	if _label == null or active_team != "" or game_over:
		return
	_label.text = "PICKING FIRST TEAM..."
	_label.add_theme_color_override("font_color", _team_color(team))


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
		# Issue #413: the handover's SAFETY TIMER — effects may run long,
		# so the recovery window is 30 s (issue #85's force-recovery
		# kept, just patient). When it elapses the next turn is
		# force-started even with actions still pending, and the
		# force-fire goes to the debug action log.
		_switch_wait += delta
		if _switch_wait > EFFECTS_SAFETY_TIME:
			_switch_wait = 0.0
			DebugInfo.log("safety timer (%.0f s): forcing the next turn, %d action(s) still pending" % [EFFECTS_SAFETY_TIME, _pending_effects()])
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
	_turn_index = 0
	var first: String = _turn_order[0] if not _turn_order.is_empty() \
			else [TEAM_PLAYER, TEAM_ENEMY].pick_random()
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
	# Issue #244: a fresh turn clears the expired-timer wait state.
	_timer_wait = false
	# Issue #104: a fresh turn always starts with switching unlocked.
	_switch_locked = false
	var members := _alive_of(team)
	# Issue #446: each turn start refreshes the ACTING team's shared
	# blackboard — once per turn, never per physics frame. Allies are the
	# team's own alive figures; enemies are every OTHER team's alive
	# figures (in a multi-team death-match the other AI teams count as
	# enemies too, issue #228). The team's bots then read TeamBlackboard's
	# statics instead of querying the world themselves.
	var board_enemies: Array = []
	for figure in _alive("player_team") + _alive("enemy_team"):
		if team_id_of(figure) != team:
			board_enemies.append(figure)
	TeamBlackboard.update_team(team, members, board_enemies)
	# Issue #131 rework, per-character since #143: the lock must survive
	# the enemy turn — only the start of a fresh PLAYER turn re-enables
	# weapon selection (for every character).
	if is_player_team(team):
		WeaponInventory.unlock_all()
		# Issue #170: a fresh player turn refills the tool quota.
		ToolInventory.reset_turn()
	# Issue #170/#221: a fresh turn of a team ends every shield of that
	# team's members ("defends until its next turn begins") — NPCs raise
	# shields too now, so the clear can no longer be player-team only.
	for member in members:
		if member.has_method("set_shielded"):
			member.set_shielded(false)
	_turn_left = _turn_duration()
	# Issue #187: drop the previous turn's active member before picking.
	# Without this, an enemy NPC left in active_member from the enemy turn
	# makes the "no member is controlled" fallback below never fire, so a
	# player turn can start with NOBODY controlled (e.g. right after the
	# controlled character died) — the player can neither act nor switch.
	active_member = null
	if members.is_empty():
		_check_win()
		return
	# Issue #101: every member of the team starting its turn gets its
	# full shot quota back (per-weapon limits live in Weapon.gd).
	for member in members:
		var weapon: Node = member.get_node_or_null("Weapon")
		if weapon != null and weapon.has_method("reset_shots"):
			weapon.reset_shots()
	# Issue #343: teams ROTATE their members — each new turn of a team
	# begins with the member AFTER the one that acted last time, never the
	# same figure again (player and AI teams alike, like Worms).
	if is_player_team(team):
		var chosen: Node = _next_member(team, members)
		# TeamController hands the input over and keeps active_member in
		# sync (issue #183); the direct fallback covers teams whose only
		# survivors are AI allies nobody can control (issue #121).
		var group := get_tree().get_nodes_in_group("player_team")
		var index := group.find(chosen)
		if index != -1:
			TeamController.set_active_index(index)
		if active_member != chosen:
			active_member = chosen
	else:
		active_member = _next_member(team, members)
	if active_member == null:
		active_member = members[0]
		# …but if the controlled member died, hand control to a survivor,
		# otherwise the player team could never act again (issue #85).
		if team == TEAM_PLAYER and active_member.has_method("set_controlled"):
			active_member.set_controlled(true)
	_update_label()
	# Issue #252: debug action log — whose turn just began.
	var actor: Variant = team
	if active_member != null and active_member.get("display_name") != null:
		actor = active_member.get("display_name")
	DebugInfo.log("%s: %s's turn" % [_team_name(team), str(actor)])
	# Issue #434: REWARD_SPEC §2.4/§2.5 — the agent controller that plays
	# the acting member is notified its own turn started (survival credit
	# + shaping rebase). Human teams have no AGENT controller, so the
	# dispatch is a no-op for them.
	BotController.notify_own_turn_started(active_member)


func _end_turn(from_serial: int = -1) -> void:
	if _level == null or game_over or active_team == "":
		return
	# A stale post-shot timer must not cut a fresh turn short (issue #85).
	if from_serial != -1 and from_serial != _shot_serial:
		return
	# Issue #434: REWARD_SPEC §2.5/§2.7/§2.8 — the acting member's
	# controller closes the ended turn (shaped positioning remainder,
	# idle-command audit, danger-tile penalty) BEFORE _check_win() or the
	# next _begin_turn() could free or replace the member.
	BotController.notify_own_turn_ended(active_member)
	_switch_wait = 0.0
	_switching = false
	# Issue #343: remember who acted this team's turn (a mid-turn Switch
	# kept active_member current, issue #183) — the team's next turn
	# begins with the NEXT member.
	if active_member != null:
		_last_active[active_team] = active_member
	_check_win()
	if not game_over:
		# Issue #191: advance along the repeating multi-team order.
		var next := _next_alive_team()
		if next != "":
			_begin_turn(next)


func _alive(group: String) -> Array:
	var result: Array = []
	for member in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(member):
			continue
		var hp = member.get("health")
		if hp is int and hp > 0:
			result.append(member)
	return result


## Issue #167: the DISPLAYED team color is the scene-authored team_color
## of the team's first alive figure; the hard-coded constant is only a
## fallback when nobody is alive (or a figure has no team_color).
## Issue #192: turn time comes from the level configuration (GameConfig);
## fall back to the built-in default when it is unset or invalid.
func _turn_duration() -> float:
	var t: float = GameConfig.turn_time
	return TURN_TIME if t <= 0.0 else t

func _team_color(team: String) -> Color:
	for member in _alive("player_team") + _alive("enemy_team"):
		if team_id_of(member) == team:
			var c = member.get("team_color")
			if c is Color:
				return c
	return TEAM_COLORS.get(team, TEAM_COLORS[TEAM_ENEMY])


## Issue #167: the banner must name the team by the color its figures are
## actually painted with, not by a hard-coded level-independent name —
## a green team must never be announced as "PINK TEAM".
func _team_name(team: String) -> String:
	var c := _team_color(team)
	var best: String = TEAM_NAMES[team]
	var best_d := INF
	for entry in COLOR_NAMES:
		var pc: Color = entry[1]
		var d: float = pow(c.r - pc.r, 2.0) + pow(c.g - pc.g, 2.0) + pow(c.b - pc.b, 2.0)
		if d < best_d:
			best_d = d
			best = "%s TEAM" % entry[0]
	return best


func _check_win() -> void:
	# Issue #191: the game ends when at most one TEAM (by id) is alive.
	var alive_teams: Array[String] = []
	for id in _teams:
		if not _alive_of(id).is_empty():
			alive_teams.append(id)
	if alive_teams.size() > 1:
		return
	game_over = true
	active_team = ""
	active_member = null
	if _label != null:
		# Issue #151: mutual destruction is an explicit DRAW, not a phantom
		# winner for whichever team happens to be checked first.
		if alive_teams.is_empty():
			_label.text = "DRAW!"
			_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
		else:
			var winner: String = alive_teams[0]
			_label.text = "%s WINS!" % _team_name(winner)
			_label.add_theme_color_override("font_color", _team_color(winner))
	# Issue #437: the terminal game state ends the RL episode too — every
	# agent controller gets its REWARD_SPEC §2.9 outcome (+0.50 win when its
	# team is the sole survivor, −0.50 loss otherwise, draw included) and the
	# framework's game_over flags: done=true + needs_reset=true, truncated
	# stays false (a win/loss is never a timeout). The horizon path in the
	# controller core flags truncation with NO outcome reward, so a timeout
	# can never be confused with a victory.
	BotController.notify_episode_outcome(
			alive_teams[0] if alive_teams.size() == 1 else "")
	# Issue #222: the game must never block after the win — figures keep
	# idling but nobody may move, and the player keeps a live view to
	# spectate: the shared camera stays enabled even when the whole player
	# team died out (with nobody controlled it is the free spectator
	# camera of issue #126) and the hint says how to use it.
	for camera in get_tree().get_nodes_in_group("player_camera"):
		if is_instance_valid(camera):
			camera.enabled = true
	if _hint_label != null:
		_hint_label.text = HINT_SPECTATE
	_update_controls_visibility()


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
	_build_controls_panel()
	_update_label()


## Issue #377 rework: compact controls window at the center of the left
## side of the screen — a window with a 90% transparent white background,
## every item of the list on its own line, closed by a vector-drawn cross
## (no font glyph dependency) in its top left corner. While hidden, only
## the backgroundless word "controls" stays — pinned to the exact spot
## the cross occupied — and clicking it shows the window again. The window
## lives through every turn change (enemy turns included); only leaving
## the level rebuilds it, and the hidden/shown choice is never reset.
func _build_controls_panel() -> void:
	_controls_root = Control.new()
	_controls_root.name = "ControlsHintRoot"
	_controls_root.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_controls_root.grow_horizontal = Control.GROW_DIRECTION_END
	_controls_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_controls_root.offset_left = 12.0
	_controls_root.offset_right = 12.0
	_controls_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_controls_root)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.1)
	style.set_corner_radius_all(6.0)
	style.set_content_margin_all(10.0)
	_controls_panel = PanelContainer.new()
	_controls_panel.name = "ControlsPanel"
	_controls_panel.add_theme_stylebox_override("panel", style)
	_controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_root.add_child(_controls_panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	var close := CrossCloseButton.new()
	close.name = "CloseButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_on_controls_close_pressed)
	rows.add_child(close)
	for line in CONTROL_LINES:
		var row := Label.new()
		row.text = line
		row.add_theme_font_size_override("font_size", 12)
		row.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(row)
	_controls_panel.add_child(rows)
	# The root sits on the vertical center line; shift the window up by
	# half its height so the window's CENTER hugs the anchor point, the
	# same centered look the old grow-both layout had.
	var window_height := _controls_panel.get_minimum_size().y
	_controls_panel.position = Vector2(0.0, -window_height * 0.5)
	_controls_word = Button.new()
	_controls_word.name = "ControlsWord"
	_controls_word.text = "controls"
	_controls_word.flat = true
	_controls_word.focus_mode = Control.FOCUS_NONE
	_controls_word.add_theme_font_size_override("font_size", 12)
	_controls_word.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_controls_word.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1.0))
	_controls_word.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1.0))
	# Issue #377 rework: while hidden, the word sits exactly where the
	# cross button was — the top left corner of the window's content.
	_controls_word.position = Vector2(10.0, 8.0 - window_height * 0.5)
	_controls_word.size = _controls_word.get_minimum_size()
	_controls_word.pressed.connect(_on_controls_word_pressed)
	_controls_root.add_child(_controls_word)
	_update_controls_visibility()


## Issue #377 rework: the window and the "controls" word stay on screen
## through every turn change — the player's hidden/shown choice persists
## and the instance is only dropped when the level is left.
func _update_controls_visibility() -> void:
	if not is_instance_valid(_controls_panel) \
			or not is_instance_valid(_controls_word):
		return
	_controls_panel.visible = not _controls_hidden
	_controls_word.visible = _controls_hidden


func _on_controls_close_pressed() -> void:
	_controls_hidden = true
	_update_controls_visibility()


func _on_controls_word_pressed() -> void:
	_controls_hidden = false
	_update_controls_visibility()


func _update_label() -> void:
	if _label == null:
		return
	if active_team == "":
		if not game_over:
			_label.text = ""
			if _hint_label != null:
				_hint_label.text = HINT_ROLL
		_update_controls_visibility()
		return
	var team_name: String = _team_name(active_team)
	# Issue #165/#167: the banner names the team by its actual scene-
	# authored color and is painted in that team color.
	_label.text = "%s TURN — %d s" % [team_name, ceili(_turn_left)]
	_label.add_theme_color_override("font_color", _team_color(active_team))
	_update_hint()


## Issue #87: context hint under the turn timer.
func _update_hint() -> void:
	if _hint_label == null:
		return
	if _switching:
		# Issue #244: pick the hint for HOW the turn ended — a shot or the
		# expired timer; both block input while the effects resolve.
		_hint_label.text = HINT_EFFECTS if _timer_wait else HINT_SWITCH
	elif active_team == TEAM_PLAYER:
		# Issue #377: the controls list lives in the closable window on the
		# left — the one-line top hint stays empty during the player's turn.
		_hint_label.text = ""
	else:
		_hint_label.text = HINT_ENEMY
	_update_controls_visibility()


## Issue #377 rework: the close control of the controls window. The cross
## is DRAWN with two anti-aliased lines instead of a text glyph — the
## project font has no ✕ character, so the old text button rendered a
## placeholder box. Drawing it keeps the symbol identical everywhere.
class CrossCloseButton extends Button:
	var cross_color := Color(1.0, 1.0, 1.0, 0.75)
	var cross_color_hover := Color(1.0, 1.0, 1.0, 1.0)

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(18.0, 18.0)

	func _draw() -> void:
		var center := size * 0.5
		var arm: float = maxf(minf(size.x, size.y) * 0.5 - 2.0, 3.0)
		var color := cross_color_hover if is_hovered() else cross_color
		var width := 2.0
		draw_line(center - Vector2(arm, arm), center + Vector2(arm, arm),
			color, width, true)
		draw_line(center - Vector2(arm, -arm), center + Vector2(arm, -arm),
			color, width, true)
