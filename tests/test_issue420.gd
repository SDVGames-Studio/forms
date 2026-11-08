extends Node
## Regression check for issue #420: every value returned by get_obs()
## must stay inside its documented bounds (OBSERVATION_SPEC.md) across a
## battery of game states — signed slots (relative positions, velocities)
## in [-1, 1], fraction/flag slots (HP, shield, cooldowns, arena position
## fractions) in [0, 1], booleans as exactly 0.0/1.0. Raw world
## coordinates or unscaled HP values must never leave a controller.
## Sweeps BOTH game controllers: BotController.gd (46-float battlefield
## vector) and TrainingBot.gd (2-float scaffold vector, including
## off-arena drift).
##
## Run headless: godot --headless res://tests/test_issue420.tscn
## Exit code 0 = pass.

const BotControllerScript := preload("res://BotController.gd")
const TrainingBotScript := preload("res://TrainingBot.gd")

# Layout mirrors BotController.gd (issue #381): 4 + 4*5 + 4*5 + 2 = 46.
const EXPECTED_SIZE := 46

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
var extra: Array = []

func _ready() -> void:
	await get_tree().process_frame
	_setup()
	_check_normal_state()
	_check_extreme_state()
	_check_shield_flag_exact()
	_check_overflow_teams()
	_check_no_figure_fallback()
	_check_training_bot_inside_arena()
	_check_training_bot_off_arena()
	_report()

func _setup() -> void:
	player = _figure("player", Vector2(500, 500))
	enemy = _figure("enemy", Vector2(700, 500))
	bot = Node2D.new()
	bot.set_script(BotControllerScript)
	add_child(bot)
	bot.position = Vector2(500, 500)
	bot.figure_path = bot.get_path_to(player)
	await get_tree().process_frame

func _figure(side: String, at: Vector2) -> StubFigure:
	var fig := StubFigure.new()
	fig.side = side
	fig.position = at
	add_child(fig)
	return fig

## Documented per-slot ranges (OBSERVATION_SPEC.md): one [min, max] pair
## per flat index — own (hp, shield, vel, vel), 8 x figure blocks
## (rel, rel, hp, vel, vel), cooldowns (fire, jump). Signed slots are
## [-1, 1], fraction/flag slots are [0, 1].
func _signed_range() -> Array:
	return [-1.0, 1.0]

func _unsigned_range() -> Array:
	return [0.0, 1.0]

func _battlefield_ranges() -> Array:
	var ranges: Array = [_unsigned_range(), _unsigned_range(), _signed_range(), _signed_range()]
	for _block in 8:
		ranges.append_array([_signed_range(), _signed_range(), _unsigned_range(), _signed_range(), _signed_range()])
	ranges.append_array([_unsigned_range(), _unsigned_range()])
	return ranges

func _check_battlefield_bounds(label: String) -> void:
	var flat: Array = bot.get_obs()["obs"]
	if flat.size() != EXPECTED_SIZE:
		failures.append("%s: flat obs must hold %d floats, got %d" % [label, EXPECTED_SIZE, flat.size()])
		return
	var ranges := _battlefield_ranges()
	for i in EXPECTED_SIZE:
		var v := float(flat[i])
		if v < ranges[i][0] or v > ranges[i][1]:
			failures.append("%s: obs[%d]=%s outside documented [%s, %s]" % [label, i, str(flat[i]), str(ranges[i][0]), str(ranges[i][1])])

func _expect(value, expected: float, label: String) -> void:
	if not is_equal_approx(float(value), expected):
		failures.append("%s must be %s, got %s" % [label, str(expected), str(value)])

func _check_normal_state() -> void:
	# A sane mid-battle state: everything inside the arena, sub-max speeds,
	# mid cooldowns, one shield up — all 46 values in bounds.
	player.health = 80
	player.shielded = true
	player.velocity = Vector2(160, -40)
	player._cooldown_left = 1.0
	player._jump_left = 0.5
	enemy.health = 60
	enemy.position = Vector2(900, 620)
	enemy.velocity = Vector2(-200, 90)
	_check_battlefield_bounds("normal state")

func _check_extreme_state() -> void:
	# Way outside the arena, way past max speed, HP above max, cooldowns
	# past their ceilings — every slot must clamp exactly to its edge.
	player.health = 250
	player.velocity = Vector2(6000, -6000)
	player._cooldown_left = 5.0
	player._jump_left = 3.0
	enemy.health = 180
	enemy.position = Vector2(5600, -4200)
	enemy.velocity = Vector2(9000, -9000)
	var dead := _figure("enemy", Vector2(600, 500))
	dead.health = -30
	_check_battlefield_bounds("extreme state")
	dead.free()
	var flat: Array = bot.get_obs()["obs"]
	_expect(flat[0], 1.0, "extreme: own hp_frac must clamp to 1.0")
	_expect(flat[2], 1.0, "extreme: own vel_x must clamp to 1.0")
	_expect(flat[3], -1.0, "extreme: own vel_y must clamp to -1.0")
	_expect(flat[4], 1.0, "extreme: enemy rel_x must clamp to 1.0")
	_expect(flat[5], -1.0, "extreme: enemy rel_y must clamp to -1.0")
	_expect(flat[6], 1.0, "extreme: enemy hp_frac must clamp to 1.0")
	_expect(flat[7], 1.0, "extreme: enemy vel_x must clamp to 1.0")
	_expect(flat[8], -1.0, "extreme: enemy vel_y must clamp to -1.0")
	_expect(flat[44], 1.0, "extreme: fire cooldown fraction must clamp to 1.0")
	_expect(flat[45], 1.0, "extreme: jump cooldown fraction must clamp to 1.0")
	# The dead (health <= 0) figure must not leak a negative hp_frac.
	_expect(flat[6], 1.0, "extreme: nearest visible enemy slot stays in bounds with a dead figure nearby")

func _check_shield_flag_exact() -> void:
	# Booleans are exactly 0.0 / 1.0 floats, never a raw value.
	player.shielded = true
	var on: Array = bot.get_obs()["obs"]
	if typeof(on[1]) != TYPE_FLOAT or float(on[1]) != 1.0:
		failures.append("shield flag on must be exactly float 1.0, got %s" % str(on[1]))
	player.shielded = false
	var off: Array = bot.get_obs()["obs"]
	if typeof(off[1]) != TYPE_FLOAT or float(off[1]) != 0.0:
		failures.append("shield flag off must be exactly float 0.0, got %s" % str(off[1]))

func _check_overflow_teams() -> void:
	# Six extra enemies and zero allies: only the 4 nearest enemy slots
	# report, everything else pads with zeros — length and bounds hold.
	for i in 6:
		var fig := _figure("enemy", Vector2(600 + 100 * i, 500))
		fig.health = 40 + i
		extra.append(fig)
	_check_battlefield_bounds("overflow teams")

func _check_no_figure_fallback() -> void:
	# Every figure gone: the vector stays well-formed and in bounds,
	# own = [1.0, 0.0, 0.0, 0.0] (fully-healed stationary bot).
	for fig in [player, enemy] + extra:
		fig.free()
	_check_battlefield_bounds("no-figure fallback")
	var flat: Array = bot.get_obs()["obs"]
	var fallback := [1.0, 0.0, 0.0, 0.0]
	for i in 4:
		_expect(flat[i], fallback[i], "no-figure fallback own[%d]" % i)

func _training_bot(at: Vector2) -> Node2D:
	var tb := Node2D.new()
	tb.set_script(TrainingBotScript)
	add_child(tb)
	tb.position = at
	return tb

func _check_training_bot_inside_arena() -> void:
	# Spawn pose of training_scene.tscn: local (576, 400) -> [0.5, 400/752].
	var tb := _training_bot(Vector2(576, 400))
	var obs: Array = tb.get_obs()["obs"]
	if obs.size() != 2:
		failures.append("TrainingBot obs must hold 2 floats, got %d" % obs.size())
	else:
		_expect(obs[0], 0.5, "TrainingBot inside arena: x fraction must be 576/1152")
		_expect(obs[1], 400.0 / 752.0, "TrainingBot inside arena: y fraction must be 400/752")
	tb.free()

func _check_training_bot_off_arena() -> void:
	# The scaffold walk has no wall check, so the position can drift past
	# the arena rect — both fractions must clamp to [0, 1].
	for pos in [Vector2(-400.0, 2000.0), Vector2(2000.0, -50.0), Vector2(1152.0, 752.0)]:
		var tb := _training_bot(pos)
		var obs: Array = tb.get_obs()["obs"]
		for i in 2:
			if float(obs[i]) < 0.0 or float(obs[i]) > 1.0:
				failures.append("TrainingBot at %s: obs[%d]=%s outside [0, 1]" % [str(pos), i, str(obs[i])])
		if pos == Vector2(-400.0, 2000.0):
			_expect(obs[0], 0.0, "TrainingBot off-arena left must clamp x to 0.0")
			_expect(obs[1], 1.0, "TrainingBot off-arena below must clamp y to 1.0")
		if pos == Vector2(2000.0, -50.0):
			_expect(obs[0], 1.0, "TrainingBot off-arena right must clamp x to 1.0")
			_expect(obs[1], 0.0, "TrainingBot off-arena above must clamp y to 0.0")
		tb.free()

func _report() -> void:
	if failures.is_empty():
		print("ISSUE420 OK: every get_obs() value stays inside its documented [-1, 1] / [0, 1] bounds across all tested game states")
	else:
		for f in failures:
			print("ISSUE420 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
