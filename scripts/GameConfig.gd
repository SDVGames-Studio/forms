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
## persisted to user://team.cfg.

## Team color of the player's figures (also used for the turn banner).
static var team_color := Color(1, 0.84, 0.2, 1)

## Shape of the player's figures: square, circle, triangle, star or ellipse.
static var team_shape := "square"

## Names of the team members (index 0 is the hero).
static var member_names: Array[String] = ["Player 1", "Player 2", "Player 3"]

const _SAVE_PATH := "user://team.cfg"


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
