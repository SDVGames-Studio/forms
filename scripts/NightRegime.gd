class_name NightRegime
extends Node
## Night regime (issue #367).
##
## Chosen in the level configuration menu before the level starts
## (GameConfig.night_regime). While on, the level plays in total
## darkness:
## - a near-black CanvasModulate tints the whole world canvas, so only
##   lit areas are readable (owner rework 2026-11-07: the shadowed area
##   must be totally dark);
## - every member of the player's team carries a vision field: a wedge
##   of neutral moonlight opening toward the enemy team, shaped like
##   the issue's mock (the mock's green lines only marked the wedge's
##   borders — no circle and nothing green is drawn);
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

## Ambient tint of the world canvas while the night regime is on:
## total darkness (everything outside a light stays unreadable).
const NIGHT_COLOR := Color(0.01, 0.015, 0.03, 1.0)

## How far a figure sees, in world pixels (the mock's wedge reaches
## beyond the screen edge).
const VISION_RADIUS := 300.0

## Half-opening of the vision wedge in radians (≈ 20°; the mock's wedge
## spans roughly from -5° to +20° around the direction to the enemy).
const VISION_HALF_ANGLE := 0.349066

## Moonlight tint of a vision field — neutral white-blue, not green.
const VISION_TINT := Color(0.85, 0.9, 1.0)

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


## A figure's vision field: a wedge of moonlight that opens toward the
## enemy team (the visible-area shape of the issue's mock). The light
## re-aims itself as figures walk, and nothing is drawn on top — no
## green circle, no border lines.
class VisionField:
	extends PointLight2D

	## Seconds between re-aims (the enemy centroid barely moves).
	const _AIM_INTERVAL := 0.25

	## Side length of the shared wedge texture; its sector reaches
	## _SECTOR_TEX_RADIUS pixels from the centre.
	const _SECTOR_TEX_SIZE := 256
	const _SECTOR_TEX_RADIUS := 128.0

	## The shared sector texture (built once, per-pixel).
	static var _sector_texture: ImageTexture = null

	## Vision reach in world pixels.
	var radius := NightRegime.VISION_RADIUS

	var _aim_timer := 0.0


	## Build a configured wedge light. `vision_radius` is in world
	## pixels.
	static func create(vision_radius: float) -> VisionField:
		var field := VisionField.new()
		field.name = "VisionField"
		field.color = NightRegime.VISION_TINT
		field.energy = 1.1
		field.texture = sector_texture()
		# The texture's wedge reaches _SECTOR_TEX_RADIUS px from the
		# centre; scale it to the requested vision radius.
		field.texture_scale = vision_radius / _SECTOR_TEX_RADIUS
		field.radius = vision_radius
		return field


	## The shared wedge texture: a sector of the vision half-angle
	## opening along +X, bright at the figure and fading to nothing at
	## the vision radius (same stops as ShotLight's radial gradient).
	static func sector_texture() -> ImageTexture:
		if _sector_texture != null:
			return _sector_texture
		var img := Image.create_empty(_SECTOR_TEX_SIZE, _SECTOR_TEX_SIZE,
			false, Image.FORMAT_RGBA8)
		var centre := Vector2(_SECTOR_TEX_SIZE / 2.0, _SECTOR_TEX_SIZE / 2.0)
		var half := NightRegime.VISION_HALF_ANGLE
		for y in _SECTOR_TEX_SIZE:
			for x in _SECTOR_TEX_SIZE:
				var offset := Vector2(x + 0.5, y + 0.5) - centre
				var dist := offset.length()
				var alpha := 0.0
				if dist <= _SECTOR_TEX_RADIUS and absf(offset.angle()) <= half:
					# Full brightness for the first 30% of the reach,
					# then a linear fade to transparent at the edge.
					var t := dist / _SECTOR_TEX_RADIUS
					alpha = 1.0 if t <= 0.3 else clampf((1.0 - t) / 0.7, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
		_sector_texture = ImageTexture.create_from_image(img)
		return _sector_texture


	func _ready() -> void:
		_aim()


	func _process(delta: float) -> void:
		# Keep the wedge pointed at the enemy team as figures walk.
		_aim_timer += delta
		if _aim_timer >= _AIM_INTERVAL:
			_aim_timer = 0.0
			_aim()


	## Point the wedge toward the centroid of the enemy team (the
	## direction figures face when they aim at the other side).
	func _aim() -> void:
		var parent := get_parent() as Node2D
		if parent == null:
			return
		var centroid := Vector2.ZERO
		var count := 0
		for enemy in get_tree().get_nodes_in_group("enemy_team"):
			if enemy is Node2D:
				centroid += (enemy as Node2D).global_position
				count += 1
		if count == 0:
			return
		centroid /= count
		var dir := centroid - parent.global_position
		if dir.length_squared() < 1.0:
			return
		global_rotation = dir.angle()
