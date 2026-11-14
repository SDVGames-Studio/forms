extends Node
## Regression check for issue #279: on Level 5 (the disc arena) it was
## impossible to keep moving clockwise — the character stopped and just
## shook left-right at the rim positions where the walking tangent is
## vertical (3/9 o'clock). Root cause: the walk basis was oriented by the
## legacy "flip while tangent.x < 0" rule, so the gravity vector's tiny
## numeric wobble at those positions reversed the walking direction
## between frames; the issue #277 rework (PR #284) replaced it with a
## continuity-oriented tangent. This test guards the WALK itself on the
## REAL Level5 scene, through the real TurnController turn flow.
##
## Checks (both directions — the disc has a vertical tangent on BOTH
## sides, and the old rule stalled the walk at either):
##  1. Holding move_right from the 12 o'clock spawn walks CLOCKWISE past
##     3 o'clock: at least 120° of rim in 720 physics ticks (12 s at
##     320 px/s on a 1280 px ring is ~169° ideal; 120° allows the natural
##     first-turn roll delay and chord-bounce friction).
##  2. Holding move_left walks COUNTER-CLOCKWISE at least 120° past
##     9 o'clock.
##  3. The walking tangent never flips 180° between frames (continuity).
##  4. The figure stays on the rim (never launched ballistically) and
##     the angular progress does not oscillate (few direction reversals —
##     the old bug shook in place, producing hundreds).
##
## Run headless: godot --headless res://tests/test_issue279.tscn
## Exit code 0 = pass.

const Level5Scene := preload("res://scenes/levels/Level5.tscn")
const TICKS := 720
const MIN_ARC := deg_to_rad(120.0)
## Rim outer radius 1280 + capsule 24; a real walk hugs the surface.
const MAX_RADIUS := 1280.0 + 140.0
## Chord-vertex bounces may jiggle the angle; a stuck shake produces
## hundreds of reversals, a healthy walk almost none.
const MAX_REVERSALS := 30


## Walk `action` around the real Level5 rim through the real turn flow
## and report [net arc (rad), max radius, reversals, min tangent dot].
func _walk_rim(action: String) -> Array:
	var level := Level5Scene.instantiate()
	add_child(level)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fig := level.get_node("Player") as CharacterBody2D
	# Walk the TERRAIN: issue #279 is about the rim's gravity direction,
	# so remove every other figure — figures block each other by design
	# (issue #144) and teammates/NPCs standing on the rim would stop the
	# walk at their capsules.
	for group in ["player_team", "enemy_team"]:
		for member in get_tree().get_nodes_in_group(group):
			if member != fig:
				member.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Begin the player's turn through the controller's own door and keep
	# the turn timer topped up — the figure's input branch only runs on
	# the player team's live turn, and fighting the state machine with
	# forced fields wedges the post-shot handover (input frozen).
	TurnController.call("_begin_turn", "player")
	await get_tree().physics_frame
	var centre := (level.get_node("Ring") as Node2D).global_position
	Input.action_press(action)
	var angles: Array[float] = []
	var min_dot := 1.0
	var max_radius := 0.0
	var reversals := 0
	var prev_delta := 0.0
	var prev_tangent: Vector2 = fig.current_tangent()
	for i in TICKS:
		TurnController.set("_turn_left", 15.0)
		await get_tree().physics_frame
		var rel := fig.global_position - centre
		angles.append(atan2(rel.y, rel.x))
		max_radius = maxf(max_radius, rel.length())
		var tangent: Vector2 = fig.current_tangent()
		min_dot = minf(min_dot, tangent.dot(prev_tangent))
		prev_tangent = tangent
		if angles.size() >= 2:
			var delta := wrapf(angles[-1] - angles[-2], -PI, PI)
			if prev_delta != 0.0 and absf(delta) > 0.0005 \
					and absf(prev_delta) > 0.0005 \
					and signf(delta) != signf(prev_delta):
				reversals += 1
			if absf(delta) > 0.0005:
				prev_delta = delta
	Input.action_release("move_right")
	Input.action_release("move_left")
	var arc := 0.0
	for i in angles.size() - 1:
		arc += wrapf(angles[i + 1] - angles[i], -PI, PI)
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return [arc, max_radius, reversals, min_dot]


func _ready() -> void:
	var ok := true
	# 1. Clockwise: holding move_right (D) from the 12 o'clock spawn the
	# figure must travel past 3 o'clock — increasing angle on screen.
	var cw: Array = await _walk_rim("move_right")
	var cw_ok: bool = cw[0] >= MIN_ARC
	print("ISSUE279 clockwise: arc=", rad_to_deg(cw[0]), "deg max_radius=",
			cw[1], " reversals=", cw[2], " min_tangent_dot=", cw[3],
			" -> ", cw_ok)
	ok = cw_ok and ok
	# 2. Counter-clockwise: holding move_left (A) past 9 o'clock.
	var ccw: Array = await _walk_rim("move_left")
	var ccw_ok: bool = ccw[0] <= -MIN_ARC
	print("ISSUE279 counter-clockwise: arc=", rad_to_deg(ccw[0]),
			"deg max_radius=", ccw[1], " reversals=", ccw[2],
			" min_tangent_dot=", ccw[3], " -> ", ccw_ok)
	ok = ccw_ok and ok
	# 3/4. Shared health checks for both walks.
	var radius_ok: bool = cw[1] <= MAX_RADIUS and ccw[1] <= MAX_RADIUS
	print("ISSUE279 stays on rim: max radius cw=", cw[1], " ccw=", ccw[1],
			" limit=", MAX_RADIUS, " -> ", radius_ok)
	ok = radius_ok and ok
	var rev_ok: bool = cw[2] <= MAX_REVERSALS and ccw[2] <= MAX_REVERSALS
	print("ISSUE279 no shake: reversals cw=", cw[2], " ccw=", ccw[2],
			" limit=", MAX_REVERSALS, " -> ", rev_ok)
	ok = rev_ok and ok
	var tan_ok: bool = cw[3] > 0.0 and ccw[3] > 0.0
	print("ISSUE279 tangent continuity: min dot cw=", cw[3], " ccw=",
			ccw[3], " -> ", tan_ok)
	ok = tan_ok and ok
	print("ISSUE279 ok=", ok)
	get_tree().quit(0 if ok else 1)
