extends Node2D
## Issue #547: the "choose after the start" spawn regime
## (SpawnRegime.REGIME_CHOOSE).
##
## SpawnRegime.apply adds ONE chooser as a child of the level (after
## GameConfig.apply trimmed and dressed the live figures) and hands it
## the hero team's figures in group order — hero first. The chooser
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
##   itself, and the (still running) roll hands the first turn over.
##
## Only the HERO team is placed by hand. Computer-played hero teams
## never reach a chooser (SpawnRegime._apply_choose falls back to the
## designer regime), and hot-seat teams keep their authored spots.
##
## The chooser and its hint run in PROCESS_MODE_ALWAYS (input, process
## and SceneTreeTimers keep working while the tree is paused); the
## pause is tracked in `_we_paused` so a chooser never lifts somebody
## else's pause (the in-game menu's) and never outlives its own —
## `_exit_tree` is the safety net for a level swapped out mid-choose.
##
## SpawnRegime's constants are mirrored locally (tests do the same)
## instead of referencing the class back — that would be a cyclic
## script reference.

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
## The chooser's hint rides ABOVE the turn HUD (layer 50) and the
## in-game menu (layer 10).
const HUD_LAYER := 60

const HINT := "Choose a spawn point for %s — click on a surface"
const HINT_BAD := "No ground there — pick a surface spot for %s"

## Figures to place, hero first (filled by SpawnRegime._apply_choose
## before the chooser enters the tree).
var figures: Array = []

var _level: Node2D = null
var _index := 0
var _bad_left := 0.0
var _done := false
var _we_paused := false
var _layer: CanvasLayer = null
var _label: Label = null


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
	_hint()


func _process(delta: float) -> void:
	if _done or not _we_paused:
		return
	if _bad_left > 0.0:
		_bad_left = maxf(0.0, _bad_left - delta)
		if _bad_left == 0.0:
			_hint()
	var figure := _current()
	if figure != null:
		figure.global_position = get_global_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _we_paused:
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
	if _done:
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


## Esc: stop choosing — the un-placed figures keep their authored
## positions and the game starts. Public for tests.
func cancel() -> void:
	if not _done:
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


func _finish() -> void:
	_done = true
	if _we_paused:
		_we_paused = false
		get_tree().paused = false
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
