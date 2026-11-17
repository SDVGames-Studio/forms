extends Node
## Regression check for issue #537 rework v4 (owner report 2026-11-14:
## "I choose 4 teammates in one team and one in the second team. But
## when I start the level there were 3 teammates in the first team and
## two in the second").
##
## The team set must drive the level's team sizes on EVERY start path,
## not only through the level-config menu's Start:
##  - A classic/direct start (menu_team_sizes=false — duel buttons,
##    editor preview, fresh boot) with a saved 4/1 set fields 4/1:
##    the old sync truncated member_names to its previous size (a 4th
##    teammate never registered) and never synced enemy_count (stale
##    default 2) — exactly the owner's 3/2.
##  - Explicit classic overrides (tests, tools) still survive the
##    implicit load in apply().
##  - _sync_from_teams mirrors the set exactly — it can GROW and SHRINK
##    team_size/enemy_count/member_names.
##  - A level staging fewer than three player figures (duel-style)
##    still fields the full configured count.
##  - The menu path (menu_team_sizes=true) keeps fielding exactly the
##    picked counts on the REAL Level1.tscn.
##
## Run headless: godot --headless res://tests/test_issue537_v4.tscn
## Exit code 0 = pass.

var _fails: Array = []

const HERO_COLOR := Color(1, 0.84, 0.2)
const FOE_COLOR := Color(0.75, 0.2, 0.45)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE537V4 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var saved_teams := GameConfig.teams.duplicate(true)
	var saved_menu := GameConfig.menu_team_sizes

	# ---- 1) the owner's case: classic start follows the SAVED set ----
	# Persist a 4/1 set, then simulate a FRESH BOOT (empty teams, unset
	# classic counts) and start a level directly — no menu, no flag.
	GameConfig.teams = _set_4_1()
	GameConfig.save_teams()
	GameConfig.teams = []
	GameConfig.team_size = 0
	GameConfig.enemy_count = 0
	GameConfig.menu_team_sizes = false
	var level := _stage_standard_cast()
	add_child(level)
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("classic start fields the configured 4 heroes",
		_live_count(get_tree(), "player_team", HERO_COLOR) == 4)
	_check("classic start fields the configured 1 foe",
		_live_count(get_tree(), "enemy_team", FOE_COLOR) == 1)
	level.queue_free()
	await get_tree().process_frame

	# ---- 2) explicit classic overrides survive the implicit load ----
	GameConfig.teams = []
	GameConfig.team_size = 2
	GameConfig.enemy_count = 1
	GameConfig.menu_team_sizes = false
	level = _stage_standard_cast()
	add_child(level)
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("explicit team_size=2 survives the implicit set load",
		_live_count(get_tree(), "player_team", HERO_COLOR) == 2)
	_check("explicit enemy_count=1 survives the implicit set load",
		_live_count(get_tree(), "enemy_team", FOE_COLOR) == 1)
	level.queue_free()
	await get_tree().process_frame

	# ---- 3) _sync_from_teams mirrors the set exactly ----
	GameConfig.teams = _set_4_1()
	GameConfig._sync_from_teams()
	_check("sync grows team_size to 4", GameConfig.team_size == 4)
	_check("sync syncs enemy_count to 1", GameConfig.enemy_count == 1)
	_check("sync mirrors every member name",
		GameConfig.member_names.size() == 4)
	(GameConfig.teams[0]["names"] as Array).resize(1)
	(GameConfig.teams[1]["names"] as Array).resize(3)
	GameConfig._sync_from_teams()
	_check("sync shrinks team_size to 1", GameConfig.team_size == 1)
	_check("sync grows enemy_count to 3", GameConfig.enemy_count == 3)

	# ---- 4) duel-style cast: fewer staged heroes than configured ----
	GameConfig.teams = _set_4_1()
	GameConfig._sync_from_teams()
	GameConfig.menu_team_sizes = false
	level = Node2D.new()
	add_child(level)
	var hero := _stage_figure(level, "Player", "res://scripts/Player.gd",
			HERO_COLOR, "square")
	hero.position = Vector2(100, 100)
	# The duel casts stage an Npc on the PLAYER side (team="player",
	# issue #121) plus a plain foe.
	var blue := _stage_figure(level, "BlueAI", "res://scripts/Npc.gd",
			HERO_COLOR, "square")
	blue.set("team", "player")
	_stage_figure(level, "RedAI", "res://scripts/Npc.gd", FOE_COLOR, "circle")
	GameConfig.apply(level)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("duel-style cast still fields the configured 4 heroes",
		_live_count(get_tree(), "player_team", HERO_COLOR) == 4)
	_check("duel-style cast still fields the configured 1 foe",
		_live_count(get_tree(), "enemy_team", FOE_COLOR) == 1)
	level.queue_free()
	await get_tree().process_frame

	# ---- 5) the menu path on the REAL first level ------------------
	GameConfig.teams = _set_4_1()
	GameConfig.menu_team_sizes = true
	var real: Node = (load("res://scenes/levels/Level1.tscn") as PackedScene).instantiate()
	add_child(real)
	for i in 4:
		await get_tree().process_frame
	_check("menu start fields the picked 4 heroes (real Level1.tscn)",
		_live_count(get_tree(), "player_team", HERO_COLOR) == 4)
	_check("menu start fields the picked 1 foe (real Level1.tscn)",
		_live_count(get_tree(), "enemy_team", FOE_COLOR) == 1)
	real.queue_free()
	for i in 2:
		await get_tree().process_frame

	# ---- restore the environment for anything running after us -----
	GameConfig.menu_team_sizes = saved_menu
	GameConfig.teams = saved_teams
	GameConfig._sync_from_teams()
	GameConfig.save_teams()

	if _fails.is_empty():
		print("PASS: issue #537 team counts follow the set on every path")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % _fails.size())
		get_tree().quit(1)


func _set_4_1() -> Array:
	return [
		{"label": "Team 1", "color": HERO_COLOR, "shape": "square",
			"names": ["H1", "H2", "H3", "H4"], "skill": 5,
			"friendly_fire": 0, "controller": "player", "language": "English"},
		{"label": "Team 2", "color": FOE_COLOR, "shape": "circle",
			"names": ["F1"], "skill": 5,
			"friendly_fire": 0, "controller": "computer", "language": "English"},
	]


## The standard staged cast: hero + two teammates + three NPCs.
func _stage_standard_cast() -> Node2D:
	var level := Node2D.new()
	var names := ["Player", "Teammate1", "Teammate2", "Npc", "Npc2", "Npc3"]
	for node_name: String in names:
		var script := "res://scripts/Npc.gd" if node_name.begins_with("Npc") \
				else "res://scripts/Player.gd"
		_stage_figure(level, node_name, script, HERO_COLOR, "square")
	return level


func _stage_figure(level: Node2D, node_name: String, script_path: String,
		color: Color, shape: String) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = node_name
	body.set_script(load(script_path))
	body.set("team_color", color)
	body.set("team_shape", shape)
	body.set("display_name", node_name)
	level.add_child(body)
	return body


func _live_count(tree: SceneTree, group: String, color: Variant) -> int:
	var count := 0
	for figure in tree.get_nodes_in_group(group):
		if figure == null or figure.is_queued_for_deletion():
			continue
		if color == null or figure.get("team_color") == color:
			count += 1
	return count
