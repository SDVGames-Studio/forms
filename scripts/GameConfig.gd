extends Object
class_name GameConfig
## Level configuration chosen before a level begins (issue #137).
##
## The levels menu stores the picked level here, the level configuration
## menu fills the options in, and each playable level applies the settings
## in _ready (via LevelConfig.gd attached to the level root).

## Path of the level the player picked in the levels menu.
static var level_path := ""

## Members of the player's team including the hero (1..3; the scenes
## pre-place the hero plus Teammate1/Teammate2).
static var team_size := 3

## Number of computer opponents (1..3; the scenes pre-place Npc..Npc3).
static var enemy_count := 2

## Issue #180: AI behavior parameters belong to the TEAM configuration
## (edited in the team menu), not to the level configuration.

## AI skill: 0..10. Mapped onto the NPC difficulty bands — 0..3 = easy,
## 4..7 = normal, 8..10 = hard (aim slew speed + pause between shots).
static var ai_skill := 5

## AI friendly-fire: 0 = the computer ALWAYS avoids friendly fire,
## 10 = it does not care at all (in between the avoidance checks are
## applied probabilistically per shot).
static var ai_friendly_fire := 0

## Issue #192: per-turn time limit in seconds, set in the level
## configuration menu and read by TurnController when a turn starts.
static var turn_time := 30.0

## Issue #169: player team customisation, edited in the team menu and
## persisted to user://team.cfg. Since issue #208 the menu edits the
## whole set of teams (see `teams` below); these single-team fields stay
## the runtime source every level applies.

## Team color of the player's figures (also used for the turn banner).
static var team_color := Color(1, 0.84, 0.2, 1)

## Shape of the player's figures: square, circle, triangle, star or ellipse.
static var team_shape := "square"

## Names of the team members (index 0 is the hero).
static var member_names: Array[String] = ["Player 1", "Player 2", "Player 3"]

const _SAVE_PATH := "user://team.cfg"

## Issue #208: the whole set of teams shown in the team menu. teams[0]
## is the PLAYER team (its color, shape and names are applied to the
## player figures in every level); teams[1] ("Enemies") feeds the
## computer team's AI parameters. Persisted in the same team.cfg under
## the "teams" section; the single-team keys above stay in sync with it.
static var teams: Array = []

## Issue #208: the levels place at most three figures per team (hero +
## two teammates / Npc..Npc3) and the menu list must stay readable.
const MAX_TEAM_MEMBERS := 3
const MAX_TEAMS := 8


## Issue #208: the default set of teams = the teams that are in the
## levels: the player team (current customisation) and the computer
## (NPC) team with its authored pink color.
static func default_teams() -> Array:
	var player_names: Array[String] = []
	for member_name in member_names:
		player_names.append(member_name)
	return [
		{
			"label": "Player Team", "color": team_color,
			"shape": team_shape, "names": player_names,
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
		},
		{
			"label": "Enemies", "color": Color(0.75, 0.2, 0.45, 1),
			"shape": "square",
			"names": ["Enemy 1", "Enemy 2", "Enemy 3"],
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
		},
	]


## Issue #208: load the saved set of teams (falling back to the default
## set from the levels), then keep the single-team fields in sync.
static func load_teams() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) == OK and cfg.has_section_key("teams", "set"):
		teams = _sanitize_teams(cfg.get_value("teams", "set", []))
	else:
		teams = default_teams()
	_sync_from_teams()


## Issue #208: persist the whole set of teams and, from it, the classic
## single-team keys every level applies (kept in one file).
static func save_teams() -> void:
	_sync_from_teams()
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)  # keep any other keys; missing file is fine
	cfg.set_value("teams", "set", teams)
	cfg.set_value("team", "color", team_color)
	cfg.set_value("team", "shape", team_shape)
	cfg.set_value("team", "names", member_names)
	cfg.set_value("ai", "skill", ai_skill)
	cfg.set_value("ai", "friendly_fire", ai_friendly_fire)
	cfg.save(_SAVE_PATH)


## Keep the single-team fields the levels apply in sync with the set:
## teams[0] drives the player figures, teams[1] (if present) drives the
## computer team's AI behavior.
static func _sync_from_teams() -> void:
	if teams.is_empty():
		return
	var player: Dictionary = teams[0]
	team_color = player["color"]
	team_shape = player["shape"]
	var names: Array[String] = []
	for member_name in player["names"]:
		names.append(str(member_name))
	while names.size() < member_names.size():
		names.append("Player %d" % (names.size() + 1))
	names.resize(mini(member_names.size(), MAX_TEAM_MEMBERS))
	member_names = names
	team_size = maxi(1, mini(member_names.size(), MAX_TEAM_MEMBERS))
	var ai_team: Dictionary = teams[1] if teams.size() > 1 else player
	ai_skill = clampi(int(ai_team["skill"]), 0, 10)
	ai_friendly_fire = clampi(int(ai_team["friendly_fire"]), 0, 10)


## The cfg file is user-editable, so validate every entry; anything
## broken falls back to sane defaults instead of crashing the menu.
static func _sanitize_teams(raw: Array) -> Array:
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var team: Dictionary = entry
		var names: Array[String] = []
		if team.get("names") is Array:
			for member_name in team["names"].slice(0, MAX_TEAM_MEMBERS):
				var text := str(member_name).strip_edges()
				names.append(text if not text.is_empty() else "Member %d" % (names.size() + 1))
		if names.is_empty():
			names.append("Member 1")
		var shape := str(team.get("shape", "square"))
		if not ["square", "circle", "triangle", "star", "ellipse"].has(shape):
			shape = "square"
		out.append({
			"label": str(team.get("label", "Team %d" % (out.size() + 1))),
			"color": team["color"] if typeof(team.get("color")) == TYPE_COLOR else Color(1, 1, 1),
			"shape": shape, "names": names,
			"skill": clampi(int(team.get("skill", 5)), 0, 10),
			"friendly_fire": clampi(int(team.get("friendly_fire", 0)), 0, 10),
		})
	return out.slice(0, MAX_TEAMS) if not out.is_empty() else default_teams()


## Issue #169: load the saved team customisation (if any) into these
## static fields; called by the team menu and before applying a level.
static func load_team() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	team_color = cfg.get_value("team", "color", team_color)
	team_shape = cfg.get_value("team", "shape", team_shape)
	var names: Array = cfg.get_value("team", "names", member_names)
	if names.size() == member_names.size():
		for i in names.size():
			member_names[i] = str(names[i])
	# Issue #180: AI behavior parameters persist with the team.
	ai_skill = clampi(int(cfg.get_value("ai", "skill", ai_skill)), 0, 10)
	ai_friendly_fire = clampi(int(cfg.get_value("ai", "friendly_fire", ai_friendly_fire)), 0, 10)


## Issue #169: persist the current team customisation.
static func save_team() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("team", "color", team_color)
	cfg.set_value("team", "shape", team_shape)
	cfg.set_value("team", "names", member_names)
	# Issue #180: AI behavior parameters persist with the team.
	cfg.set_value("ai", "skill", ai_skill)
	cfg.set_value("ai", "friendly_fire", ai_friendly_fire)
	cfg.save(_SAVE_PATH)


static func apply(level: Node) -> void:
	# Trim the player team: keep the hero plus team_size - 1 teammates.
	var teammates: Array[String] = ["Teammate1", "Teammate2"]
	for i in teammates.size():
		if i + 1 >= team_size:
			var member := level.get_node_or_null(NodePath(teammates[i]))
			if member != null:
				member.queue_free()
	# Trim the enemy team: the scenes place at most Npc..Npc3.
	var npcs: Array[String] = ["Npc", "Npc2", "Npc3"]
	# Issue #180: AI behavior parameters come from the team configuration:
	# skill maps onto the difficulty bands, friendly-fire passes through.
	var ai_difficulty := 0 if ai_skill <= 3 else (1 if ai_skill <= 7 else 2)
	for i in npcs.size():
		var npc := level.get_node_or_null(NodePath(npcs[i]))
		if npc == null:
			continue
		if i >= enemy_count:
			npc.queue_free()
			continue
		if npc.get("difficulty") != null:
			npc.set("difficulty", ai_difficulty)
		if npc.get("ai_friendly_fire") != null:
			npc.set("ai_friendly_fire", ai_friendly_fire)
	# Issue #169: apply the customised team color, shape and names.
	var members := level.get_tree().get_nodes_in_group("player_team")
	for member in members:
		if member.get("display_name") != null:
			var idx := members.find(member)
			member.set("display_name", member_names[mini(idx, member_names.size() - 1)])
		if member.has_method("apply_team_setup"):
			member.call("apply_team_setup")
