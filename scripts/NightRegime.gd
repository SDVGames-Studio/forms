class_name NightRegime
extends Node
## Night regime (issue #367, rework v3: a vision MASK layer).
##
## Chosen in the level configuration menu before the level starts
## (GameConfig.night_regime). While on, a dedicated canvas layer paints a
## totally black overlay over EVERYTHING the world shows — terrain,
## figures and the background layer alike (owner rework 2026-11-07: a
## CanvasModulate could not darken the background's own canvas layer,
## and a PointLight2D wedge only brightened the ground). The overlay's
## shader carves out, every frame:
## - one vision wedge per PLAYER-team figure, aimed along that figure's
##   LIVE aim direction — it follows the view keys / AI aiming (owner
##   rework: the vision must depend on the aiming);
## - one radial hole per active light source (every ShotLight: muzzle
##   flashes, projectiles, mines, explosions), so a shot fired beyond
##   the player's vision reveals itself and whatever it lit — nothing
##   else (the issue's flash rule).
## Enemy figures get no wedge: in the night regime the player sees their
## teammates' vision only. The mask layer sits above the world canvas
## (0) and the background (-100) but below the OSD/menus (10), so the
## HUD stays readable.
##
## The manager is added once per level via NightRegime.apply(level); it
## reads the player_team group live each frame, so figures trimmed by
## GameConfig.apply or killed mid-level simply drop out of the mask.

## Canvas layer of the mask: above the world (0) and the background
## (-100), below the OSD / in-game menu (10) and friends (12+).
const MASK_LAYER := 5

## How far a figure sees, in world pixels (the mock's wedge reaches
## beyond the screen edge).
const VISION_RADIUS := 300.0

## Half-opening of the vision wedge in radians (≈ 20°; the mock's wedge
## spans roughly from -5° to +20° around the aim direction).
const VISION_HALF_ANGLE := 0.349066

## Sizes of the shader's uniform arrays (must match the declarations in
## scripts/night_mask.gdshader).
const SHADER_WEDGES := 12
const SHADER_LIGHTS := 16

## The mask's fragment shader (wedge + light-source holes).
const SHADER := preload("res://scripts/night_mask.gdshader")

var level_root: Node = null

var _mask: ColorRect = null
var _material: ShaderMaterial = null
var _wedge_data := PackedVector4Array()
var _light_data := PackedVector3Array()
var _wedge_count := 0
var _light_count := 0


## Turn the night regime on for `level`: build the mask layer that
## hides everything beyond the team's vision. Called from
## LevelConfig._ready when GameConfig.night_regime is on.
static func apply(level: Node) -> NightRegime:
	var night := NightRegime.new()
	night.name = "NightRegime"
	night.level_root = level
	level.add_child(night)
	return night


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NightMaskLayer"
	layer.layer = MASK_LAYER
	level_root.add_child(layer)

	_mask = ColorRect.new()
	_mask.name = "NightMask"
	_mask.color = Color.BLACK
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mask.material = _material
	layer.add_child(_mask)

	# Uniform arrays must be filled to their declared size before the
	# first frame renders; the counts gate how many entries are read.
	_wedge_data.resize(SHADER_WEDGES)
	_light_data.resize(SHADER_LIGHTS)
	for i in SHADER_WEDGES:
		_wedge_data[i] = Vector4.ZERO
	for j in SHADER_LIGHTS:
		_light_data[j] = Vector3.ZERO
	_material.set_shader_parameter("vision_radius", VISION_RADIUS)
	_material.set_shader_parameter("vision_half_angle", VISION_HALF_ANGLE)


func _process(_delta: float) -> void:
	if _material == null:
		return
	_collect_wedges()
	_collect_lights()
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	_material.set_shader_parameter("wedge_count", _wedge_count)
	_material.set_shader_parameter("wedges", _wedge_data)
	_material.set_shader_parameter("light_count", _light_count)
	_material.set_shader_parameter("lights", _light_data)
	_material.set_shader_parameter("cam_ix", inv.x)
	_material.set_shader_parameter("cam_iy", inv.y)
	_material.set_shader_parameter("cam_io", inv.origin)
	_material.set_shader_parameter("screen_size",
		get_viewport().get_visible_rect().size)


## Fill the wedge uniforms from the current player-team figures. A
## wedge is aimed along the figure's live aim direction: the Weapon
## child's facing sign applied to its aim_dir (exactly what the held
## weapon points along).
func _collect_wedges() -> void:
	var i := 0
	for member in get_tree().get_nodes_in_group("player_team"):
		# Untyped on purpose: aim_dir/facing_sign are duck-typed calls
		# (Player and Npc both expose them; Node2D itself has neither).
		var figure = member
		if not (figure is Node2D) or not figure.has_method("aim_dir"):
			continue
		var facing := 1.0
		var weapon = figure.get_node_or_null(NodePath("Weapon"))
		if weapon != null and weapon.has_method("facing_sign"):
			facing = weapon.facing_sign()
		var dir: Vector2 = figure.aim_dir(facing, 1.0)
		if dir.length_squared() < 0.25:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		if i < _wedge_data.size():
			_wedge_data[i] = Vector4(figure.global_position.x,
				figure.global_position.y, dir.x, dir.y)
		i += 1
		if i >= _wedge_data.size():
			break
	_wedge_count = mini(i, _wedge_data.size())


## Fill the light uniforms from the active ShotLight nodes (they join
## the "shot_lights" group in _ready and leave it automatically when
## freed/faded).
func _collect_lights() -> void:
	var i := 0
	for node in get_tree().get_nodes_in_group("shot_lights"):
		var light := node as Node2D
		if light == null or not is_instance_valid(light):
			continue
		var radius := 96.0
		if node is ShotLight:
			radius = (node as ShotLight).radius
		if i < _light_data.size():
			_light_data[i] = Vector3(light.global_position.x,
				light.global_position.y, radius)
		i += 1
		if i >= _light_data.size():
			break
	_light_count = mini(i, _light_data.size())
