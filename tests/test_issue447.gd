extends Node
## Regression check for issue #447: the battlefield observation vector
## carries a trailing TEAM block (indices 46-49) sourced from the
## TeamBlackboard (issue #446) — the shared focus target's relative
## position in the agent's local frame, the team-average HP fraction,
## and the living ally-to-enemy ratio. Pins the issue's Definition of
## Done: the total dimension is 50, and the team fields CHANGE when the
## focus target changes or the team HP changes.
##
## Run headless: godot --headless res://tests/test_issue447.tscn
## Exit code 0 = pass.

const BotControllerScript := preload("res://BotController.gd")

# OBSERVATION_SPEC.md constants, copied from the spec table — NOT from
# BotController.gd — so the test fails if either side drifts.
const SPEC_HALF_W := 576.0        # focus_x divisor (arena half width)
const SPEC_HALF_H := 376.0        # focus_y divisor (arena half height)
const SPEC_MAX_HP := 100.0        # team_hp divisor
const SPEC_SIZE := 50             # 4 + 4*5 + 4*5 + 2 + 4 (team block)

## Minimal figure stand-in: alive, teamable, positionable. Carries the
## `shielded` flag like every real figure (Player/Npc) — BotController's
## own-vitals slot bool()-converts it, and a missing property would abort
## that block (velocity/cooldown properties stay absent: those getters
## duck-type null to zero).
class FakeFigure extends Node2D:
	var health := 100
	var shielded := false
	var side := "enemy"

	func _ready() -> void:
		add_to_group("player_team" if side == "player" else "enemy_team")

var failures: Array[String] = []
var bot: Node2D
var me: FakeFigure
var ally: FakeFigure
var enemy_a: FakeFigure
var enemy_b: FakeFigure
var enemy_c: FakeFigure
var enemy_d: FakeFigure

func _ready() -> void:
	await get_tree().process_frame
	TeamBlackboard.reset_blackboard()
	_setup()
	_check_dimension_and_empty_board()
	_check_team_block_values()
	_check_focus_change_moves_fields()
	_check_hp_change_moves_field()
	_check_ratio_change()
	_check_no_figure_fallback()
	_report()

func _setup() -> void:
	me = _figure("player", Vector2(400, 400))
	me.health = 80
	ally = _figure("player", Vector2(600, 480))
	ally.health = 60
	enemy_a = _figure("enemy", Vector2(700, 400))
	enemy_b = _figure("enemy", Vector2(1200, 300))
	enemy_c = _figure("enemy", Vector2(1300, 400))
	enemy_d = _figure("enemy", Vector2(1400, 500))
	bot = Node2D.new()
	bot.set_script(BotControllerScript)
	add_child(bot)
	bot.position = Vector2(400, 400)
	bot.figure_path = bot.get_path_to(me)

func _figure(side: String, at: Vector2) -> FakeFigure:
	var fig := FakeFigure.new()
	fig.side = side
	add_child(fig)
	fig.position = at
	return fig

func _obs() -> Array:
	return bot.get_obs()["obs"]

func _expect(value, expected: float, label: String) -> void:
	if not is_equal_approx(float(value), expected):
		failures.append("%s must be %s, got %s" % [label, str(expected), str(value)])

## The flat vector is 50 floats, all GDScript floats, and an EMPTY board
## (episode start, before the first turn refresh) reads the documented
## neutral team block [0, 0, 0, 0.5] while a figure is still bound.
func _check_dimension_and_empty_board() -> void:
	var flat := _obs()
	if flat.size() != SPEC_SIZE:
		failures.append("flat obs must hold %d floats, got %d" % [SPEC_SIZE, flat.size()])
		return
	for i in flat.size():
		if typeof(flat[i]) != TYPE_FLOAT:
			failures.append("obs[%d] must be a float, got %s" % [i, type_string(typeof(flat[i]))])
	_expect(flat[46], 0.0, "empty board focus_x")
	_expect(flat[47], 0.0, "empty board focus_y")
	_expect(flat[48], 0.0, "empty board team_hp")
	_expect(flat[49], 0.5, "empty board ally_enemy_ratio")

## Board refreshed for the acting team (exactly what TurnController does
## once per turn): focus = the living enemy nearest the ally centroid
## (enemy_a), team_hp = avg(80, 60)/100, ratio = 2 allies / (2+2).
func _check_team_block_values() -> void:
	TeamBlackboard.update_team("player", [me, ally], [enemy_a, enemy_b])
	var flat := _obs()
	# Ally centroid is (500, 440): enemy_a (700, 400) is nearer than
	# enemy_b (1200, 300), so the team focuses enemy_a — 300 px straight
	# ahead of me (rotation 0: local frame = world frame).
	_expect(flat[46], 300.0 / SPEC_HALF_W, "team focus_x = 300/576")
	_expect(flat[47], 0.0 / SPEC_HALF_H, "team focus_y = 0")
	_expect(flat[48], (80.0 + 60.0) / 2.0 / SPEC_MAX_HP, "team_hp = avg(80,60)/100")
	_expect(flat[49], 2.0 / 4.0, "ally ratio = 2/(2+2)")

## DoD: the team fields CHANGE when the focus target changes — enemy_a
## dies, the board reassigns the focus to enemy_b (far right and above),
## and the focus slots move to the new offset (x saturates the clamp).
func _check_focus_change_moves_fields() -> void:
	var before := _obs()
	enemy_a.health = -1
	TeamBlackboard.update_team("player", [me, ally], [enemy_b])
	var flat := _obs()
	if is_equal_approx(float(flat[46]), float(before[46])) \
			and is_equal_approx(float(flat[47]), float(before[47])):
		failures.append("focus slots must CHANGE when the focus target changes")
	_expect(flat[46], 1.0, "new focus_x clamps to 1.0 (800/576)")
	_expect(flat[47], -100.0 / SPEC_HALF_H, "new focus_y = -100/376")

## DoD: the team fields CHANGE when the team HP changes — the ally drops
## to 20 HP and the team-average fraction follows avg(80,20)/100 = 0.5.
func _check_hp_change_moves_field() -> void:
	var before := _obs()
	ally.health = 20
	TeamBlackboard.update_team("player", [me, ally], [enemy_b])
	var flat := _obs()
	if is_equal_approx(float(flat[48]), float(before[48])):
		failures.append("team_hp must CHANGE when the team HP changes")
	_expect(flat[48], (80.0 + 20.0) / 2.0 / SPEC_MAX_HP, "team_hp = avg(80,20)/100")

## The ratio tracks the living counts: 1 ally vs 3 enemies -> 0.25.
func _check_ratio_change() -> void:
	ally.health = -1
	TeamBlackboard.update_team("player", [me], [enemy_b, enemy_c, enemy_d])
	var flat := _obs()
	_expect(flat[49], 1.0 / 4.0, "ally ratio = 1/(1+3) after the ally dies")

## Every figure gone: the whole vector stays well-formed (50 floats) and
## the team block falls back to the documented neutral [0, 0, 1, 0.5].
func _check_no_figure_fallback() -> void:
	for fig in [me, ally, enemy_a, enemy_b, enemy_c, enemy_d]:
		fig.free()
	var flat := _obs()
	if flat.size() != SPEC_SIZE:
		failures.append("no-figure fallback must keep %d floats, got %d" % [SPEC_SIZE, flat.size()])
		return
	_expect(flat[0], 1.0, "no-figure fallback own hp_frac")
	_expect(flat[46], 0.0, "no-figure fallback focus_x")
	_expect(flat[47], 0.0, "no-figure fallback focus_y")
	_expect(flat[48], 1.0, "no-figure fallback team_hp")
	_expect(flat[49], 0.5, "no-figure fallback ally ratio")

func _report() -> void:
	if failures.is_empty():
		print("ISSUE447 OK: 50-float vector with blackboard team block; focus/HP/ratio fields track the board and change with it")
	else:
		for f in failures:
			print("ISSUE447 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
