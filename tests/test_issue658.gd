extends Node
## Regression check for issue #658: every enemy observation slot carries
## a line-of-sight float — 1.0 (Visible) when a clear world-geometry ray
## reaches the enemy, 0.0 (Occluded) when a wall stands between. This is
## the issue's acceptance case: drop a wall between two figures and the
## LoS observation for that enemy flips 1.0 -> 0.0; take the wall away
## and it flips back. Figures never occlude (every figure RID joins the
## ray exclude list), missing enemy slots pad los with 0.0, and ally
## slots keep the classic 5 values.
##
## Run headless: godot --headless res://tests/test_issue658.tscn
## Exit code 0 = pass.

const BotControllerScript := preload("res://scripts/BotController.gd")

# OBSERVATION_SPEC.md constants, copied from the spec tables — NOT from
# BotController.gd — so the test fails if either side drifts.
const SPEC_SIZE := 54            # 4 + 4*6 + 4*5 + 2 + 4 (enemy los included)
const ENEMY_BLOCK_START := 4     # first enemy slot, 6 values each
const LOS_OFFSET_IN_BLOCK := 5   # los trails [rel_x, rel_y, hp, vel_x, vel_y]
const ALLIES_LEN := 20           # allies stay 5-wide — no los slot

class StubFigure extends CharacterBody2D:
	var health := 100
	var shielded := false
	var _cooldown_left := 0.0
	var _jump_left := 0.0
	var side := "enemy"

	func _ready() -> void:
		# Figure layer (2), never terrain (1): figures must not occlude —
		# the controller also excludes every figure RID from the ray.
		collision_layer = 2
		collision_mask = 0
		add_to_group("player_team" if side == "player" else "enemy_team")

var failures: Array[String] = []
var bot: Node2D
var me: StubFigure
var enemy_behind: StubFigure
var enemy_clear: StubFigure

func _ready() -> void:
	await get_tree().physics_frame
	_setup()
	_check_clear_field()
	await _check_wall_occludes()
	await _check_wall_removed()
	_report()

func _figure(side: String, at: Vector2) -> StubFigure:
	var fig := StubFigure.new()
	fig.side = side
	fig.position = at
	add_child(fig)
	return fig

## Terrain on layer 1 — the ground convention from DestructibleGround /
## IndestructibleGround. A 40x200 rectangle at (600, 300): it cuts the
## horizontal ray me -> enemy_behind, but the ray me -> enemy_clear
## passes below the wall's footprint (y > 400 at x = 600).
func _wall() -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 200)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(600, 300)
	add_child(wall)
	return wall

func _setup() -> void:
	TeamBlackboard.reset_blackboard()
	me = _figure("player", Vector2(200, 300))
	enemy_behind = _figure("enemy", Vector2(1000, 300))  # behind the wall spot
	enemy_clear = _figure("enemy", Vector2(1000, 700))   # ray passes below it
	_figure("player", Vector2(260, 320))                 # ally for the allies block
	bot = Node2D.new()
	bot.set_script(BotControllerScript)
	add_child(bot)
	bot.position = Vector2(200, 300)
	bot.figure_path = bot.get_path_to(me)

func _los_at(flat: Array, slot: int) -> float:
	return float(flat[ENEMY_BLOCK_START + 6 * slot + LOS_OFFSET_IN_BLOCK])

func _expect(value: float, expected: float, label: String) -> void:
	if not is_equal_approx(value, expected):
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(value)])

func _check_clear_field() -> void:
	var flat: Array = bot.get_obs()["obs"]
	_expect(float(flat.size()), SPEC_SIZE, "flat length (no wall)")
	# Nearest first: enemy_behind (800 px) then enemy_clear (~894 px).
	_expect(_los_at(flat, 0), 1.0, "clear field: nearest enemy los")
	_expect(_los_at(flat, 1), 1.0, "clear field: second enemy los")
	_expect(_los_at(flat, 2), 0.0, "clear field: empty enemy slot pads los 0.0")
	_expect(_los_at(flat, 3), 0.0, "clear field: empty enemy slot pads los 0.0")

func _check_wall_occludes() -> void:
	var wall := _wall()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var flat: Array = bot.get_obs()["obs"]
	_expect(float(flat.size()), SPEC_SIZE, "flat length (wall up)")
	_expect(_los_at(flat, 0), 0.0, "wall up: enemy BEHIND the wall reads occluded")
	_expect(_los_at(flat, 1), 1.0, "wall up: enemy beside the wall stays visible")
	var allies: Array = bot.call("_collect_obs_parts")["allies"]
	if allies.size() != ALLIES_LEN:
		failures.append("allies block must stay %d floats, got %d" % [ALLIES_LEN, allies.size()])
	wall.free()

func _check_wall_removed() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var flat: Array = bot.get_obs()["obs"]
	_expect(_los_at(flat, 0), 1.0, "wall gone: the same enemy flips back to visible")

func _report() -> void:
	if failures.is_empty():
		print("ISSUE658 OK: enemy los slots flip 1.0 -> 0.0 -> 1.0 as the wall appears and disappears; allies stay 5-wide; flat length 54")
	else:
		for f in failures:
			print("ISSUE658 FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
