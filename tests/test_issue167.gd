extends Node
## Regression test for issue #167: the turn banner must name the team by
## the color its figures are ACTUALLY painted with. A team tinted green
## in the scene must be announced "GREEN TEAM", never the hard-coded
## "PINK TEAM" / "YELLOW TEAM".
##
## Run headless: godot --headless res://tests/test_issue167.tscn
## Exit code 0 = pass.

const TurnControllerScript := preload("res://TurnController.gd")


func _ready() -> void:
	var ok := true
	ok = await _check_team_color_from_scene() and ok
	ok = await _check_team_name_matches_color() and ok
	ok = await _check_fallback_without_members() and ok
	print("ISSUE167 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


var _figs: Array = []


func _cleanup(ctrl: Node) -> void:
	ctrl.queue_free()
	for fig in _figs:
		fig.queue_free()
	_figs.clear()
	await get_tree().process_frame


func _make_controller() -> Node:
	var ctrl: Node = TurnControllerScript.new()
	add_child(ctrl)
	return ctrl


func _make_figure(script_path: String, group: String, color: Color) -> CharacterBody2D:
	var fig: CharacterBody2D = load(script_path).new()
	fig.team_color = color
	fig.add_to_group(group)
	add_child(fig)
	_figs.append(fig)
	return fig


## _team_color must return the scene-authored team_color of an alive
## member, not the hard-coded constant.
func _check_team_color_from_scene() -> bool:
	var ctrl := _make_controller()
	var green := Color(0.2, 0.8, 0.25, 1.0)
	_make_figure("res://Npc.gd", "enemy_team", green)
	var got: Color = ctrl._team_color(ctrl.TEAM_ENEMY)
	var ok: bool = got.is_equal_approx(green)
	print("ISSUE167 team_color scene: got=", got, " ok=", ok)
	await _cleanup(ctrl)
	return ok


## A green-tinted enemy team must be named GREEN TEAM (issue #167).
func _check_team_name_matches_color() -> bool:
	var ctrl := _make_controller()
	_make_figure("res://Npc.gd", "enemy_team", Color(0.2, 0.8, 0.25, 1.0))
	_make_figure("res://Player.gd", "player_team", Color(0.2, 0.4, 0.9, 1.0))
	var enemy_name: String = ctrl._team_name(ctrl.TEAM_ENEMY)
	var player_name: String = ctrl._team_name(ctrl.TEAM_PLAYER)
	var ok: bool = enemy_name == "GREEN TEAM" and player_name == "BLUE TEAM"
	print("ISSUE167 names: enemy=", enemy_name, " player=", player_name, " ok=", ok)
	await _cleanup(ctrl)
	return ok


## With no alive members the hard-coded fallbacks still apply.
func _check_fallback_without_members() -> bool:
	var ctrl := _make_controller()
	var ok: bool = ctrl._team_color(ctrl.TEAM_ENEMY).is_equal_approx(ctrl.TEAM_COLORS[ctrl.TEAM_ENEMY]) \
		and ctrl._team_name(ctrl.TEAM_PLAYER) == "YELLOW TEAM"
	print("ISSUE167 fallback ok=", ok)
	await _cleanup(ctrl)
	return ok