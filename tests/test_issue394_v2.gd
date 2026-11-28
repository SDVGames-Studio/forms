extends Node
## Regression check for issue #394 rework v4 (owner 2026-11-28): the
## pre-game level setup's team composition is DECOUPLED from the team
## customization menu's roster.
##  - GameConfig.resolve_level_names: the ROSTER members fill first
##    ("if there are N teammates in my team, they should be chosen
##    first"); members past the roster end are "mateK" extras; an
##    unset count falls back to the roster size; the count is capped.
##  - The level setup's member grids edit "level_members" ONLY — the
##    roster names are never touched by the level setup.
##  - The owner's scenario: roster growth in the team menu (a save)
##    never changes the level's counts — they persist with the set,
##    so reopening the level setup keeps the composition.
##  - Start (_prepare_level_sets): the LIVE set the level plays wears
##    the resolved names (roster first, "mateK" extras) while the
##    SAVED set keeps the roster names — the extras never appear in
##    the team customization menu.
##
## Run headless: godot --headless res://tests/test_issue394_v2.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://scenes/menus/LevelConfigMenu.tscn")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE394V2 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	var saved_teams := GameConfig.teams.duplicate(true)
	var saved_menu_sizes := GameConfig.menu_team_sizes

	# ---- resolve_level_names: roster first, mateK extras. ----
	var names := GameConfig.resolve_level_names(
		{"names": ["Alpha", "Beta"], "level_members": 4})
	_check("roster members are chosen first, extras are mateK",
		names == ["Alpha", "Beta", "mate1", "mate2"])
	names = GameConfig.resolve_level_names(
		{"names": ["Alpha", "Beta", "Gamma"], "level_members": 2})
	_check("a smaller count takes the FIRST roster members",
		names == ["Alpha", "Beta"])
	names = GameConfig.resolve_level_names({"names": ["Alpha"]})
	_check("an unset count falls back to the roster size",
		names == ["Alpha"])
	names = GameConfig.resolve_level_names(
		{"names": ["A", "B"], "level_members": 100})
	_check("the count is capped at the grid maximum, extras keep counting",
		names.size() == GameConfig.MAX_LEVEL_TEAM_MEMBERS
		and str(names[2]) == "mate1"
		and str(names[GameConfig.MAX_LEVEL_TEAM_MEMBERS - 1])
				== "mate%d" % (GameConfig.MAX_LEVEL_TEAM_MEMBERS - 2))

	# ---- the level setup: grid edits hit the count, never the roster. ----
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.save_teams()
	var menu := MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var roster: Array = (GameConfig.teams[0]["names"] as Array).duplicate()
	var level_count: int = int(GameConfig.teams[0][GameConfig.LEVEL_MEMBERS_KEY])
	_check("a team's level count starts at its roster size",
		level_count == roster.size())
	menu._add_member(0)
	menu._add_member(0)
	_check("grid appends grow the level count",
		int(GameConfig.teams[0][GameConfig.LEVEL_MEMBERS_KEY])
				== level_count + 2)
	_check("grid appends never touch the roster",
		(GameConfig.teams[0]["names"] as Array) == roster)
	menu._remove_member(0, 0)
	_check("grid removals shrink the level count",
		int(GameConfig.teams[0][GameConfig.LEVEL_MEMBERS_KEY])
				== level_count + 1)

	# ---- the owner's scenario: a team-menu round-trip keeps the counts.
	# (The team menu grows the roster in place and saves — exactly what
	# its Save button does; the level setup then reopens and reloads.)
	(GameConfig.teams[0]["names"] as Array).append("New Mate")
	GameConfig.save_teams()
	GameConfig.teams = []
	GameConfig.load_teams()
	_check("roster growth never changes the level count",
		int(GameConfig.teams[0][GameConfig.LEVEL_MEMBERS_KEY])
				== level_count + 1
		and (GameConfig.teams[0]["names"] as Array).size()
				== roster.size() + 1)
	menu.queue_free()

	# ---- Start: the live set fields the resolved names, the save keeps
	# the roster (the extras never reach the team menu). ----
	GameConfig.teams = [
		{"label": "Heroes", "color": Color(1, 0, 0), "shape": "square",
			"names": ["H1", "H2"], "skill": 5, "friendly_fire": 0,
			"controller": "player", "language": "English",
			"level_members": 4},
	]
	GameConfig.save_teams()
	var menu2 := MenuScene.instantiate()
	add_child(menu2)
	await get_tree().process_frame
	menu2._prepare_level_sets()
	_check("the live set fields the roster first, mate extras past it",
		(GameConfig.teams[0]["names"] as Array)
				== ["H1", "H2", "mate1", "mate2"])
	GameConfig.teams = []
	GameConfig.load_teams()
	_check("the saved set keeps the roster — extras never reach the team menu",
		(GameConfig.teams[0]["names"] as Array) == ["H1", "H2"]
		and int(GameConfig.teams[0][GameConfig.LEVEL_MEMBERS_KEY]) == 4)
	menu2.queue_free()

	GameConfig.menu_team_sizes = saved_menu_sizes
	GameConfig.teams = saved_teams
	DirAccess.remove_absolute("user://team.cfg")

	if _fails.is_empty():
		print("PASS: issue #394 rework v4 — level setup decoupled from the team menu")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % _fails.size())
		get_tree().quit(1)
