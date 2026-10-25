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
var _layer: CanvasLayer
var _label: Label


func _process(delta: float) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if level != _level:
		_level = level
		_on_level_changed()
	if _level == null or game_over or _switching:
		return
	# The active character died mid-turn — hand over immediately.
	if active_member != null:
		var hp = active_member.get("health")
		if not (hp is int) or hp <= 0:
			_end_turn()
			return
	_turn_left = maxf(0.0, _turn_left - delta)
	_update_label()
	if _turn_left == 0.0:
		_end_turn()


## Weapon._fire reports every shot (player and NPC alike) — the shot ends
## the move, so after a short delay the turn passes to the other team.
func notify_shot() -> void:
	if _level == null or game_over or _switching or active_team == "":
		return
	_switching = true
	_update_label()
	get_tree().create_timer(AFTER_SHOT_DELAY).timeout.connect(_end_turn)


func _on_level_changed() -> void:
	if _level == null:
		# Back in a menu: drop the HUD and the state.
		if _layer != null:
			_layer.queue_free()
			_layer = null
			_label = null
		active_team = ""
		active_member = null
		game_over = false
		_switching = false
		return
	_start_round()


func _start_round() -> void:
	game_over = false
	_switching = false
	active_team = ""
	active_member = null
	_build_ui()
	# Visual random generator: the banner flickers between team colors,
	# then settles on a random team — that team moves first.
	var roll := create_tween()
	for i in ROLL_STEPS:
		var team := TEAM_PLAYER if i % 2 == 0 else TEAM_ENEMY
		roll.tween_callback(_show_roll.bind(team))
		roll.tween_interval(ROLL_STEP_TIME)
	roll.tween_callback(_finish_roll)


func _show_roll(team: String) -> void:
	if _label == null:
		return
	_label.text = "PICKING FIRST TEAM..."
	_label.add_theme_color_override("font_color", TEAM_COLORS[team])


func _finish_roll() -> void:
	var first: String = [TEAM_PLAYER, TEAM_ENEMY].pick_random()
	_begin_turn(first)


func _begin_turn(team: String) -> void:
	if _level == null or game_over:
		return
	active_team = team
	_switching = false
	_turn_left = TURN_TIME
	var group := "player_team" if team == TEAM_PLAYER else "enemy_team"
	var members := _alive(group)
	if members.is_empty():
		_check_win()
		return
	if team == TEAM_PLAYER:
		# The player keeps whichever character is currently controlled.
		for member in members:
			if member.get("controlled") == true:
				active_member = member
				break
	else:
		active_member = members.pick_random()
	if active_member == null:
		active_member = members[0]
	_update_label()


func _end_turn() -> void:
	if _level == null or game_over:
		return
	_switching = false
	_check_win()
	if game_over:
		return
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
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	if active_team == "":
		if not game_over:
			_label.text = ""
		return
	var team_name: String = TEAM_NAMES[active_team]
	_label.text = "%s — %d s" % [team_name, ceili(_turn_left)]
	_label.add_theme_color_override("font_color", TEAM_COLORS[active_team])
