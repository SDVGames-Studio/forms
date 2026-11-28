extends Node2D
## Issue #464 rework: a PLAYABLE level built at runtime from an
## editor-authored level file (user://levels/<name>.json).
##
## The level editor stores its map as plain data — {kind, shape, ...}
## ground pieces and {x,y} spawn points in the 1152x648 authoring
## space (see LevelEditorCanvas). Since issue #632 the palette draws
## rectangles, triangles, circles, closed loops and bezier curves;
## this script turns the JSON into exactly the nodes the stock levels
## are authored with: IndestructibleGround / DestructibleGround
## StaticBody2Ds, a player team (hero with the shared zoom camera +
## teammates, each with a Weapon) and computer figures on the spawn
## points — then applies the usual pre-game configuration
## (GameConfig.apply, NightRegime), mirroring scripts/LevelConfig.gd
## on every stock level.
##
## Spawn points fill the figures in team order: hero, teammates, then
## the computer team; a figure without a spawn point falls back to a
## spread along the top of the authoring space (it drops onto the
## ground under gravity, like a new round's paratroopers would).

## Issue #740: per-ground-kind PICTURES plus the level's BACKGROUND
## picture — the level file carries one picture each for
## indestructible ground, destructible ground (with an exact tile
## size and rotation, so a picture smaller than its ground repeats)
## and the background (stretched over the authoring space, drawn
## behind everything). The legacy single "picture" key of #633 still
## loads and fills both ground kinds.
const FORMAT := "forms-level/1"
const LEVELS_DIR := "user://levels"
## The editor's authoring space — LevelEditorCanvas.CANVAS_SIZE.
const CANVAS_SIZE := Vector2(1152, 648)
## Figure capsule — the authored levels' CircleShape2D_shape.
const BODY_RADIUS := 24.0
const BODY_HEIGHT := 57.6
## Fallback figure line when the JSON has fewer spawns than figures.
const FALLBACK_Y := 120.0

const PlayerScript := preload("res://scripts/Player.gd")
const NpcScript := preload("res://scripts/Npc.gd")
const WeaponScript := preload("res://scripts/Weapon.gd")
const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")
const IndestructibleScript := preload(
	"res://scripts/IndestructibleGround.gd")
const DestructibleScript := preload(
	"res://scripts/DestructibleGround.gd")
const EditorCanvas := preload("res://scripts/LevelEditorCanvas.gd")
## Issue #632: how finely a circle piece becomes a polygon disc.
const DISC_SEGMENTS := 32

## Issue #740: the level's pictures, decoded once — the ground kinds'
## textures, their tile sizes and rotations, and the background.
var _ground_pictures := {}
var _ground_picture_sizes := {}
var _ground_picture_rotations := {}
var _background_picture: Texture2D = null


func _ready() -> void:
	_build(GameConfig.custom_level_name)
	GameConfig.apply(self)
	# Issue #367: the night regime applies to custom levels as well.
	if GameConfig.night_regime:
		NightRegime.apply(self)
	# Issue #523: the spawn regime applies to custom levels as well —
	# the designer regime is their default (the editor's JSON spawn
	# points already staged the figures); the random regimes scatter
	# them over the generated terrain like in any stock level.
	SpawnRegime.apply(self)


## The figure plan, in GameConfig.apply order: the hero + teammates
## the player team is trimmed to, then the computer team. [node name,
## is NPC, display name].
static func _figure_plan() -> Array:
	return [
		["Player", false, "Player 1"],
		["Teammate1", false, "Player 2"],
		["Teammate2", false, "Player 3"],
		["Npc", true, "Enemy 1"],
		["Npc2", true, "Enemy 2"],
		["Npc3", true, "Enemy 3"],
	]


## Parse the level file; an empty dictionary means "missing/broken —
## use the fallback terrain" (a custom level must never hard-crash
## the game over a bad file).
static func _load_level(stem: String) -> Dictionary:
	if stem.is_empty():
		return {}
	var path := "%s/%s.json" % [LEVELS_DIR, stem]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY \
			or str((parsed as Dictionary).get("format", "")) != FORMAT:
		return {}
	return parsed


func _build(stem: String) -> void:
	var level := _load_level(stem)
	var pieces: Array = []
	var spawns: Array = []
	if level.is_empty():
		# Fallback terrain: the plain floor slab of Level1.tscn's world.
		pieces.append({"kind": "indestructible",
				"x": 0.0, "y": CANVAS_SIZE.y - 72.0,
				"w": CANVAS_SIZE.x, "h": 448.0})
	else:
		for raw in level.get("pieces", []):
			if typeof(raw) == TYPE_DICTIONARY:
				pieces.append(raw)
		for raw in level.get("spawns", []):
			if typeof(raw) == TYPE_DICTIONARY:
				spawns.append(Vector2(
					float(raw.get("x", 0.0)), float(raw.get("y", 0.0))))
	# Issue #740: the ground kinds' pictures and the background.
	_load_pictures(level)
	for i in pieces.size():
		_add_ground(pieces[i], i)
	var plan := _figure_plan()
	for i in plan.size():
		var at: Vector2 = spawns[i] if i < spawns.size() \
			else Vector2(200.0 + 150.0 * float(i), FALLBACK_Y)
		_add_figure(plan[i], at)


## One ground piece → StaticBody2D with the ground script. Issue
## #632: the palette's shapes build on the forms the ground scripts
## already support — discs (IndestructibleGround.radius, #190) and
## polygons (DestructibleGround.polygon, #376; IndestructibleGround
## .polygon, #632). A missing shape key is a legacy #464 rectangle.
func _add_ground(raw: Dictionary, index: int) -> void:
	var kind := str(raw.get("kind", "indestructible"))
	match str(raw.get("shape", "rect")):
		"circle":
			_add_circle_ground(raw, index, kind)
		"tri":
			_add_triangle_ground(raw, index, kind)
		"loop":
			_add_world_polygon(_read_points(raw), index, kind)
		"curve":
			_add_world_polygon(_curve_strip(_read_points(raw)),
				index, kind)
		_:
			_add_rect_ground(raw, index, kind)


## A bare ground body named for its piece index.
func _make_ground(kind: String, index: int) -> StaticBody2D:
	var ground := StaticBody2D.new()
	ground.name = "Ground%d" % index
	ground.script = IndestructibleScript \
		if kind == "indestructible" else DestructibleScript
	# Issue #740: the ground kinds carry their OWN picture, with its
	# exact tile size and rotation (a zero size stretches over the
	# form's bounds — the legacy #633 look).
	var tex: Texture2D = _ground_pictures.get(kind)
	if tex != null:
		ground.set("picture", tex)
		var size: Vector2 = _ground_picture_sizes.get(kind, Vector2.ZERO)
		if size.x > 0.0 and size.y > 0.0:
			ground.set("picture_size", size)
		ground.set("picture_rotation",
				float(_ground_picture_rotations.get(kind, 0.0)))
	return ground


## Legacy rectangle piece. The editor stores the rect's top-left
## corner; the levels position bodies by their centre.
func _add_rect_ground(raw: Dictionary, index: int, kind: String) -> void:
	var size := Vector2(
		maxf(32.0, float(raw.get("w", 0.0))),
		maxf(32.0, float(raw.get("h", 0.0))))
	var ground := _make_ground(kind, index)
	ground.set("rect_size", size)
	ground.position = Vector2(
		float(raw.get("x", 0.0)), float(raw.get("y", 0.0))) + size * 0.5
	add_child(ground)


## Circle piece — the dragged box's inscribed disc. Indestructible
## ground uses the native disc (a real CircleShape2D, exact gravity);
## destructible ground becomes a polygon disc chunk (#376 carving).
func _add_circle_ground(raw: Dictionary, index: int, kind: String) -> void:
	var size := Vector2(
		maxf(32.0, float(raw.get("w", 0.0))),
		maxf(32.0, float(raw.get("h", 0.0))))
	var radius := minf(size.x, size.y) * 0.5
	var center := Vector2(
		float(raw.get("x", 0.0)), float(raw.get("y", 0.0))) + size * 0.5
	if kind == "indestructible":
		var disc := _make_ground(kind, index)
		disc.set("radius", radius)
		disc.position = center
		add_child(disc)
	else:
		_add_polygon_ground(_disc_polygon(radius), center, index, kind)


## Triangle piece — an upward-pointing triangle inscribed in the box
## (base on the box's bottom edge, apex on its top edge).
func _add_triangle_ground(raw: Dictionary, index: int, kind: String) -> void:
	var size := Vector2(
		maxf(32.0, float(raw.get("w", 0.0))),
		maxf(32.0, float(raw.get("h", 0.0))))
	var center := Vector2(
		float(raw.get("x", 0.0)), float(raw.get("y", 0.0))) + size * 0.5
	var half := size * 0.5
	_add_polygon_ground(PackedVector2Array([
		Vector2(-half.x, half.y),
		Vector2(half.x, half.y),
		Vector2(0.0, -half.y),
	]), center, index, kind)


## A world-space polygon piece (loop vertices, a curve's ground
## ribbon): centred on its vertex mean, built as local polygon(s).
func _add_world_polygon(world: PackedVector2Array,
		index: int, kind: String) -> void:
	if world.size() < 3:
		return
	var centroid := Vector2.ZERO
	for p in world:
		centroid += p
	centroid /= float(world.size())
	var local := PackedVector2Array()
	for p in world:
		local.append(p - centroid)
	_add_polygon_ground(local, centroid, index, kind)


## Issue #633: decode the level file's embedded ground picture (a
## base64 PNG chosen in the editor); null when absent or unreadable
## (a broken picture must never break the level — flat colors stay).
static func _picture_texture(level: Dictionary) -> Texture2D:
	var raw = level.get("picture", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var b64 := str((raw as Dictionary).get("png", ""))
	if b64.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(
				Marshalls.base64_to_raw(b64)) != OK:
		return null
	return ImageTexture.create_from_image(image)


## Issue #740: the level's background picture, stretched over the
## authoring space behind everything (a parent's own drawing renders
## under all its children). Null = the plain backdrop.
func _draw() -> void:
	if _background_picture != null:
		draw_texture_rect(_background_picture,
			Rect2(Vector2.ZERO, CANVAS_SIZE), false)


## Issue #740: the level's background picture (for tests and
## callers); null when the level has none.
func background_picture() -> Texture2D:
	return _background_picture


## Issue #740: decode the level file's pictures — one per ground kind
## (with its exact tile size and rotation) plus the background; a
## legacy #633 single "picture" fills both ground kinds. A broken
## entry quietly drops to flat colors (never break the level).
func _load_pictures(level: Dictionary) -> void:
	_ground_pictures = {}
	_ground_picture_sizes = {}
	_ground_picture_rotations = {}
	_background_picture = null
	var raw_pics = level.get("pictures", null)
	if typeof(raw_pics) == TYPE_DICTIONARY:
		for kind in ["indestructible", "destructible"]:
			var raw = (raw_pics as Dictionary).get(kind, {})
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var tex := _entry_texture(raw)
			if tex == null:
				continue
			_ground_pictures[kind] = tex
			_ground_picture_sizes[kind] = Vector2(
				float((raw as Dictionary).get("w", 0.0)),
				float((raw as Dictionary).get("h", 0.0)))
			_ground_picture_rotations[kind] = \
					float((raw as Dictionary).get("rot", 0.0))
		var raw_bg = (raw_pics as Dictionary).get("background", {})
		if typeof(raw_bg) == TYPE_DICTIONARY:
			_background_picture = _entry_texture(raw_bg)
	else:
		# Legacy #633: one picture for both ground kinds.
		var legacy := _picture_texture(level)
		if legacy != null:
			for kind in ["indestructible", "destructible"]:
				_ground_pictures[kind] = legacy
	if _background_picture != null:
		queue_redraw()


## Issue #740: decode one level-file picture entry; null when absent
## or unreadable.
static func _entry_texture(raw: Dictionary) -> Texture2D:
	var b64 := str(raw.get("png", ""))
	if b64.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(
				Marshalls.base64_to_raw(b64)) != OK:
		return null
	return ImageTexture.create_from_image(image)


## A local-space polygon ground. Indestructible ground keeps it whole
## (LevelTerrain reads the polygon; static collision decomposes concave
## loops by itself). Destructible chunks carve exactly when CONVEX
## (#376), so a concave polygon is triangulated into convex parts —
## a failed triangulation falls back to the convex hull.
func _add_polygon_ground(local: PackedVector2Array, at: Vector2,
		index: int, kind: String) -> void:
	if local.size() < 3:
		return
	if kind == "indestructible":
		var ground := _make_ground(kind, index)
		ground.set("polygon", local)
		ground.position = at
		add_child(ground)
		return
	var parts: Array = []
	if _is_convex(local):
		parts = [local]
	else:
		# This Godot's triangulate_polygon returns flat VERTEX INDICES,
		# three per triangle — collect the triangles themselves.
		var ids := Geometry2D.triangulate_polygon(local)
		for i in range(0, ids.size() - 2, 3):
			parts.append(PackedVector2Array([
				local[ids[i]], local[ids[i + 1]], local[ids[i + 2]]]))
	if parts.is_empty():
		parts = [Geometry2D.convex_hull(local)]
	# Issue #633: destructible pieces of ONE authored polygon share the
	# whole polygon's picture mapping, so the picture stays continuous
	# across the split (all parts share the same local frame).
	var pic_origin := Vector2.ZERO
	var pic_span := Vector2.ZERO
	if kind != "indestructible" \
			and _ground_pictures.get("destructible") != null:
		var aabb := Rect2(local[0], Vector2.ZERO)
		for p in local:
			aabb = aabb.expand(p)
		pic_origin = aabb.position
		pic_span = aabb.size
	for j in parts.size():
		var part: PackedVector2Array = parts[j]
		if part.size() < 3:
			continue
		var ground := _make_ground(kind, index)
		if parts.size() > 1:
			ground.name = "Ground%d_%d" % [index, j]
		ground.set("polygon", part)
		if pic_span != Vector2.ZERO:
			ground.set("picture_origin", pic_origin)
			ground.set("picture_span", pic_span)
		ground.position = at
		add_child(ground)


## A curve piece — the quadratic bezier's ground ribbon, sampled with
## the editor's own strip math (click order [start, end, bend]).
func _curve_strip(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() != 3:
		return PackedVector2Array()
	return EditorCanvas.curve_strip_polygon(
		points, EditorCanvas.CURVE_THICKNESS)


## The "points": [{x, y}, ...] of a loop/curve piece.
static func _read_points(raw: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in raw.get("points", []):
		if typeof(p) == TYPE_DICTIONARY:
			points.append(Vector2(
				float((p as Dictionary).get("x", 0.0)),
				float((p as Dictionary).get("y", 0.0))))
	return points


## A regular polygon disc of `radius` (the circle piece's chunky
## destructible twin — convex, so #376 carving stays exact).
static func _disc_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in DISC_SEGMENTS:
		var a := TAU * float(i) / float(DISC_SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points


## True when the polygon's edge cross products all keep one sign.
static func _is_convex(points: PackedVector2Array) -> bool:
	var side := 0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var c := points[(i + 2) % points.size()]
		var cross := (b.x - a.x) * (c.y - b.y) \
				- (b.y - a.y) * (c.x - b.x)
		var s := 1 if cross > 0.0 else (-1 if cross < 0.0 else 0)
		if s == 0:
			continue
		if side == 0:
			side = s
		elif s != side:
			return false
	return true


## One figure on a spawn point. Player figures get the authored
## children (capsule shape, team-colored visual, the hero carries the
## shared zoom camera) and every player figure a Weapon; NPCs build
## their own insides (see Npc.gd). The Weapon stays the LAST child so
## it draws in front of the body (issue #282).
func _add_figure(slot: Array, at: Vector2) -> void:
	var figure := CharacterBody2D.new()
	figure.name = slot[0]
	figure.position = at
	figure.script = NpcScript if slot[1] else PlayerScript
	figure.set("display_name", slot[2])
	if not slot[1]:
		figure.collision_layer = 8
		figure.collision_mask = 1
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var capsule := CapsuleShape2D.new()
		capsule.radius = BODY_RADIUS
		capsule.height = BODY_HEIGHT
		shape.shape = capsule
		figure.add_child(shape)
		var visual := ColorRect.new()
		visual.name = "Visual"
		visual.position = Vector2(-32.0, -32.0)
		visual.size = Vector2(64.0, 64.0)
		visual.color = GameConfig.team_color
		figure.add_child(visual)
		if slot[0] == "Player":
			var camera := Camera2D.new()
			camera.name = "Camera"
			camera.script = ZoomCameraScript
			camera.position_smoothing_enabled = true
			camera.position_smoothing_speed = 8.0
			camera.zoom = Vector2(0.5, 0.5)
			figure.add_child(camera)
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.script = WeaponScript
	figure.add_child(weapon)
	add_child(figure)
