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
		elif difficulty != 1:
			var npc := level.get_node_or_null(NodePath(npcs[i]))
			if npc != null and npc.get("difficulty") != null:
				npc.set("difficulty", difficulty)
