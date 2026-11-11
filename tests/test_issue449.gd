extends Node
## Regression check for issue #449: the shared focus target is assigned by
## the focus-fire heuristic — RE-RUN once per team turn inside
## TeamBlackboard.update_team() — and the whole team converges on it:
## every allied Npc aims at the same (heuristic-selected) enemy even when
## another enemy stands closer, and every allied BotController's team
## observation block reports that same target. Pins the issue's
## Definition of Done:
##   1. each team turn produces a focus target stored on the blackboard
##      (and re-assigns it once it dies),
##   2. the target is visible in every allied bot's observation,
##   3. a scripted scenario confirms multiple bots direct attacks at the
##      same enemy the heuristic selects.
## Heuristic pins: the HP term outranks proximity (a ≤ ~33%-HP enemy
## beats a full-HP enemy at the team's feet), proximity decides at even
## HP, and equal scores fall to the deterministic scene-name tie-break.
##
## Run headless: godot --headless res://tests/test_issue449.tscn
## Exit code 0 = pass.

const Npc := preload("res://Npc.gd")
const BotControllerScript := preload("res://BotController.gd")

# Observation conventions shared with test_issue447 (OBSERVATION_SPEC.md
# values, copied — not read from BotController — so drift fails here too).
const SPEC_HALF_W := 576.0        # focus_x divisor (arena half width)
const SPEC_HALF_H := 376.0        # focus_y divisor (arena half height)
const SPEC_TEAM_START := 46       # team block: [focus_x, focus_y, hp, ratio]
const SPEC_SIZE := 50

## Minimal figure stand-in: alive, teamable, positionable (the same
## convention as tests/test_issue446.gd — HP and position are all the
## heuristic may observe).
class FakeFigure extends Node2D:
	var health := 100

	var side := "player"

	func _ready() -> void:
		add_to_group("player_team" if side == "player" else "enemy_team")

var failures := 0
var npc_a: CharacterBody2D
var npc_b: CharacterBody2D
var healthy_near: FakeFigure
var wounded_far: FakeFigure
var bot_a: Node2D
var bot_b: Node2D

func _ready() -> void:
	await get_tree().process_frame
	TeamBlackboard.reset_blackboard()
	_setup()
	_check_heuristic_picks_focus()
	_check_proximity_at_even_hp()
	_check_name_tiebreak()
	_check_coordinated_fire_and_observation()
	_check_refocus_after_death()
	_report()

## The scripted battlefield: the allied team is two enemy-side Npcs at
## (0,0)/(100,0) (ally centroid (50,0)) with a BotController bound to each;
## the opposing side is a FULL-HP enemy at (200,0) and a 15-HP enemy at
## (500,0). Distances to the centroid: 150 vs 450.
func _setup() -> void:
	npc_a = Npc.new()
	add_child(npc_a)  # default team "enemy" -> group "enemy_team"
	npc_b = Npc.new()
	npc_b.position = Vector2(100.0, 0.0)
	add_child(npc_b)
	healthy_near = _figure("HealthyNear", Vector2(200.0, 0.0))
	wounded_far = _figure("WoundedFar", Vector2(500.0, 0.0))
	wounded_far.health = 15
	bot_a = _bot_bound_to(npc_a)
	bot_b = _bot_bound_to(npc_b)

func _figure(fig_name: String, at: Vector2) -> FakeFigure:
	var fig := FakeFigure.new()
	fig.name = fig_name
	fig.side = "player"
	add_child(fig)
	fig.position = at
	return fig

func _bot_bound_to(figure: Node2D) -> Node2D:
	var bot := Node2D.new()
	bot.set_script(BotControllerScript)
	add_child(bot)
	bot.position = figure.position
	bot.figure_path = bot.get_path_to(figure)
	return bot

func _update_board() -> void:
	# The exact per-team-turn refresh TurnController._begin_turn performs
	# (issue #446): allies = the team's own figures, enemies = everyone
	# else's, once per call — never per frame.
	TeamBlackboard.update_team("enemy", [npc_a, npc_b], [healthy_near, wounded_far])

## DoD 1: every team turn produces a focus target; the heuristic's HP
## term (0.6 × 0.85 = 0.51 for the 15-HP enemy) outranks the proximity
## term (0.4 × 1.0 = 0.4 for the nearest, full-HP one), and identical
## turns deterministically repeat the pick.
func _check_heuristic_picks_focus() -> void:
	_update_board()
	_expect(TeamBlackboard.get_focus_target("enemy") == wounded_far,
			"focus = the 15-HP far enemy (HP term beats proximity), got %s"
					% TeamBlackboard.get_focus_target("enemy"))
	_update_board()  # the next turn: same inputs, same deterministic pick
	_expect(TeamBlackboard.get_focus_target("enemy") == wounded_far,
			"identical turn inputs deterministically re-pick the same focus")

## At even HP the proximity term decides — the enemy nearest the ally
## centroid ("the key position") becomes the focus.
func _check_proximity_at_even_hp() -> void:
	var saved := wounded_far.health
	wounded_far.health = 100
	_update_board()
	_expect(TeamBlackboard.get_focus_target("enemy") == healthy_near,
			"at even HP the nearest-to-centroid enemy is focused")
	wounded_far.health = saved
	_update_board()
	_expect(TeamBlackboard.get_focus_target("enemy") == wounded_far,
			"restored HP restores the wounded focus")

## Equal score (same HP, same distance) falls to the deterministic
## scene-name tie-break — the whole team still gets exactly ONE target.
func _check_name_tiebreak() -> void:
	var zeta := _figure("Zeta", Vector2(300.0, 0.0))
	var alpha := _figure("Alpha", Vector2(300.0, 0.0))
	TeamBlackboard.update_team("enemy", [npc_a], [zeta, alpha])
	_expect(TeamBlackboard.get_focus_target("enemy") == alpha,
			"score tie resolves to the lexicographically smaller name")
	zeta.queue_free()
	alpha.queue_free()

## DoD 2 + DoD 3: every allied bot's observation carries the same focus
## target, and multiple bots direct their attacks at it — both Npcs pick
## the heuristic's wounded enemy over their OWN nearest opponent, because
## Npc._nearest_opponent() prefers the team's shared focus target.
func _check_coordinated_fire_and_observation() -> void:
	_update_board()
	_expect(npc_a._nearest_opponent() == wounded_far
			and npc_b._nearest_opponent() == wounded_far,
			"both allied bots attack the same heuristic-selected enemy")
	var team_a := _team_block(bot_a)
	var team_b := _team_block(bot_b)
	var expect_a := Vector2(
			clampf((500.0 - 0.0) / SPEC_HALF_W, -1.0, 1.0),
			clampf((0.0 - 0.0) / SPEC_HALF_H, -1.0, 1.0))
	var expect_b := Vector2(
			clampf((500.0 - 100.0) / SPEC_HALF_W, -1.0, 1.0),
			clampf((0.0 - 0.0) / SPEC_HALF_H, -1.0, 1.0))
	_expect(is_equal_approx(team_a[0], expect_a.x)
			and is_equal_approx(team_a[1], expect_a.y),
			"bot A's team block reports the shared focus target")
	_expect(is_equal_approx(team_b[0], expect_b.x)
			and is_equal_approx(team_b[1], expect_b.y),
			"bot B's team block reports the shared focus target")

## DoD 1's turnover half: the focused enemy dies — the next team turn's
## update re-assigns the focus (no corpse retention), the whole team
## switches its attacks to the new target together, and the observations
## follow.
func _check_refocus_after_death() -> void:
	wounded_far.health = 0
	_update_board()
	_expect(TeamBlackboard.get_focus_target("enemy") == healthy_near,
			"a dead focus target is re-assigned next turn")
	_expect(TeamBlackboard.get_living_enemies("enemy") == 1,
			"the corpse is not counted as a living enemy")
	_expect(npc_a._nearest_opponent() == healthy_near
			and npc_b._nearest_opponent() == healthy_near,
			"both bots switch attacks to the new shared target")
	var team_a := _team_block(bot_a)
	var expect_a := Vector2(
			clampf((200.0 - 0.0) / SPEC_HALF_W, -1.0, 1.0), 0.0)
	_expect(is_equal_approx(team_a[0], expect_a.x)
			and is_equal_approx(team_a[1], expect_a.y),
			"bot A's team block follows the re-assigned focus")

func _team_block(bot: Node2D) -> Array:
	var obs: Array = bot.get_obs()["obs"]
	_expect(obs.size() == SPEC_SIZE,
			"observation stays %d floats, got %s" % [SPEC_SIZE, obs.size()])
	return obs.slice(SPEC_TEAM_START, SPEC_TEAM_START + 2)

func _report() -> void:
	var ok := failures == 0
	print("ISSUE449 ok=", ok)
	get_tree().quit(1 if not ok else 0)

func _expect(cond: bool, what: String) -> bool:
	if not cond:
		failures += 1
		print("FAIL ", what)
	return cond
