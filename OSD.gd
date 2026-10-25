extends CanvasLayer
## On-Screen Display (issue #76).
##
## Replaces the small zoom label from issue #43 with a full OSD in the
## top-left corner: current zoom level, FPS, and the current level's name.
## Zoom is read from the shared player camera every frame, so no other
## script has to notify the OSD about zoom changes.

const ZOOM_LINE := "Zoom: %d%%"
const FPS_LINE := "FPS: %d"

var _zoom_label: Label
var _fps_label: Label
var _level_name := ""

func _ready() -> void:
	layer = 10
	_zoom_label = _make_label(12.0)
	_fps_label = _make_label(30.0)
	_level_label = _make_label(48.0)
	_level_name = ""
	_update_level_name()


func _make_label(y: float) -> Label:
	var label := Label.new()
	label.position = Vector2(12.0, y)
	label.text = ""
	add_child(label)
	return label


func _process(_delta: float) -> void:
	_zoom_label.text = ZOOM_LINE % roundi(_camera_zoom() * 100.0)
	_fps_label.text = FPS_LINE % Engine.get_frames_per_second()
	_update_level_name()


## Issue #76: current level's name (checked every frame; cheap compare).
func _update_level_name() -> void:
	var scene := get_tree().current_scene
	var level_name := String(scene.name) if scene != null else ""
	if level_name != _level_name:
		_level_name = level_name
		_level_label.text = level_name


func _camera_zoom() -> float:
	var camera: Camera2D = null
	for node in get_tree().get_nodes_in_group("player_camera"):
		camera = node as Camera2D
		if camera != null:
			break
	return camera.zoom.x if camera != null else 1.0
