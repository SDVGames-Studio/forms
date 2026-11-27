extends Node2D
## Issue #547: the "choose after the start" spawn regime
## (SpawnRegime.REGIME_CHOOSE).
##
## SpawnRegime.apply adds ONE chooser as a child of the level (after
## GameConfig.apply trimmed and dressed the live figures) and hands it
## the TURN-BASED placement plan — see `entries`. The chooser then
## walks that plan once the level has started:
##
## - the level's physics space is given two frames to flush (the same
##   rule SpawnRegime's scatter follows — freshly-entered ground
##   bodies become queryable only after a physics step), then the
##   WHOLE TREE is paused: the first-team roll freezes mid-flicker,
##   nothing falls, nobody shoots;
## - a HAND entry (the first team — the player side) is placed by the
##   player: the figure follows the cursor and a left click drops it
##   onto the first surface under LOCAL gravity beneath the click
##   (LevelTerrain.gravity_at), the standing spot validated exactly
##   like the random regimes' sampler — a clearance circle free of
##   ground — so a figure can never be embedded in terrain; a click
##   that cannot hold a figure flashes a hint instead;
## - a SCRIPT entry (the other teams) is placed automatically: its
##   figure appears on its authored spot one AUTO_STEP beat after it
##   becomes current. Owner rework 2026-11-27 ("make spawning
##   turn-based too"): the plan interleaves the teams — the first
##   team places a teammate, then every other team places one, round
##   after round — so the spawn order mirrors the game's turn order
##   instead of the whole first team going first with the rest
##   appearing afterwards;
## - clicks while a script beat runs are ignored (nothing is there to
##   place by hand yet); Esc cancels the REST of the hand placement —
##   the current figure returns to its authored spot and every
##   remaining entry is placed by the script, one per beat, so the
##   game still starts with the complete field;
## - once the plan runs out the pause lifts, the chooser frees itself,
##   and the (still running) roll hands the first turn over;
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
##   A figure exists on the ground only once it is placed: the
##   player's at the clicked spot the moment it becomes current, the
##   other teams' on their authored spawn spots as their script beats
##   come up.
##
## Only the FIRST team is placed by hand. Rework (owner 2026-11-20):
## the chooser runs whatever plays the team — since the #617 rework
## v2 defaults every team to the computer, a computer-played first
## team must still get its placement phase (the hand on the mouse
## does the choosing; before, SpawnRegime._apply_choose silently fell
## back to the designer regime and the feature looked dead). The
## other teams' figures are placed by the SCRIPT (hot-seat teams on
## their authored spots included — hand-placing those is a separate
## slice if the owner wants it).
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
## Pause between two script-placed figures — a script entry's figure
## appears on its spawn spot one beat after it becomes current.
const AUTO_STEP := 0.2
## The chooser's hint rides ABOVE the turn HUD (layer 50) and the
## in-game menu (layer 10).
const HUD_LAYER := 60

const HINT := "Choose a spawn point for %s — click on a surface"
const HINT_BAD := "No ground there — pick a surface spot for %s"
## Shown while a script entry waits out its beat.
const HINT_AUTO := "Placing the other teams..."

## The turn-based placement plan (owner rework 2026-11-27, "make
## spawning turn-based too"), filled by SpawnRegime._apply_choose
## before the chooser enters the tree: TEAM-ROUND order — the first
## team places a teammate, then every other team places one, round
## after round. Each entry is a Dictionary:
##   figure — the Node2D being placed;
##   hand   — true: the player clicks it in; false: the script
##            reveals it on its authored spot.
var entries: Array = []

var _level: Node2D = null
## The plan's cursor: the index of the entry being placed.
var _index := 0
var _bad_left := 0.0
var _done := false
## True while the current entry waits for the player's click (its
## figure follows the cursor); false while it waits out its script
## beat — an auto entry, or any entry after Esc.
var _waiting_hand := false
## True after Esc: every remaining entry turns into a script one.
var _cancelled := false
## Seconds to the current entry's script placement.
var _auto_left := 0.0
## The current hand figure's authored spot, captured the moment it
## becomes current (before it starts following the cursor) — Esc
## returns it there instead of leaving it floating at the mouse.
var _home := Vector2.INF
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
	_settle_current()


func _process(delta: float) -> void:
	if _done or not _we_paused:
		return
	if _waiting_hand:
		if _bad_left > 0.0:
			_bad_left = maxf(0.0, _bad_left - delta)
			if _bad_left == 0.0:
				_hint()
		var figure := _figure_at(_index)
		if figure == null:
			# The figure died mid-choose — skip its entry.
			_advance()
		else:
			# Owner rework 2026-11-26: the figure being placed appears at
			# the cursor the moment it becomes current — before that it
			# did not exist on the ground.
			if not figure.visible:
				figure.visible = true
			figure.global_position = get_global_mouse_position()
	else:
		_auto_left -= delta
		if _auto_left <= 0.0:
			_place_current_by_script()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _waiting_hand or not _we_paused:
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


## Place the CURRENT hand figure at `at` — the first validated surface
## spot under local gravity beneath it. Returns false (and flashes the
## hint) when nothing there can hold a figure; a click while a script
## beat runs is simply ignored (also false — there is nothing to place
## by hand at that moment). Public for tests.
func confirm_spot(at: Vector2) -> bool:
	if _done or not _waiting_hand:
		return false
	var stand := standing_spot(at)
	if stand == Vector2.INF:
		_bad_left = BAD_FLASH
		if _label != null:
			_label.text = HINT_BAD % _figure_name()
		return false
	var figure := _figure_at(_index)
	if figure == null:
		_advance()
		return true
	figure.global_position = stand
	_bad_left = 0.0
	_advance()
	return true


## Esc: stop choosing by hand — the current figure returns to its
## authored spot and the script places every remaining entry, one per
## beat, and the game starts. Public for tests.
func cancel() -> void:
	if _done:
		return
	if _waiting_hand:
		var figure := _figure_at(_index)
		if figure != null and _home != Vector2.INF:
			# The figure followed the cursor since it became current —
			# put it back where the phase found it.
			figure.global_position = _home
	_cancelled = true
	_settle_current()


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


## Set the phase for the entry the cursor sits on: skip dead entries,
## end the phase past the last one, and either wait for the player's
## click (a hand entry — capture its authored spot first) or arm the
## script beat. Called whenever the plan advances.
func _settle_current() -> void:
	while _index < entries.size():
		if _figure_at(_index) != null:
			break
		_index += 1
	if _index >= entries.size():
		_end_phase()
		return
	var entry: Dictionary = entries[_index]
	if entry.get("hand", false) and not _cancelled:
		_waiting_hand = true
		_home = (_figure_at(_index) as Node2D).global_position
		_hint()
	else:
		_waiting_hand = false
		_auto_left = AUTO_STEP
		if _label != null:
			_label.text = HINT_AUTO


## One step of the plan: the cursor moves to the next entry.
func _advance() -> void:
	_index += 1
	_settle_current()


## One script beat: the current entry's figure APPEARS on its authored
## spot (script figures are never moved — the beat only reveals them,
## so the #626 settle pass's placements stand) and the plan moves on.
func _place_current_by_script() -> void:
	var figure := _figure_at(_index)
	if figure != null:
		figure.visible = true
	_advance()


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


## The live figure of entry `i`, or null when the entry is out of the
## plan or its figure is gone (freed figures cannot be placed).
func _figure_at(i: int) -> Node2D:
	if i < 0 or i >= entries.size():
		return null
	var node: Node2D = null
	var raw = (entries[i] as Dictionary).get("figure")
	if raw is Node2D:
		node = raw
	if node == null or not is_instance_valid(node) \
			or node.is_queued_for_deletion():
		return null
	return node


func _figure_name() -> String:
	var figure := _figure_at(_index)
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
