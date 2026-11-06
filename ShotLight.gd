class_name ShotLight
extends PointLight2D
## Lighting effect for weapon shots (issue #368).
##
## A radial light that travels with a projectile (or flashes at a muzzle
## or an explosion). In Godot 4 a PointLight2D only shows in scenes that
## carry a CanvasModulate — these levels have none — so every ShotLight
## also carries a soft additive-glow sprite: the shot visibly glows in
## ANY level, and in a darkened scene the same node lights the real
## terrain around it. No assets: the radial texture is built in code and
## shared by every instance.

## Radius in pixels the light/glow reaches from its centre.
var radius := 96.0
## 0 = steady light; 0..0.4 = sinusoidal energy wobble (rocket exhaust).
var flicker := 0.0

var _glow: Sprite2D = null
var _base_energy := 1.5
var _time := 0.0

## Radial white->transparent gradient shared by every ShotLight.
static var _radial_texture: GradientTexture2D = null


## Build a configured light. `light_radius` is in world pixels; `wobble`
## > 0 makes the energy flicker (see _process).
static func create(color: Color, light_radius := 96.0, energy := 1.5,
		glow := true, wobble := 0.0) -> ShotLight:
	var light := ShotLight.new()
	light.color = color
	light.radius = light_radius
	light.energy = energy
	light._base_energy = energy
	light.flicker = wobble
	light.texture = radial_texture()
	# The texture is 256 px wide, so scale = radius / 128 covers 2*radius.
	light.texture_scale = light_radius / 128.0
	if glow:
		light._glow = Sprite2D.new()
		light._glow.name = "Glow"
		light._glow.texture = radial_texture()
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		light._glow.material = mat
		light._glow.modulate = Color(color, 0.5)
		light._glow.scale = Vector2.ONE * (light_radius / 128.0)
		light.add_child(light._glow)
	return light


## The shared radial gradient (white core fading to transparent).
static func radial_texture() -> GradientTexture2D:
	if _radial_texture == null:
		var gradient := Gradient.new()
		# Gradient.new() ships two default stops — REPLACE them wholesale.
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.gradient = gradient
		_radial_texture = texture
	return _radial_texture


## Explosion / muzzle flash: spawn under `parent` at `at`, then fade.
static func flash(parent: Node, at: Vector2, color: Color,
		light_radius: float, energy := 3.0, duration := 0.4) -> ShotLight:
	var light := ShotLight.create(color, light_radius, energy, true, 0.3)
	parent.add_child(light)
	light.global_position = at
	light.fade(duration)
	return light


## Fade the light (and its glow) out over `duration` seconds, then free.
## The node must already be inside the scene tree.
func fade(duration: float) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "energy", 0.0, duration)
	if _glow != null:
		tween.tween_property(_glow, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	if flicker <= 0.0:
		set_process(false)
		return
	_time += delta
	energy = _base_energy * (1.0 + flicker * sin(_time * 30.0))
