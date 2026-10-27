extends Node
## Issue #33: switches which member of the player's team is controlled.
##
## N ("switch_next") picks the next team member, P ("switch_prev") the
## previous one. The team is every live node in the "player_team" group;
## switching moves input control (and the camera) to the new member.

func _ready() -> void:
	# Give control to the first team member once the scene is up.
	call_deferred("set_active_index", 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_next"):
		_cycle(1)
	elif event.is_action_pressed("switch_prev"):
		_cycle(-1)


func _team() -> Array:
	return get_tree().get_nodes_in_group("player_team")


func _active_index() -> int:
	var members := _team()
	for i in members.size():
		if members[i].get("controlled") == true:
			return i
	return -1


func _cycle(step: int) -> void:
	# Issue #104: once the active member has moved or aimed this turn,
	# character switching is blocked until the turn ends.
	if TurnController.is_switch_locked():
		return
	var members := _team()
	if members.is_empty():
		return
	var index := _active_index()
	if index == -1:
		index = 0
	index = (index + step + members.size()) % members.size()
	set_active_index(index)


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
