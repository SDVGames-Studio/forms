extends Node2D
## Issue #547: the "choose after the start" spawn regime
## (SpawnRegime.REGIME_CHOOSE).
##
## SpawnRegime.apply adds ONE chooser as a child of the level (after
## GameConfig.apply trimmed and dressed the live figures) and hands it
## the first team's figures in group order — hero first. The chooser
## then lets the player pick each figure's standing spot AFTER the
## level has started:
##
## - the level's physics space is given two frames to flush (the same
##   rule SpawnRegime's scatter follows — freshly-entered ground
##   bodies become queryable only after a physics step), then the
##   WHOLE TREE is paused: the first-team roll freezes mid-flicker,
##   nothing falls, nobody shoots;
## - the figure being placed follows the cursor; a left click drops it
##   onto the first surface under LOCAL gravity beneath the click
##   (LevelTerrain.gravity_at), and the standing spot is validated
##   exactly like the random regimes' sampler — a clearance circle
##   free of ground — so a figure can never be embedded in terrain;
##   a click that cannot hold a figure flashes a hint instead;
## - Esc cancels the rest: the un-placed figures keep their authored
##   positions and the game starts with what was placed;
## - once the last figure is placed the pause lifts, the chooser frees
##   itself, and the (still running) roll hands the first turn over;
## - the shared zoom camera stays LIVE through the pause (owner
##   rework 2026-11-21, "unblock camera in the spawn regime"): every
##   player_camera runs PROCESS_MODE_ALWAYS for the phase, so the
##   view can be panned and zoomed while placing figures — the
##   placement LEFT clicks and taps fall through ZoomCamera to the
##   chooser, the right button pans and the wheel/± zoom;
## - the GLOBAL camera is the phase's default cam mode (owner rework
##   2026-11-24, "make the global camera a default cam mode"): the
##   figure being placed follows the cursor, and a follow camera
##   chased it off the level. The shared mode goes GLOBAL for the
##   placement — nobody is followed, only the player's pans and
##   zooms move the view — and the mode the player had is restored
##   when the phase ends (a follow type re-anchors on its figure,
##   the #552 type-change rule, so the first turn starts with the
##   classic view).
## - owner rework 2026-11-26 ("before I place character it shouldn't
##   exist on the ground" / "computer didn't place any character at
##   all"): the whole staged cast enters the phase HIDDEN — SpawnRegime
##   hides every live figure before this chooser enters the tree, so
##   nobody stands on the authored staging while the player chooses.
##   The figure being placed is revealed at the cursor the moment it
##   becomes current; once the player's team is done (last figure
##   placed, or Esc) the SCRIPT places everyone still hidden — the
##   other teams' figures appear on their authored spawn spots one
##   per AUTO_STEP beat while the pause still holds, and only when
##   the field is complete does the pause lift and the game begin.
##
## Only the FIRST team is placed by hand. Rework (owner 2026-11-20):
## the chooser runs whatever plays the team — since the #617 rework
## v2 defaults every team to the computer, a computer-played first
## team must still get its placement phase (the hand on the mouse
## does the choosing; before, SpawnRegime._apply_choose silently
## fell back to the designer regime and the feature looked dead).
## Hot-seat teams keep their authored spots.
##
## The chooser and its hint run in PROCESS_MODE_ALWAYS (input, process
## and SceneTreeTimers keep working while the tree is paused); the
## pause is tracked in `_we_paused` so a chooser never lifts somebody
## else's pause (the in-game menu's) and never outlives its own —
## `_exit_tree` is the safety net for a level swapped out mid-choose.
##
## SpawnRegime's constants are mirrored locally (tests do the same)
## instead of referencing the class back — that would be a cyclic
## script reference. ZoomCamera is safe to reference (it discovers
## this phase through the "spawn_chooser" GROUP, never through the
## script — no cycle).

## The shared zoom camera's mode handling (owner rework 2026-11-24).
const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

## How far below the click a floor may sit: the figure drops onto the
## first surface beneath the cursor, anywhere within this reach.
const CLICK_DROP := 2048.0
## Stand-off of a figure's centre from the surface along local gravity
## (SpawnRegime.STAND_OFF — capsule half-height 28.8 + 2 px settle).
const STAND_OFF := 30.8
## Clearance radius around a standing spot — nothing solid this close
## (SpawnRegime.CLEAR_RADIUS).
const CLEAR_RADIUS := 30.0
## Collision mask of the terrain (SpawnRegime.GROUND_MASK): the ground
## rides layer 1, the figures' bodies layer 8 — only ground is probed.
const GROUND_MASK := 1
## Physics frames the chooser waits before pausing and accepting
## clicks: the level's freshly-entered ground bodies become queryable
## only once the space has flushed.
const FLUSH_FRAMES := 2
## How long the "no ground there" hint stays up after a bad click.
const BAD_FLASH := 1.2
## Owner rework 2026-11-26: pause between two script-placed figures —
## the other teams' characters appear on the field one per beat.
const AUTO_STEP := 0.2
## The chooser's hint rides ABOVE the turn HUD (layer 50) and the
## in-game menu (layer 10).
const HUD_LAYER := 60

const HINT := "Choose a spawn point for %s — click on a surface"
const HINT_BAD := "No ground there — pick a surface spot for %s"
## Owner rework 2026-11-26: shown while the script places the cast
## the player did not place by hand.
const HINT_AUTO := "Placing the other teams..."

## Figures to place, hero first (filled by SpawnRegime._apply_choose
## before the chooser enters the tree).
var figures: Array = []
## Owner rework 2026-11-26: every live figure the phase hid (filled
## by SpawnRegime._apply_choose) — the auto-place tail reveals the
## still-hidden ones once the player is done.
var staged: Array = []

var _level: Node2D = null
var _index := 0
var _bad_left := 0.0
var _done := false
## True while the player is still placing their team; the auto-place
## tail (script placement of the still-hidden cast) runs when false.
var _placing := true
## Seconds to the next script-placed figure (the tail's beat).
var _auto_left := 0.0
## Still-hidden figures waiting for their auto-place beat.
var _auto_rest: Array = []
var _we_paused := false
var _layer: CanvasLayer = null
var _label: Label = null
## Cameras flipped to PROCESS_MODE_ALWAYS for the phase, each with the
## mode it had before — restored the moment the pause lifts.
var _cameras: Array = []
## Owner rework 2026-11-24: the shared camera MODE the phase started
## with (-1 = not taken) — the phase defaults to the GLOBAL camera and
## gives the player's mode back when it ends.
var _camera_mode := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_level = get_parent() as Node2D
	_build_hud()
	# Let the physics space flush before any query or pause.
	for i in FLUSH_FRAMES:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	# Someone else may still hold the pause (the in-game menu can be
	# open in the flush window) — take over only once it lifts.
	while get_tree().paused and is_inside_tree():
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	get_tree().paused = true
	_we_paused = true
	# The group makes the phase discoverable: ZoomCamera falls the
	# placement clicks and taps through to the chooser (they must
	# never start a camera drag) while everything else pans/zooms.
	add_to_group("spawn_chooser")
	_unblock_cameras()
	_hint()


func _process(delta: float) -> void:
	if _done or not _we_paused:
		return
	if _placing:
		if _bad_left > 0.0:
			_bad_left = maxf(0.0, _bad_left - delta)
			if _bad_left == 0.0:
				_hint()
		var figure := _current()
		if figure != null:
			# Owner rework 2026-11-26: the figure being placed appears at
			# the cursor the moment it becomes current — before that it
			# did not exist on the ground.
			if not figure.visible:
				figure.visible = true
			figure.global_position = get_global_mouse_position()
	else:
		# Owner rework 2026-11-26: the script-placement tail — one
		# still-hidden figure per beat (the pause holds, so the other
		# teams' characters visibly APPEAR on their spawn spots) until
		# the field is complete and the game may begin.
		_auto_left -= delta
		if _auto_left <= 0.0:
			_reveal_next()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _placing or not _we_paused:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		confirm_spot(get_global_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE
			or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		cancel()


## Place the CURRENT figure at `at` — the first validated surface spot
## under local gravity beneath it. Returns false (and flashes the
## hint) when nothing there can hold a figure. Public for tests.
func confirm_spot(at: Vector2) -> bool:
	if _done or not _placing:
		return false
	var stand := standing_spot(at)
	if stand == Vector2.INF:
		_bad_left = BAD_FLASH
		if _label != null:
			_label.text = HINT_BAD % _figure_name()
		return false
	var figure := _current()
	if figure == null:
		_finish()
		return true
	figure.global_position = stand
	_index += 1
	_bad_left = 0.0
	if _index >= figures.size():
		_finish()
	else:
		_hint()
	return true


## Esc: stop choosing — the script places the un-placed figures on
## their authored positions and the game starts. Public for tests.
func cancel() -> void:
	if _placing:
		_finish()


## The standing spot a click at `at` would produce (mirrors the
## sampler's validation), or Vector2.INF when no surface beneath the
## click can hold a figure.
func standing_spot(at: Vector2) -> Vector2:
	if _level == null:
		return Vector2.INF
	var space := _level.get_world_2d().direct_space_state
	var grav := LevelTerrain.gravity_at(get_tree(), at)
	var params := PhysicsRayQueryParameters2D.create(
			at, at + grav * CLICK_DROP, GROUND_MASK)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return Vector2.INF
	var stand: Vector2 = hit["position"] - grav * STAND_OFF
	if not _is_clear(space, stand, grav):
		return Vector2.INF
	return stand


## The chooser must never outlive its pause: a level swapped out
## mid-choose frees the chooser, the pause goes with it.
func _exit_tree() -> void:
	if _we_paused:
		_we_paused = false
		if get_tree() != null:
			get_tree().paused = false
	_restore_cameras()


## The player is done (last figure placed, or Esc). Owner rework
## 2026-11-26: the still-hidden cast — the other teams, and the
## un-placed first-team figures of a cancel — is placed by the
## SCRIPT: one figure per AUTO_STEP beat under the still-held pause
## (the chooser keeps processing through it), and the phase truly
## ends only when the field is complete. With nothing left hidden
## the phase ends immediately, exactly as before.
func _finish() -> void:
	if not _placing:
		return
	_placing = false
	_auto_rest = []
	for figure in staged:
		var node := figure as Node2D
		if node != null and is_instance_valid(node) \
				and not node.is_queued_for_deletion() \
				and not node.visible:
				_auto_rest.append(node)
	if _auto_rest.is_empty():
		_end_phase()
	else:
		if _label != null:
				_label.text = HINT_AUTO
		_auto_left = AUTO_STEP


## One beat of the script-placement tail: the next still-hidden
## figure appears on its spawn spot; the phase ends once the queue
## runs out.
func _reveal_next() -> void:
	while not _auto_rest.is_empty():
		var figure := _auto_rest.pop_front() as Node2D
		if figure == null or not is_instance_valid(figure) \
				or figure.is_queued_for_deletion():
			continue
		if not figure.visible:
			figure.visible = true
		break
	if _auto_rest.is_empty():
		_end_phase()
	else:
		_auto_left = AUTO_STEP


## The phase truly ends: the pause lifts, the cameras are restored,
## the chooser frees itself.
func _end_phase() -> void:
	_done = true
	if _we_paused:
		_we_paused = false
		get_tree().paused = false
	_restore_cameras()
	remove_from_group("spawn_chooser")
	if _layer != null:
		_layer.queue_free()
		_layer = null
		_label = null
	queue_free()


## The figure currently following the cursor; skips freed figures (a
## mid-choose death cannot happen while paused, but never wedge on a
## dead one either) and finishes the phase when the list runs out.
func _current() -> Node2D:
	while _index < figures.size():
		var figure := figures[_index] as Node2D
		if figure != null and is_instance_valid(figure):
			return figure
		_index += 1
	if not _done:
		_finish()
	return null


func _figure_name() -> String:
	var figure := _current()
	if figure != null and figure.get("display_name") != null:
		return str(figure.get("display_name"))
	return "figure %d" % (_index + 1)


func _hint() -> void:
	if _label != null:
		_label.text = HINT % _figure_name()


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "SpawnChooserHud"
	_layer.layer = HUD_LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 10.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right",
			"margin_top", "margin_bottom"]:
		panel.add_theme_constant_override(side, 12)
	_layer.add_child(panel)
	_label = Label.new()
	_label.name = "Hint"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)


## Owner rework 2026-11-21 ("unblock camera in the spawn regime"): the
## pause used to freeze the shared zoom camera with the rest of the
## tree, so a map wider than the view could not be panned or zoomed
## while placing figures. Every player_camera runs PROCESS_MODE_ALWAYS
## for the duration of the phase — input and process keep flowing
## (ZoomCamera leaves the placement clicks to the chooser and pans
## with the right button, zooms with wheel and +/-).
func _unblock_cameras() -> void:
	for camera in get_tree().get_nodes_in_group("player_camera"):
		if camera == null or not is_instance_valid(camera):
			continue
		_cameras.append([camera, camera.process_mode])
		camera.process_mode = Node.PROCESS_MODE_ALWAYS
	# Owner rework 2026-11-24 ("make the global camera a default cam
	# mode"): the placed figure is snapped to the cursor, and a follow
	# camera (character global/local) chased it — the view drifted
	# away from the level with the cursor. The GLOBAL type follows
	# NOBODY, so the level stays put and the #678 pan/zoom is all that
	# moves the view. The camera-type switch button is hidden while
	# the tree is paused (#353), so nothing can fight the phase for
	# the mode; the player's own mode returns when it lifts.
	_camera_mode = ZoomCameraScript.camera_mode
	ZoomCameraScript.camera_mode = ZoomCameraScript.MODE_GLOBAL


## The phase ends — every camera gets back the process mode it had
## before (cameras freed with a swapped-out level are skipped), and
## the shared camera MODE the player had before the phase returns
## (a follow type re-anchors on its figure, the #552 rule).
func _restore_cameras() -> void:
	for entry in _cameras:
		var camera := entry[0] as Node
		if camera != null and is_instance_valid(camera):
			camera.process_mode = entry[1]
	_cameras = []
	if _camera_mode != -1:
		ZoomCameraScript.camera_mode = _camera_mode
		_camera_mode = -1


## A standing spot must be free of terrain AND still have its floor
## (SpawnRegime._is_clear, mirrored — see the header note on cycles).
func _is_clear(space: PhysicsDirectSpaceState2D, stand: Vector2,
		grav: Vector2) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = CLEAR_RADIUS
	var shape_params := PhysicsShapeQueryParameters2D.new()
	shape_params.shape = circle
	shape_params.collision_mask = GROUND_MASK
	shape_params.transform = Transform2D(0.0, stand)
	if not space.intersect_shape(shape_params, 1).is_empty():
		return false
	var floor_params := PhysicsRayQueryParameters2D.create(
			stand, stand + grav * (STAND_OFF + CLEAR_RADIUS), GROUND_MASK)
	return not space.intersect_ray(floor_params).is_empty()
