extends Node2D
## Issue #464 rework: a PLAYABLE level built at runtime from an
## editor-authored level file (user://levels/<name>.json).
##
## The level editor stores its map as plain data — {kind,x,y,w,h}
## ground pieces and {x,y} spawn points in the 1152x648 authoring
## space (see LevelEditorCanvas). The levels menu sends the player
## here with GameConfig.custom_level_name set; this script turns the
## JSON into exactly the nodes the stock levels are authored with:
## IndestructibleGround / DestructibleGround StaticBody2Ds, a player
## team (hero with the shared zoom camera + teammates, each with a
## Weapon) and computer figures on the spawn points — then applies
## the usual pre-game configuration (GameConfig.apply, NightRegime),
## mirroring scripts/LevelConfig.gd on every stock level.
##
## Spawn points fill the figures in team order: hero, teammates, then
## the computer team; a figure without a spawn point falls back to a
## spread along the top of the authoring space (it drops onto the
## ground under gravity, like a new round's paratroopers would).

const FORMAT := "forms-level/1"
const LEVELS_DIR := "user://levels"
## The editor's authoring space — LevelEditorCanvas.CANVAS_SIZE.
const CANVAS_SIZE := Vector2(1152, 648)
## Figure capsule — the authored levels' CircleShape2D_shape.
const BODY_RADIUS := 24.0
const BODY_HEIGHT := 57.6
## Fallback figure line when the JSON has fewer spawns than figures.
const FALLBACK_Y := 120.0

const PlayerScript := preload("res://Player.gd")
const NpcScript := preload("res://Npc.gd")
const WeaponScript := preload("res://Weapon.gd")
const ZoomCameraScript := preload("res://ZoomCamera.gd")
const IndestructibleScript := preload(
	"res://scripts/IndestructibleGround.gd")
const DestructibleScript := preload(
	"res://scripts/DestructibleGround.gd")


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
		# Fallback terrain: the plain floor slab of Level.tscn's world.
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
	for i in pieces.size():
		_add_ground(pieces[i], i)
	var plan := _figure_plan()
	for i in plan.size():
		var at: Vector2 = spawns[i] if i < spawns.size() \
			else Vector2(200.0 + 150.0 * float(i), FALLBACK_Y)
		_add_figure(plan[i], at)


## One ground piece → StaticBody2D with the ground script. The editor
## stores the rect's top-left corner; the levels position bodies by
## their centre.
func _add_ground(raw: Dictionary, index: int) -> void:
	var kind := str(raw.get("kind", "indestructible"))
	var size := Vector2(
		maxf(32.0, float(raw.get("w", 0.0))),
		maxf(32.0, float(raw.get("h", 0.0))))
	var ground := StaticBody2D.new()
	ground.name = "Ground%d" % index
	ground.script = IndestructibleScript \
		if kind == "indestructible" else DestructibleScript
	ground.set("rect_size", size)
	ground.position = Vector2(
		float(raw.get("x", 0.0)), float(raw.get("y", 0.0))) + size * 0.5
	add_child(ground)


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
