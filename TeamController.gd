extends Node
## Issue #33: switches which member of the player's team is controlled.
##
## Issue #170 rework: direct N/P switching is GONE — switching is now the
## Switch TOOL in the ToolInventory (once per turn). This autoload keeps
## only the control hand-over logic (used by the Switch tool).

func _ready() -> void:
	# Give control to the first team member once the scene is up.
	call_deferred("set_active_index", 0)


func _team() -> Array:
	return get_tree().get_nodes_in_group("player_team")


func _active_index() -> int:
	var members := _team()
	for i in members.size():
		if members[i].get("controlled") == true:
			return i
	return -1


## Issue #170: the Switch tool hands control to the NEXT team member.
func switch_next() -> void:
	var members := _team()
	if members.is_empty():
		return
	var index := _active_index()
	if index == -1:
		index = 0
	set_active_index((index + 1) % members.size())


func set_active_index(index: int) -> void:
	var members := _team()
	if members.is_empty():
		return
	index = clampi(index, 0, members.size() - 1)
	for i in members.size():
		# Issue #121: AI members of the player team (Npc.gd) have no
		# input control to hand over — skip them.
		if members[i].has_method("set_controlled"):
			members[i].set_controlled(i == index)
	# Issue #183: keep TurnController.active_member in sync with control —
	# the whole turn flow (hp watchdog, weapon lock, tools, the NPC gate)
	# keys off active_member, so after a Switch it must point at the newly
	# controlled member, not at the previous one.
	if TurnController.active_team == TurnController.TEAM_PLAYER:
		var member: Node = members[index]
		if member != null and is_instance_valid(member) \
				and member.get("controlled") == true:
			TurnController.active_member = member
