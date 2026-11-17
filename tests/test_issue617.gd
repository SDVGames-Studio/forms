extends Node
## Issue #617: all levels share ONE character structure.
##
##  1. the renamed level files exist (Level1/Level6/Level7) and the old
##     file names are gone;
##  2. every staged figure in every level is a PLAIN Character.gd body
##     named Team<N>mate<M> with NO child nodes;
##  3. run directly (defaults) a level fields COMPUTERS only — no human
##     figure exists — and the level's shared camera is there, hosted
##     by a figure;
##  4. the default camera type is the GLOBAL camera;
##  5. opting the first team in as "player" (the level menu choice)
##     dresses its figures as human Player.gd figures.
##
## Rework v2 (owner 2026-11-17: "one Player and one computer" — the
## defaults must be 3 teams × 2 mates, all computer):
##  6. a direct default run fields exactly THREE teams of TWO mates
##     each (counted by team color), every one computer-played;
##  7. a pre-rework team.cfg (no version stamp — written by the old
##     defaults with a PLAYER first team) is replaced by the fresh
##     defaults on load, so running any level fields 3×2 computers.
##
## Run headless: godot --headless res://tests/test_issue617.tscn
## Exit code 0 = pass.

const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")
const CharacterScript := preload("res://scripts/Character.gd")

const LEVELS: Array[String] = [
	"res://scenes/levels/Level1.tscn", "res://scenes/levels/Level2.tscn",
	"res://scenes/levels/Level3.tscn", "res://scenes/levels/Level4.tscn",
	"res://scenes/levels/Level5.tscn", "res://scenes/levels/Level6.tscn",
	"res://scenes/levels/Level7.tscn",
]
const GONE: Array[String] = [
	"res://scenes/levels/Level.tscn", "res://scenes/levels/LevelDuel.tscn",
	"res://scenes/levels/LevelDuelBig.tscn",
]

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])


## The uniform staging name Team<N>mate<M> parsed to [team, member]
## (both 1-based) — empty when the name is not in the uniform format.
func _slot(figure_name: String) -> Array:
	if not figure_name.begins_with("Team"):
		return []
	var mate := figure_name.find("mate")
	if mate < 0:
		return []
	var team := figure_name.substr(4, mate - 4).to_int()
	var member := figure_name.substr(mate + 4).to_int()
	if team < 1 or member < 1:
		return []
	return [team, member]


func _ready() -> void:
	# --- 1. The renames. ---
	for path in GONE:
		_check(not ResourceLoader.exists(path), "%s is gone" % path)
	for path in LEVELS:
		_check(ResourceLoader.exists(path), "%s exists" % path)

	# --- 4. The default camera type is GLOBAL (check before any play). ---
	_check(ZoomCameraScript.camera_mode == ZoomCameraScript.MODE_GLOBAL,
			"default camera type is GLOBAL")

	# --- 2. The uniform staging structure (pure scene check). ---
	for path in LEVELS:
		var level: Node = (load(path) as PackedScene).instantiate()
		var figures := 0
		for child in level.get_children():
			if child is CharacterBody2D:
				figures += 1
				_check(_slot(str(child.name)).size() == 2,
						"%s/%s is named Team<N>mate<M>" % [path, child.name])
				_check(child.get_script() == CharacterScript,
						"%s/%s is a plain Character.gd body" % [path, child.name])
				_check(child.get_child_count() == 0,
						"%s/%s has no child nodes" % [path, child.name])
		_check(figures >= 2, "%s stages at least two figures" % path)
		level.free()

	# --- 3. A direct run fields computers only + the shared camera. ---
	# Rework v2: simulate the owner's fresh direct run — no team.cfg,
	# unset classic counts, no menu flag.
	DirAccess.remove_absolute("user://team.cfg")
	GameConfig.teams = []
	GameConfig.team_size = 0
	GameConfig.enemy_count = 0
	GameConfig.menu_team_sizes = false
	var level1: Node = (load("res://scenes/levels/Level1.tscn")
			as PackedScene).instantiate()
	add_child(level1)
	for i in 30:
		await get_tree().physics_frame
	var humans := 0
	var computers := 0
	var by_color := {}
	for group in ["player_team", "enemy_team"]:
		for figure in get_tree().get_nodes_in_group(group):
			if figure.has_method("set_controlled"):
				humans += 1
			else:
				computers += 1
				var c = figure.get("team_color")
				if c is Color:
						by_color[c] = int(by_color.get(c, 0)) + 1
	_check(humans == 0 and computers > 0,
			"direct run fields computers only (humans=%d computers=%d)"
			% [humans, computers])
	# --- 6. Rework v2: the defaults field 3 teams × 2 mates exactly. ---
	var pairs := true
	for color in by_color:
		pairs = pairs and int(by_color[color]) == 2
	_check(by_color.size() == 3 and pairs,
			"default run fields 3 teams × 2 mates (teams=%d counts=%s)"
			% [by_color.size(), str(by_color.values())])
	var camera := get_tree().get_first_node_in_group("player_camera")
	_check(camera != null and is_instance_valid(camera),
			"the level's shared camera exists")
	_check(camera != null and camera.get_parent() is CharacterBody2D,
			"the shared camera is hosted by a figure")
	level1.queue_free()
	for i in 5:
		await get_tree().physics_frame

	# --- 7. Rework v2: a pre-rework team.cfg resets to the defaults. ---
	var stale := ConfigFile.new()
	stale.set_value("teams", "set", [
		{"label": "Team 1", "color": Color(1, 0.84, 0.2), "shape": "square",
			"names": ["Player 1", "Player 2", "Player 3"], "skill": 5,
			"friendly_fire": 0, "controller": "player"},
		{"label": "Team 2", "color": Color(0.75, 0.2, 0.45), "shape": "circle",
			"names": ["Member 1", "Member 2", "Member 3"], "skill": 5,
			"friendly_fire": 0, "controller": "computer"},
	])
	stale.save("user://team.cfg")
	GameConfig.teams = []
	GameConfig.load_teams()
	_check(GameConfig.teams.size() == 3
			and GameConfig.team_controller(0) == "computer"
			and (GameConfig.teams[0]["names"] as Array).size() == 2,
			"a pre-rework team.cfg (no version stamp) resets to the 3×2 all-computer defaults")
	DirAccess.remove_absolute("user://team.cfg")

	# --- 5. Opting the first team in dresses a human figure. ---
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	GameConfig.team_size = 0
	GameConfig.enemy_count = 0
	GameConfig.menu_team_sizes = false
	var level6: Node = (load("res://scenes/levels/Level6.tscn")
			as PackedScene).instantiate()
	add_child(level6)
	for i in 30:
		await get_tree().physics_frame
	var human_found := false
	for figure in get_tree().get_nodes_in_group("player_team"):
		if figure.has_method("set_controlled"):
			human_found = true
	_check(human_found, "the opted-in first team dresses a human figure")
	level6.queue_free()
	await get_tree().physics_frame

	if _failures.is_empty():
		print("ISSUE617 PASS")
	else:
		for failure in _failures:
			print("ISSUE617 FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
