extends Node
## Regression check for issue #421: OBSERVATION_SPEC.md must match the
## implemented get_obs() output exactly — structure (the dictionary holds
## exactly one "obs" key), data types (every element a GDScript float),
## lengths (46 battlefield / 2 scaffold), order, and per-value formulas.
## The test drives a running episode for BOTH controllers, captures a
## sample observation, and reconstructs the identical vector from world
## state using ONLY the formulas documented in OBSERVATION_SPEC.md — the
## same construction a Python-side wrapper performs — then compares field
## by field. Any drift between spec, controller, or this test fails.
##
## Run headless: godot --headless res://tests/test_issue421.tscn
## Exit code 0 = pass.

const BotControllerScript := preload("res://BotController.gd")
const TrainingBotScript := preload("res://TrainingBot.gd")

# OBSERVATION_SPEC.md constants, copied from the spec tables — NOT from
# the controller scripts — so the test fails if either side drifts.
const SPEC_HALF_W := 576.0        # rel_x divisor (arena half width)
const SPEC_HALF_H := 376.0        # rel_y divisor (arena half height)
const SPEC_VEL := 320.0           # velocity divisor (run speed)
const SPEC_MAX_HP := 100.0        # hp_frac divisor
const SPEC_FIRE_CD := 2.0         # fire cooldown ceiling
const SPEC_JUMP_CD := 1.0         # jump cooldown ceiling
const SPEC_ARENA_W := 1152.0      # scaffold x divisor
const SPEC_ARENA_H := 752.0       # scaffold y divisor
const SPEC_MOVE_PER_STEP := 8.0   # scaffold walk delta per decision step
const SPEC_SLOTS := 4             # enemy/ally slots, nearest first

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
var enemy_a: StubFigure
var enemy_b: StubFigure
var ally_a: StubFigure

func _ready() -> void:
	await get_tree().process_frame
	await _check_battlefield_episode()
	await _check_training_episode()
	_report()

func _figure(side: String, at: Vector2) -> StubFigure:
	var fig := StubFigure.new()
	fig.side = side
	fig.position = at
	add_child(fig)
	return fig

## ---- spec-side reconstruction (uses only OBSERVATION_SPEC.md formulas) ----

func _spec_rel(frame: Node2D, target: Node2D) -> Vector2:
	# to_local() for a scale-1 2D node: (world - origin).rotated(-rotation).
	var local: Vector2 = (target.global_position - frame.global_position) \
			.rotated(-frame.global_rotation)
	return Vector2(
		clampf(local.x / SPEC_HALF_W, -1.0, 1.0),
		clampf(local.y / SPEC_HALF_H, -1.0, 1.0))

func _spec_vel(frame: Node2D, v: Vector2) -> Vector2:
	var vl: Vector2 = v.rotated(-frame.global_rotation)
	return Vector2(
		clampf(vl.x / SPEC_VEL, -1.0, 1.0),
		clampf(vl.y / SPEC_VEL, -1.0, 1.0))

func _spec_hp(fig: Node2D) -> float:
	return clampf(float(fig.health) / SPEC_MAX_HP, 0.0, 1.0)

func _spec_sorted(candidates: Array, origin: Vector2) -> Array:
	# Nearest first by squared distance; ties broken by node name.
	var figs := candidates.duplicate()
	figs.sort_custom(func(a, b):
		var da := origin.distance_squared_to(a.global_position)
		var db := origin.distance_squared_to(b.global_position)
		if da == db:
			return String(a.name) < String(b.name)
		return da < db)
	return figs

func _spec_team_block(figs: Array, frame: Node2D) -> Array:
	var rows: Array = []
	for i in SPEC_SLOTS:
		if i < figs.size():
			var f: Node2D = figs[i]
			var rel := _spec_rel(frame, f)
			var vel := _spec_vel(frame, f.velocity)
			rows.append_array([rel.x, rel.y, _spec_hp(f), vel.x, vel.y])
		else:
			rows.append_array([0.0, 0.0, 0.0, 0.0, 0.0])
	return rows

func _spec_battlefield_vector() -> Array:
	# own (4) + enemies (4x5) + allies (4x5) + cooldowns (2) = 46, in the
	# spec's exact key order.
	var frame: Node2D = player
	var enemies := _spec_sorted([enemy_a, enemy_b], frame.global_position)
	var allies := _spec_sorted([ally_a], frame.global_position)
	var vel := _spec_vel(frame, player.velocity)
	var rows: Array = [
		_spec_hp(player),
		1.0 if player.shielded else 0.0,
		vel.x,
		vel.y,
	]
	rows.append_array(_spec_team_block(enemies, frame))
	rows.append_array(_spec_team_block(allies, frame))
	rows.append(clampf(player._cooldown_left / SPEC_FIRE_CD, 0.0, 1.0))
	rows.append(clampf(player._jump_left / SPEC_JUMP_CD, 0.0, 1.0))
	return rows

## ---- shared checks ----

func _structure_check(label: String, obs: Dictionary, expected_len: int) -> Array:
	if obs.keys().size() != 1 or not obs.has("obs"):
		failures.append("%s: get_obs() must return exactly one key \"obs\" (issue #421 locked structure), got %s"
			% [label, str(obs.keys())])
	var value = obs.get("obs")
	if not (value is Array):
		failures.append("%s: obs[\"obs\"] must be an Array" % label)
		return []
	var flat: Array = value
	for i in flat.size():
		if typeof(flat[i]) != TYPE_FLOAT:
			failures.append("%s: obs[%d] must be a GDScript float (spec data type), got %s"
				% [label, i, type_string(typeof(flat[i]))])
	if flat.size() != expected_len:
		failures.append("%s: flat length must be %d (spec), got %d"
			% [label, expected_len, flat.size()])
		return []
	return flat

func _compare_field_by_field(label: String, flat: Array, expected: Array) -> void:
	for i in expected.size():
		if not is_equal_approx(float(flat[i]), float(expected[i])):
			failures.append("%s: obs[%d]=%s does not match the spec value %s"
				% [label, i, str(flat[i]), str(expected[i])])

## ---- battlefield episode (BotController.gd, 46 floats) ----

func _check_battlefield_episode() -> void:
	player = _figure("player", Vector2(500, 500))
	player.rotation = PI / 2.0
	player.health = 80
	player.shielded = true
	player.velocity = Vector2(160, -40)
	player._cooldown_left = 1.0
	player._jump_left = 0.5
	enemy_a = _figure("enemy", Vector2(900, 620))
	enemy_a.health = 60
	enemy_a.velocity = Vector2(-200, 90)
	enemy_b = _figure("enemy", Vector2(200, 300))
	enemy_b.health = 100
	enemy_b._cooldown_left = 0.4
	ally_a = _figure("player", Vector2(560, 480))
	ally_a.health = 90
	ally_a.velocity = Vector2(100, 0)
	bot = Node2D.new()
	bot.set_script(BotControllerScript)
	add_child(bot)
	bot.position = Vector2(500, 500)
	bot.figure_path = bot.get_path_to(player)
	await get_tree().process_frame
	_sample_battlefield("battlefield step 0")

	# Step the running episode on: damage the bound figure, drop its
	# shield, move an enemy much closer with saturating speed — then
	# validate the NEW sample field by field.
	player.health = 40
	player.shielded = false
	enemy_b.position = Vector2(530, 510)
	enemy_b.velocity = Vector2(-320, 640)
	await get_tree().process_frame
	_sample_battlefield("battlefield step 1")
	for fig in [player, enemy_a, enemy_b, ally_a]:
		fig.free()
	bot.free()

func _sample_battlefield(label: String) -> void:
	var obs: Dictionary = bot.get_obs()
	var flat := _structure_check(label, obs, 46)
	if flat.is_empty():
		return
	_compare_field_by_field(label, flat, _spec_battlefield_vector())
	print("ISSUE421 sample %s obs=%s" % [label, str(flat)])

## ---- scaffold episode (TrainingBot.gd, 2 floats) ----

func _check_training_episode() -> void:
	var tb := Node2D.new()
	tb.set_script(TrainingBotScript)
	add_child(tb)
	tb.position = Vector2(576, 400)
	var flat := _structure_check("scaffold spawn", tb.get_obs(), 2)
	if flat.size() == 2:
		_compare_field_by_field("scaffold spawn", flat,
			[clampf(576.0 / SPEC_ARENA_W, 0.0, 1.0), clampf(400.0 / SPEC_ARENA_H, 0.0, 1.0)])
		print("ISSUE421 sample scaffold obs=%s" % [str(flat)])

	# Step the running episode: three walk-right decision steps, then
	# validate the new sample against the spec formula.
	for _i in 3:
		tb.set_action({"move": 1})
	flat = _structure_check("scaffold after walk", tb.get_obs(), 2)
	if flat.size() == 2:
		var x := 576.0 + 3.0 * SPEC_MOVE_PER_STEP
		_compare_field_by_field("scaffold after walk", flat,
			[clampf(x / SPEC_ARENA_W, 0.0, 1.0), clampf(400.0 / SPEC_ARENA_H, 0.0, 1.0)])

	# Off-arena drift must clamp to the strict [0, 1] range.
	tb.position = Vector2(4000.0, 300.0)
	flat = _structure_check("scaffold off-arena", tb.get_obs(), 2)
	if flat.size() == 2:
		_compare_field_by_field("scaffold off-arena", flat,
			[1.0, clampf(300.0 / SPEC_ARENA_H, 0.0, 1.0)])
	tb.free()

func _report() -> void:
	if failures.is_empty():
		print("ISSUE421 OK: OBSERVATION_SPEC.md reconstructs both get_obs() vectors field by field (structure, key set, data types, lengths, order, formulas) from running episodes")
	else:
		for f in failures:
			print("ISSUE421 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
