class_name NightRegime
extends Node
## Night regime (issue #367).
##
## Chosen in the level configuration menu before the level starts
## (GameConfig.night_regime). While on, the level plays in darkness:
## - a CanvasModulate tints the whole world canvas dark, so only lit
##   areas are readable;
## - every member of the player's team carries a vision field — a
##   soft moonlight circle rimmed by a green line (the green boundary
##   from the issue's mock) that travels with the figure;
## - every other light source is already a ShotLight (issue #368):
##   muzzle flashes, projectiles, mines, explosions. In a darkened
##   canvas those PointLight2Ds genuinely light the terrain around
##   them, so a shot fired beyond the player's vision reveals itself
##   as a flash and whatever that flash lit — nothing else is lit.
##
## The manager is added once per level via NightRegime.apply(level);
## figures are pre-placed in the level scenes, so vision lights are
## attached once when the level starts (a deferred pass, after
## GameConfig.apply trimmed the teams down to the chosen sizes).

## Ambient tint of the world canvas while the night regime is on.
const NIGHT_COLOR := Color(0.20, 0.22, 0.32, 1.0)

## How far a figure sees, in world pixels (≈ five figure widths).
const VISION_RADIUS := 300.0

## Moonlight tint of a vision field (greenish, matching the rim).
const VISION_TINT := Color(0.62, 0.92, 0.68)

## Color of the vision-field boundary line.
const RIM_COLOR := Color(0.35, 0.95, 0.45, 0.9)

var level_root: Node = null


## Turn the night regime on for `level`: darken the world canvas and
## give every player-team figure a vision field. Called from
## LevelConfig._ready when GameConfig.night_regime is on.
static func apply(level: Node) -> NightRegime:
	var night := NightRegime.new()
	night.name = "NightRegime"
	night.level_root = level
	level.add_child(night)
	return night


func _ready() -> void:
	# The modulate lives on the level's world canvas: it darkens the
	# terrain and the figures, while menu/HUD canvas layers above stay
	# readable. A CanvasModulate also switches ShotLight nodes from
	# decorative glows to actual light sources.
	var modulate := CanvasModulate.new()
	modulate.name = "NightModulate"
	modulate.color = NIGHT_COLOR
	level_root.add_child(modulate)
	# Figures joined their groups in their own _ready (children are
	# ready before the level root); defer so GameConfig.apply's
	# queue_free()d extras can never race the pass.
	_attach_vision_lights.call_deferred()


## Give every current member of the player's team a vision field.
## Enemy figures deliberately get none — in the night regime the
## player sees their teammates only.
func _attach_vision_lights() -> void:
	for member in get_tree().get_nodes_in_group("player_team"):
		if member is Node and member.get_node_or_null(NodePath("VisionField")) == null:
			member.add_child(VisionField.create(VISION_RADIUS))


## A figure's vision field: soft green-tinted moonlight with a green
## boundary ring drawn at its edge (the green lines of the mock).
class VisionField:
	extends PointLight2D

	func _init() -> void:
		texture = ShotLight.radial_texture()

	static func create(radius: float) -> VisionField:
		var field := VisionField.new()
		field.name = "VisionField"
		field.color = NightRegime.VISION_TINT
		field.energy = 1.1
		field.texture_scale = radius / 128.0
		field.radius = radius
		return field

	## Vision reach in world pixels (used to place the rim ring).
	var radius := NightRegime.VISION_RADIUS

	func _draw() -> void:
		# The green boundary line of the vision field, just inside the
		# lit circle so it stays readable against the darkness.
		draw_arc(Vector2.ZERO, radius * 0.97, 0.0, TAU, 96,
			NightRegime.RIM_COLOR, 2.0, true)
