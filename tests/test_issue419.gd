extends Node
## Regression check for issue #419: BotController.get_obs() must express
## every positional and velocity observation in the agent's LOCAL frame
## (local +X = the figure's facing direction). An enemy straight ahead
## reports rel_x > 0 at ANY agent rotation, velocities rotate with the
## frame, the whole observation is invariant to a uniform battlefield
## rotation, and rotation 0 keeps the world-frame numbers of issue #381.
## The flat 50-float layout never changes (issue #447 appended the
## trailing team block).
##
## Run headless: godot --headless res://tests/test_issue419.tscn
## Exit code 0 = pass.

const BotControllerScript := preload("res://BotController.gd")

# Layout mirrors BotController.gd (issue #381 + #447):
# 4 + 4*5 + 4*5 + 2 + 4 = 50.
const EXPECTED_SIZE := 50
const NORM_HALF_W := 576.0
const VEL_NORM := 320.0

class StubFigure extends CharacterBody2D:
	var health := 100
	var shielded := false
	var _cooldown_left := 0.0
	var _jump_left := 0.0
	var side := "enemy"

	func _ready() -> void:
		add_to_group("player_team" if side == "player" else "enemy_team")

var failures: Array[String] = []
var bot: Node2D
var player: StubFigure
var enemy: StubFigure

func _ready() -> void:
	await get_tree().process_frame
	_setup()
	_check_enemy_ahead_is_positive_forward()
	_check_enemy_behind_is_negative_forward()
	_check_velocity_rotation()
	_check_own_velocity_rotation()
	_check_rotation_invariance()
	_check_zero_rotation_matches_world_frame()
	_report()

func _setup() -> void:
	player = _figure("player", Vector2(500, 500))
	enemy = _figure("enemy", Vector2(500, 800))
	bot = Node2D.new()
	bot.set_script(BotControllerScript)
	bot.global_position = Vector2(500, 500)
	add_child(bot)
	bot.figure_path = bot.get_path_to(player)
	await get_tree().process_frame

func _figure(side: String, at: Vector2) -> StubFigure:
	var fig := StubFigure.new()
	fig.side = side
	fig.global_position = at
	add_child(fig)
	return fig

func _check_enemy_ahead_is_positive_forward() -> void:
	# Agent faces world +Y (rotation PI/2): the enemy 300 px along +Y is
	# dead ahead -> local (300, 0) -> rel_x = 300/576, rel_y = 0. In the
	# old world frame it read (0, 300) -> rel_x = 0.
	player.rotation = PI / 2.0
	enemy.velocity = Vector2.ZERO
	var enemies: Array = bot.call("_collect_obs_parts")["enemies"]
	if enemies.size() == 20:
		if float(enemies[0]) <= 0.0:
			failures.append("enemy straight ahead must report rel_x > 0, got %s" % str(enemies[0]))
		if not is_equal_approx(float(enemies[0]), 300.0 / NORM_HALF_W):
			failures.append("enemy ahead rel_x must be %f, got %s" % [300.0 / NORM_HALF_W, str(enemies[0])])
		if not is_zero_approx(float(enemies[1])):
			failures.append("enemy ahead rel_y must be 0, got %s" % str(enemies[1]))

func _check_enemy_behind_is_negative_forward() -> void:
	player.rotation = PI / 2.0
	enemy.global_position = Vector2(500, 200)
	var enemies: Array = bot.call("_collect_obs_parts")["enemies"]
	if enemies.size() == 20:
		if float(enemies[0]) >= 0.0:
			failures.append("enemy straight behind must report rel_x < 0, got %s" % str(enemies[0]))
		if not is_equal_approx(float(enemies[0]), -300.0 / NORM_HALF_W):
			failures.append("enemy behind rel_x must be %f, got %s" % [-300.0 / NORM_HALF_W, str(enemies[0])])
	enemy.global_position = Vector2(500, 800)

func _check_velocity_rotation() -> void:
	# Agent facing +Y: an enemy moving world +Y moves straight forward
	# (local (160, 0) -> vel_x = 0.5); world +X is to its local -Y side
	# (local (0, -160) -> vel_y = -0.5).
	player.rotation = PI / 2.0
	enemy.velocity = Vector2(0, 160)
	var enemies: Array = bot.call("_collect_obs_parts")["enemies"]
	if enemies.size() == 20:
		if not is_equal_approx(float(enemies[3]), 0.5):
			failures.append("forward enemy vel_x must be 0.5 (160/320), got %s" % str(enemies[3]))
		if not is_zero_approx(float(enemies[4])):
			failures.append("forward enemy vel_y must be 0, got %s" % str(enemies[4]))
	enemy.velocity = Vector2(160, 0)
	enemies = bot.call("_collect_obs_parts")["enemies"]
	if enemies.size() == 20:
		if not is_zero_approx(float(enemies[3])):
			failures.append("lateral enemy vel_x must be 0, got %s" % str(enemies[3]))
		if not is_equal_approx(float(enemies[4]), -0.5):
			failures.append("lateral enemy vel_y must be -0.5, got %s" % str(enemies[4]))
	enemy.velocity = Vector2.ZERO

func _check_own_velocity_rotation() -> void:
	# Own velocity in the same local frame: facing +Y and moving world +Y
	# is forward motion -> own vel_x = 1.0 (in the world frame it read 0).
	player.rotation = PI / 2.0
	player.velocity = Vector2(0, 320)
	var own: Array = bot.call("_collect_obs_parts")["own"]
	if own.size() == 4:
		if not is_equal_approx(float(own[2]), 1.0):
			failures.append("own forward vel_x must be 1.0 (320/320), got %s" % str(own[2]))
		if not is_zero_approx(float(own[3])):
			failures.append("own forward vel_y must be 0, got %s" % str(own[3]))
	player.velocity = Vector2.ZERO

func _check_rotation_invariance() -> void:
	# Rotate the whole battle by an extra PI/3 around the agent — agent
	# rotation, enemy offset and enemy velocity all rotate together: the
	# observation must not change at all.
	player.rotation = PI / 2.0
	enemy.global_position = Vector2(500, 800)
	enemy.velocity = Vector2(0, 160)
	var before: Array = bot.get_obs()["obs"]
	var phi := PI / 3.0
	player.rotation += phi
	enemy.global_position = Vector2(500, 500) + Vector2(0, 300).rotated(phi)
	enemy.velocity = Vector2(0, 160).rotated(phi)
	var after: Array = bot.get_obs()["obs"]
	if before.size() != EXPECTED_SIZE or after.size() != EXPECTED_SIZE:
		failures.append("flat obs must hold %d floats, got %d / %d" % [EXPECTED_SIZE, before.size(), after.size()])
		return
	for i in EXPECTED_SIZE:
		if not is_equal_approx(float(before[i]), float(after[i])):
			failures.append("obs must be rotation-invariant: [%d] %s != %s" % [i, str(before[i]), str(after[i])])
			break
	enemy.velocity = Vector2.ZERO

func _check_zero_rotation_matches_world_frame() -> void:
	# With rotation 0 the local frame equals the world frame: the issue
	# #381 world-frame expectations must still hold exactly.
	player.rotation = 0.0
	enemy.global_position = Vector2(1068, 500)
	enemy.velocity = Vector2(320, 0)
	var enemies: Array = bot.call("_collect_obs_parts")["enemies"]
	if enemies.size() == 20:
		if not is_equal_approx(float(enemies[0]), 568.0 / NORM_HALF_W):
			failures.append("rotation-0 rel_x must equal the world frame %f, got %s" % [568.0 / NORM_HALF_W, str(enemies[0])])
		if not is_zero_approx(float(enemies[1])):
			failures.append("rotation-0 rel_y must be 0, got %s" % str(enemies[1]))
		if not is_equal_approx(float(enemies[3]), 1.0):
			failures.append("rotation-0 vel_x must be 1.0 (320/320), got %s" % str(enemies[3]))

func _report() -> void:
	if failures.is_empty():
		print("ISSUE419 OK: observations are agent-local (facing = +X), rotation-invariant, 50-float layout intact")
	else:
		for f in failures:
			print("ISSUE419 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
