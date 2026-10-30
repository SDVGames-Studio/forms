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

## AI difficulty: 0 = easy, 1 = normal, 2 = hard.
static var difficulty := 1

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


## Issue #169: persist the current team customisation.
static func save_team() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("team", "color", team_color)
	cfg.set_value("team", "shape", team_shape)
	cfg.set_value("team", "names", member_names)
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
	for i in npcs.size():
		if i >= enemy_count:
			var npc := level.get_node_or_null(NodePath(npcs[i]))
			if npc != null:
				npc.queue_free()
			if difficulty != 1 and npc != null and npc.get("difficulty") != null:
				npc.set("difficulty", difficulty)
	# Issue #169: apply the customised team color, shape and names.
	var members := level.get_tree().get_nodes_in_group("player_team")
	for member in members:
		if member.get("display_name") != null:
			var idx := members.find(member)
			member.set("display_name", member_names[mini(idx, member_names.size() - 1)])
		if member.has_method("apply_team_setup"):
			member.call("apply_team_setup")
