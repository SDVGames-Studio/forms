extends CanvasLayer
## On-Screen Display (issue #76).
##
## Replaces the small zoom label from issue #43 with a full OSD in the
## top-left corner: current zoom level, FPS, the current level's name and
## the current character's health (issue #109). Zoom is read from the
## shared player camera every frame, so no other scripts have to notify the
## OSD about zoom changes.
##
## Issue #252: the whole OSD is a DEBUG readout — it only shows while the
## debug mode is on (GameConfig.debug_mode, switched in the settings menu,
## default on), and the same switch enables the ACTION LOG in the top-right
## corner: figures and the turn flow report their actions through
## DebugInfo.log()/OSD.log_action() and the last few lines stay visible
## there for a few seconds.

const ZOOM_LINE := "Zoom: %d%%"
const FPS_LINE := "FPS: %d"
const HEALTH_LINE := "HP: %d/%d"
const HEALTH_NONE := "HP: —"

## Issue #252: how many action-log lines stay on screen and how long a
## line lives before it fades out of the log.
const LOG_LINES := 8
const LOG_LIFETIME := 6.0

## Issue #252: the OSD instance that renders the action log (the camera
## creates exactly one; the newest one wins, freed ones deregister).
static var _current: Node = null


## Issue #252: one action-log line, sent by figures and the turn flow.
## Silently dropped while no OSD exists; the OSD itself hides the log
## when the debug mode is off (see _push_log).
static func log_action(text: String) -> void:
	if _current != null and is_instance_valid(_current):
		_current._push_log(text)


var _zoom_label: Label
var _fps_label: Label
var _level_label: Label
var _health_label: Label
var _level_name := ""
## Issue #252: action-log label (top-right) and its live lines
## ([text, expires_at] pairs; pruned in _process).
var _log_label: Label
var _log_lines: Array = []


func _ready() -> void:
	layer = 10
	# Issue #252: debug readout — hidden entirely with the debug mode off.
	visible = GameConfig.debug_mode
	_current = self
	_zoom_label = _make_label(12.0)
	_fps_label = _make_label(30.0)
	_level_label = _make_label(48.0)
	_health_label = _make_label(66.0)
	_log_label = Label.new()
	_log_label.anchor_left = 0.5
	_log_label.anchor_right = 1.0
	_log_label.offset_left = 8.0
	_log_label.offset_right = -12.0
	_log_label.offset_top = 12.0
	_log_label.offset_bottom = 200.0
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_log_label.add_theme_font_size_override("font_size", 14)
	_log_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_log_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.1, 1.0))
	_log_label.add_theme_constant_override("outline_size", 4)
	add_child(_log_label)
	_level_name = ""
	_update_level_name()


func _exit_tree() -> void:
	# Issue #252: deregister so log_action never talks to a dead OSD.
	if _current == self:
		_current = null


func _make_label(y: float) -> Label:
	var label := Label.new()
	label.position = Vector2(12.0, y)
	label.text = ""
	add_child(label)
	return label


func _process(_delta: float) -> void:
	# Issue #252: with the debug mode off the layer is invisible — skip
	# the per-frame bookkeeping entirely.
	if not visible:
		return
	_zoom_label.text = ZOOM_LINE % roundi(_camera_zoom() * 100.0)
	_fps_label.text = FPS_LINE % Engine.get_frames_per_second()
	_update_level_name()
	_update_health()
	_prune_log()


## Issue #76: current level's name (checked every frame; cheap compare).
func _update_level_name() -> void:
	var scene := get_tree().current_scene
	var level_name := String(scene.name) if scene != null else ""
	if level_name != _level_name:
		_level_name = level_name
		_level_label.text = level_name


## Issue #109: the current character's health — the active team member
## from the shared TurnController; dash while no character is active.
func _update_health() -> void:
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		_health_label.text = HEALTH_NONE
		return
	var hp = member.get("health")
	var max_hp = member.get("MAX_HEALTH")
	if not (hp is int) or not (max_hp is int) or hp <= 0:
		_health_label.text = HEALTH_NONE
		return
	_health_label.text = HEALTH_LINE % [hp, max_hp]


## Issue #252: append one action line to the top-right log (newest at the
## bottom) and trim the log to LOG_LINES entries.
func _push_log(text: String) -> void:
	if not visible:
		return
	_log_lines.append([text, _now() + LOG_LIFETIME])
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_rebuild_log()


## Issue #252: drop expired lines (every frame; cheap compare).
func _prune_log() -> void:
	var changed := false
	while not _log_lines.is_empty() and float(_log_lines[0][1]) <= _now():
		_log_lines.pop_front()
		changed = true
	if changed:
		_rebuild_log()


func _rebuild_log() -> void:
	var text := ""
	for i in _log_lines.size():
		if i > 0:
			text += "\n"
		text += String(_log_lines[i][0])
	_log_label.text = text


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _camera_zoom() -> float:
	var camera: Camera2D = null
	for node in get_tree().get_nodes_in_group("player_camera"):
		camera = node as Camera2D
		if camera != null:
			break
	return camera.zoom.x if camera != null else 1.0
