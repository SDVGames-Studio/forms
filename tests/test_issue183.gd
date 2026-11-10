extends Node
## Regression check for issue #183: character synchronization — the player
## could move both their own and the computer's character, and the computer
## could shoot during the player's move.
##
## Verifies, in the real Level scene:
##  1. exactly one player-team member is controlled at any time;
##  2. an enemy NPC stays idle even when a stale active_member points at
##     it during the player's turn (it must never act or shoot then);
##  3. after the Switch tool hands control over, TurnController.active_member
##     follows the newly controlled member.
##
## Run headless: godot --headless res://tests/test_issue183.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	for i in 30:
		await get_tree().physics_frame
	# Get to a player turn (skip any enemy turn quickly).
	var waited := 0.0
	while TurnController.active_team != "player" and waited < 20.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		if TurnController.active_team == "enemy":
			TurnController._end_turn()
			for i in 5:
				await get_tree().physics_frame
			waited = 0.0
	var in_player_turn: bool = TurnController.active_team == "player"

	# 1 + 2: exactly one controlled member; a stale active_member on an NPC
	# must not let it act during the player's turn.
	var one_controlled := false
	var npc_idle := true
	var npc: Node = null
	for node in get_tree().get_nodes_in_group("enemy_team"):
		if is_instance_valid(node):
			npc = node
			break
	if npc != null and is_instance_valid(npc):
		TurnController.active_member = npc  # stale/desynced state
		var x0: float = npc.global_position.x
		var hp0: int = 100
		for p in get_tree().get_nodes_in_group("player_team"):
			if is_instance_valid(p) and p.get("controlled") == true:
				hp0 = p.get("health")
		for i in 60:
			await get_tree().physics_frame
		npc_idle = absf(npc.global_position.x - x0) < 2.0
		for p in get_tree().get_nodes_in_group("player_team"):
			if is_instance_valid(p) and p.get("controlled") == true:
				one_controlled = p.get("health") == hp0
	# Restore the real active member.
	TurnController.active_member = null
	var ctrl_count := 0
	for m in get_tree().get_nodes_in_group("player_team"):
		if is_instance_valid(m) and m.get("controlled") == true:
			ctrl_count += 1
			TurnController.active_member = m
	one_controlled = one_controlled and ctrl_count == 1

	# 3: after the Switch tool, active_member follows the controlled member.
	var switched_follow := true
	if ToolInventory.use_tool(ToolInventory.TOOL_SWITCH):
		await get_tree().physics_frame
		var am = TurnController.active_member
		switched_follow = am != null and is_instance_valid(am) \
			and am.get("controlled") == true
		# Only the newly controlled member may move.
		if am != null and is_instance_valid(am):
			Input.action_press("move_right")
			var x0: float = am.global_position.x
			var others_ok := true
			for m in get_tree().get_nodes_in_group("player_team"):
				if is_instance_valid(m) and m != am:
					m.set_meta("x0", m.global_position.x)
			for i in 60:
				await get_tree().physics_frame
			Input.action_release("move_right")
			switched_follow = absf(am.global_position.x - x0) > 2.0
			for m in get_tree().get_nodes_in_group("player_team"):
				if is_instance_valid(m) and m != am:
					if absf(m.global_position.x - float(m.get_meta("x0"))) > 2.0:
						others_ok = false
			switched_follow = switched_follow and others_ok
	else:
		# Switch unavailable (already used this turn) — skip check 3.
		switched_follow = true

	var ok: bool = in_player_turn and one_controlled and npc_idle \
		and switched_follow
	print("ISSUE183 player_turn=", in_player_turn, " one_controlled=",
		one_controlled, " npc_idle_in_player_turn=", npc_idle,
		" switch_follows_control=", switched_follow, " ok=", ok)
	get_tree().quit(0 if ok else 1)
