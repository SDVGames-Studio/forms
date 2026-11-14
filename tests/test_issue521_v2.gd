extends Node
## Issue #521 rework (owner report 2026-11-14: "I choose two computers in
## the level2, but when the level is loaded I can still play for one of
## the two teams. Make sure that the level totally depends on the level
## settings") checks:
##
## 1) STAGING — with the FIRST configured team played by the COMPUTER,
##    GameConfig.apply swaps the hero side's human Player figures for
##    computer Npc figures (team = "player"), carrying over each name,
##    and rescues the shared camera a figure hosts to the level.
## 2) TEAMS — TurnController no longer treats the hero team as
##    human-played unless its configured controller is "player".
## 3) INPUT GATES — a computer-played hero team's turn receives no
##    input: Tab does not skip it and notify_member_action does not
##    lock switching. Regression: a human-played hero team keeps both.
## 4) REAL SCENE — the owner's exact repro: Level2 loaded with both
##    teams configured as Computer plays with NO human figure on the
##    field and a working spectator camera.
##
## Run headless: godot --headless res://tests/test_issue521_v2.tscn
## Exit code 0 = pass; the printed ISSUE521V2 ok= verdict is authoritative.

const PlayerScript := preload("res://scripts/Player.gd")
const NpcScript := preload("res://scripts/Npc.gd")
const ZoomCameraScript := preload("res://scripts/ZoomCamera.gd")

func _ready() -> void:
	var driver := Issue521V2Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue521V2Driver extends Node:
	signal done(ok: bool)

	func run() -> void:
		var ok := true

		# --- 1) staging: computer hero team is swapped ----------------
		# The owner's configuration: BOTH teams played by the computer.
		GameConfig.teams = [
			{"label": "Team 1", "color": Color(1, 0.84, 0.2), "shape": "square",
				"names": ["Player 1", "Player 2", "Player 3"],
				"skill": 7, "friendly_fire": 0, "controller": "computer"},
			{"label": "Team 2", "color": Color(0.75, 0.2, 0.45), "shape": "circle",
				"names": ["Pink One", "Pink Two", "Pink Three"],
				"skill": 5, "friendly_fire": 0, "controller": "computer"},
		]
		GameConfig.team_size = 3
		GameConfig.enemy_count = 2
		var level := Node2D.new()
		add_child(level)
		var hero := _stage_player(level, "Player", Vector2(100, 100),
			Color(1, 0.84, 0.2), "square", true)
		var camera: Camera2D = hero.get_node("Camera")
		var mate := _stage_player(level, "Teammate1", Vector2(320, 100),
			Color(1, 0.84, 0.2), "square")
		var npc := _stage_npc(level, "Npc", Vector2(500, 100))
		var npc2 := _stage_npc(level, "Npc2", Vector2(600, 100))
		GameConfig.apply(level)
		# Capture the swap verdicts BEFORE the frame processes the
		# queue_free()d figures — afterwards they are freed instances.
		var hero_gone := hero.is_queued_for_deletion()
		var mate_gone := mate.is_queued_for_deletion()
		await get_tree().process_frame  # replacements enter the tree

		var swapped: Array = []
		for figure in get_tree().get_nodes_in_group("player_team"):
			if figure != null and not figure.is_queued_for_deletion() \
					and figure.get_parent() == level:
				swapped.append(figure)
		ok = _check(ok, "hero side has exactly two computer figures",
			swapped.size() == 2)
		var all_npc := true
		var names := []
		for figure in swapped:
			if figure.get_script() != NpcScript \
					or str(figure.get("team")) != "player":
				all_npc = false
			names.append(str(figure.get("display_name")))
		ok = _check(ok, "hero side figures are Npc (computer, player team)",
			all_npc)
		ok = _check(ok, "swapped figures keep their configured names",
			names.has("Player 1") and names.has("Player 2"))
		ok = _check(ok, "swapped figures wear the team's AI parameters",
			swapped.size() == 2 and int(swapped[0].get("difficulty")) == 1)  # skill 7 -> normal band
		ok = _check(ok, "old human figures are gone", hero_gone and mate_gone)
		ok = _check(ok, "camera rescued to the level and enabled",
			camera.get_parent() == level and camera.enabled
			and camera.is_in_group("player_camera"))
		ok = _check(ok, "enemy figures stay computer figures",
			not npc.is_queued_for_deletion()
			and not npc2.is_queued_for_deletion()
			and npc.get_script() == NpcScript
			and npc.get("team_color") == Color(0.75, 0.2, 0.45))

		# --- 2) teams: hero is human only when configured -------------
		TurnController._scan_teams()
		ok = _check(ok, "all-computer match has no human team",
			not TurnController.is_player_team(TurnController.TEAM_PLAYER)
			and not TurnController.is_player_team(TurnController.TEAM_ENEMY))
		ok = _check(ok, "two teams discovered (hero + one color)",
			TurnController._teams.size() == 2)
		# Regression: the classic configuration (hero = player) keeps the
		# hero team human.
		GameConfig.teams = GameConfig.default_teams()
		TurnController._scan_teams()
		ok = _check(ok, "regression: human hero team stays player-controlled",
			TurnController.is_player_team(TurnController.TEAM_PLAYER))
		GameConfig.teams[0]["controller"] = "computer"
		TurnController._scan_teams()
		ok = _check(ok, "computer hero team is not player-controlled",
			not TurnController.is_player_team(TurnController.TEAM_PLAYER))

		# --- 3) input gates: no input on a computer hero turn ---------
		# The synthetic level stays out of the "level" group, so the
		# autoload's _process never starts the roll — bind the controller
		# by hand and begin the hero team's turn: its active member must
		# be a COMPUTER figure.
		TurnController._level = level
		TurnController.game_over = false
		TurnController._begin_turn(TurnController.TEAM_PLAYER)
		ok = _check(ok, "computer hero turn is driven by an Npc member",
			TurnController.active_member != null
			and TurnController.active_member.get_script() == NpcScript)
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		TurnController._unhandled_input(tab)
		ok = _check(ok, "Tab does not skip a computer team's turn",
			TurnController.active_team == TurnController.TEAM_PLAYER)
		TurnController.notify_member_action()
		ok = _check(ok, "no switch lock without a human team",
			not TurnController.is_switch_locked())
		# Regression: with a HUMAN hero team the same action locks.
		GameConfig.teams[0]["controller"] = "player"
		TurnController._scan_teams()
		TurnController._begin_turn(TurnController.TEAM_PLAYER)
		TurnController.notify_member_action()
		ok = _check(ok, "regression: human hero turn still locks switching",
			TurnController.is_switch_locked())
		TurnController.active_team = ""
		TurnController.active_member = null
		TurnController._level = null
		level.queue_free()

		# --- 4) the owner's exact repro: Level2, two computers --------
		GameConfig.teams = [
			{"label": "Team 1", "color": Color(1, 0.84, 0.2), "shape": "square",
				"names": ["Player 1", "Player 2", "Player 3"],
				"skill": 5, "friendly_fire": 0, "controller": "computer"},
			{"label": "Team 2", "color": Color(0.75, 0.2, 0.45), "shape": "circle",
				"names": ["Pink One", "Pink Two", "Pink Three"],
				"skill": 5, "friendly_fire": 0, "controller": "computer"},
		]
		GameConfig.team_size = 3
		GameConfig.enemy_count = 3
		var level2: Node = load("res://scenes/levels/Level2.tscn").instantiate()
		add_child(level2)
		await get_tree().process_frame
		await get_tree().process_frame
		var human_left := false
		var figures := 0
		for figure in get_tree().get_nodes_in_group("player_team"):
			if figure == null or not is_instance_valid(figure):
				continue
			figures += 1
			if figure.has_method("set_controlled"):
				human_left = true
		ok = _check(ok, "Level2 with two computers stages no human figure",
			not human_left and figures == 3)
		var cam: Camera2D = level2.get_node_or_null("Camera")
		ok = _check(ok, "Level2 camera survives the swap as spectator view",
			cam != null and cam.get_parent() == level2 and cam.enabled
			and cam.is_in_group("player_camera"))
		ok = _check(ok, "TurnController sees a computer-only match",
			not TurnController.is_player_team(TurnController.TEAM_PLAYER))
		level2.free()

		print("ISSUE521V2 ok=%s" % str(ok).to_lower())
		done.emit(ok)


	func _stage_player(level: Node, figure_name: String, at: Vector2,
			color: Color, shape: String, with_camera := false) -> Node:
		var figure := CharacterBody2D.new()
		figure.name = figure_name
		figure.set_script(PlayerScript)
		figure.position = at
		figure.set("team_color", color)
		figure.set("team_shape", shape)
		var capsule := CollisionShape2D.new()
		var form := CapsuleShape2D.new()
		form.radius = 24.0
		form.height = 57.6
		capsule.shape = form
		figure.add_child(capsule)
		var visual := ColorRect.new()
		visual.name = "BodyVisual"
		visual.offset_left = -32.0
		visual.offset_top = -32.0
		visual.offset_right = 32.0
		visual.offset_bottom = 32.0
		figure.add_child(visual)
		var weapon := Node2D.new()
		weapon.name = "Weapon"
		weapon.set_script(preload("res://scripts/Weapon.gd"))
		figure.add_child(weapon)
		# A camera is attached BEFORE the figure enters the tree, exactly
		# like the scene-authored levels (Level2): Player._ready must FIND
		# it instead of spawning its own fallback.
		if with_camera:
			var cam := Camera2D.new()
			cam.name = "Camera"
			cam.set_script(ZoomCameraScript)
			figure.add_child(cam)
		level.add_child(figure)
		return figure


	func _stage_npc(level: Node, figure_name: String, at: Vector2) -> Node:
		var npc := CharacterBody2D.new()
		npc.name = figure_name
		npc.set_script(NpcScript)
		npc.position = at
		level.add_child(npc)
		return npc


	func _check(ok: bool, what: String, passed: bool) -> bool:
		print("[%s] %s" % ["ok" if passed else "FAIL", what])
		return ok and passed
