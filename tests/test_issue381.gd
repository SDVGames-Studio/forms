extends Node
## Regression check for issue #381: BotController.get_obs() must return a
## non-empty Dictionary whose "obs" is a flat float array of CONSTANT
## length, with every value normalized — relative positions/velocities in
## [-1, 1], HP/cooldown fractions in [0, 1]. No raw coordinates or HP
## values may leak out.
##
## The figures are minimal stand-ins exposing exactly the game-state
## surface the real Player.gd/Npc.gd figures report (health, shielded,
## velocity, cooldown vars, team groups) — the real scripts' _ready pulls
## level services a bare test scene has no need for.
##
## Run headless: godot --headless res://tests/test_issue381.tscn
## Exit code 0 = pass.

const BotControllerScript := preload("res://BotController.gd")

# Layout mirrors BotController.gd (issue #381): 4 own + 4*5 enemies +
# 4*5 allies + 2 cooldowns = 46, and the same normalization scales.
const EXPECTED_SIZE := 46
const NORM_HALF_W := 576.0
const NORM_HALF_H := 376.0

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
var ally: StubFigure
var enemy_near: StubFigure
var enemy_far: StubFigure

func _ready() -> void:
	await get_tree().process_frame
	_setup()
	var parts: Dictionary = bot.call("_collect_obs_parts")
	_check_parts_shape(parts)
	_check_flat_shape(bot.get_obs(), parts)
	_check_own_vitals(parts)
	_check_relative_positions(parts)
	_check_cooldowns(parts)
	parts = _check_consistency_after_death()
	_report()

func _setup() -> void:
	player = _figure("player", Vector2(500, 500))
	ally = _figure("player", Vector2(300, 500))
	enemy_near = _figure("enemy", Vector2(1068, 500))
	enemy_far = _figure("enemy", Vector2(5000, 5000))
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

func _check_parts_shape(parts: Dictionary) -> void:
	# The dictionary of float arrays: exactly the four named groups, each
	# the expected size, all values floats within [-1, 1].
	if parts.keys().size() != 4:
		failures.append("expected 4 obs groups, got %d" % parts.keys().size())
	for key in ["own", "enemies", "allies", "cooldowns"]:
		var row: Array = parts.get(key, [])
		var expected := 4 if key == "own" else (2 if key == "cooldowns" else 20)
		if row.size() != expected:
			failures.append("group '%s' must hold %d floats, got %d" % [key, expected, row.size()])
		for v in row:
			if typeof(v) != TYPE_FLOAT:
				failures.append("group '%s' holds a non-float: %s" % [key, str(v)])
			elif absf(v) > 1.0:
				failures.append("group '%s' value out of [-1, 1]: %f" % [key, v])

func _check_flat_shape(obs: Dictionary, parts: Dictionary) -> void:
	# The contract: one non-empty Dictionary, "obs" a flat float array of
	# constant length equal to the concatenated named groups.
	if obs.is_empty() or not obs.has("obs"):
		failures.append("get_obs() must return {'obs': [floats]}, got keys %s" % str(obs.keys()))
		return
	var flat: Array = obs["obs"]
	if flat.size() != EXPECTED_SIZE:
		failures.append("flat obs must hold %d floats, got %d" % [EXPECTED_SIZE, flat.size()])
	for v in flat:
		if typeof(v) != TYPE_FLOAT:
			failures.append("flat obs holds a non-float: %s" % str(v))
		elif absf(v) > 1.0:
			failures.append("flat obs value out of [-1, 1]: %f" % v)
	if flat.size() == EXPECTED_SIZE:
		for i in EXPECTED_SIZE:
			if not is_equal_approx(float(flat[i]), _concatenated(parts)[i]):
				failures.append("flat obs [%d] does not match the named groups" % i)
				break

func _concatenated(parts: Dictionary) -> Array:
	var out: Array = []
	for key in ["own", "enemies", "allies", "cooldowns"]:
		out.append_array(parts[key])
	return out

func _check_own_vitals(parts: Dictionary) -> void:
	# Half HP + raised shield -> [0.5, 1.0, 0, 0]; raw health must NOT appear.
	player.health = 50
	player.shielded = true
	var own: Array = bot.call("_collect_obs_parts")["own"]
	if own.size() == 4:
		if not is_equal_approx(float(own[0]), 0.5):
			failures.append("own hp fraction must be 0.5, got %s" % str(own[0]))
		if float(own[1]) != 1.0:
			failures.append("own shield slot must be 1.0, got %s" % str(own[1]))
		if not (is_zero_approx(float(own[2])) and is_zero_approx(float(own[3]))):
			failures.append("own velocity slots must be 0, got %s" % str([own[2], own[3]]))
	player.health = 100
	player.shielded = false

func _check_relative_positions(parts: Dictionary) -> void:
	# Enemy slots: nearest first. enemy_near at +568 px -> 568/576; the far
	# enemy at +4500 px clamps to 1.0 (the raw value 7.8 must never leak).
	var enemies: Array = parts["enemies"]
	if enemies.size() == 20:
		var near_x := clampf(568.0 / NORM_HALF_W, -1.0, 1.0)
		if not is_equal_approx(float(enemies[0]), near_x):
			failures.append("nearest enemy rel_x must be %f, got %s" % [near_x, str(enemies[0])])
		if not is_zero_approx(float(enemies[1])):
			failures.append("nearest enemy rel_y must be 0, got %s" % str(enemies[1]))
		if float(enemies[5]) != 1.0 or float(enemies[6]) != 1.0:
			failures.append("far enemy must clamp to (1, 1), got %s" % str([enemies[5], enemies[6]]))
		# Hurt the near enemy: its HP slot must be a fraction, never the
		# raw value.
		enemy_near.health = 25
		var enemies2: Array = bot.call("_collect_obs_parts")["enemies"]
		if not is_equal_approx(float(enemies2[2]), 0.25):
			failures.append("enemy hp fraction must be 0.25, got %s" % str(enemies2[2]))
		enemy_near.health = 100
	# Allies: the own figure is excluded (it is the origin); the remaining
	# ally sits at -200 px -> -200/576.
	var allies: Array = parts["allies"]
	if allies.size() == 20:
		var ally_x := clampf(-200.0 / NORM_HALF_W, -1.0, 1.0)
		if not is_equal_approx(float(allies[0]), ally_x):
			failures.append("ally rel_x must be %f, got %s" % [ally_x, str(allies[0])])
		if not is_zero_approx(float(allies[1])):
			failures.append("ally rel_y must be 0, got %s" % str(allies[1]))

func _check_cooldowns(parts: Dictionary) -> void:
	# Fire pause 1.0 s of the 2.0 s ceiling -> 0.5; jump 0.5 s of 1.0 s -> 0.5.
	player._cooldown_left = 1.0
	player._jump_left = 0.5
	var cds: Array = bot.call("_collect_obs_parts")["cooldowns"]
	if cds.size() == 2:
		if not is_equal_approx(float(cds[0]), 0.5) or not is_equal_approx(float(cds[1]), 0.5):
			failures.append("cooldown fractions must be [0.5, 0.5], got %s" % str(cds))
	var flat: Array = bot.get_obs()["obs"]
	if flat.size() == EXPECTED_SIZE and not is_equal_approx(float(flat[44]), 0.5):
		failures.append("flat tail fire-cooldown must be 0.5, got %s" % str(flat[44]))
	player._cooldown_left = 0.0
	player._jump_left = 0.0

func _check_consistency_after_death() -> Dictionary:
	# A dead ally must drop out of the allies block while the total length
	# stays 46 — zero padding keeps the layout constant.
	ally.health = 0
	var parts: Dictionary = bot.call("_collect_obs_parts")
	var flat: Array = bot.get_obs()["obs"]
	if flat.size() != EXPECTED_SIZE:
		failures.append("flat obs size changed after a death: %d" % flat.size())
	var allies: Array = parts["allies"]
	for v in allies:
		if not is_zero_approx(float(v)):
			failures.append("dead ally must leave zeroed ally slots, got %s" % str(allies))
			break
	return parts

func _report() -> void:
	if failures.is_empty():
		print("ISSUE381 OK: get_obs() returns 46 normalized floats in a constant layout")
	else:
		for f in failures:
			print("ISSUE381 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
