extends Node
## Issue #521 (one-device multiplayer) checks:
##
## 1) CONFIG — every team carries a controller ("player"/"computer");
##    legacy team sets without the key default by slot (first team
##    human, the rest computer); the controller is found by team COLOR.
## 2) STAGING — GameConfig.apply deals the configured teams beyond the
##    first round-robin onto the kept enemy figures: each wears its
##    team's color/shape/name, and a team marked "player" has its
##    computer figure REPLACED by a human Player.gd figure staged on
##    the enemy side (team_side = "enemy", groups follow).
## 3) HOT-SEAT FLOW — TurnController discovers the teams, treats the
##    human-played enemy-color team as player-controlled
##    (is_player_team), and _begin_turn hands the SINGLE control flag
##    between human teams: whoever's turn it is answers the keys, the
##    other human team's figure does not.
##
## Run headless: godot --headless res://tests/test_issue521.tscn
## Exit code 0 = pass; the printed ISSUE521 ok= verdict is authoritative.

const PlayerScript := preload("res://Player.gd")
const NpcScript := preload("res://Npc.gd")

func _ready() -> void:
	var driver := Issue521Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue521Driver extends Node:
	signal done(ok: bool)

	func run() -> void:
		var ok := true

		# --- 1) config: controller defaults + color lookup -----------
		GameConfig.teams = GameConfig.default_teams()
		ok = _check(ok, "hero team defaults to player",
			GameConfig.team_controller(0) == "player")
		ok = _check(ok, "second team defaults to computer",
			GameConfig.team_controller(1) == "computer")
		# A legacy saved set (no controller key) sanitizes by slot.
		var legacy: Array = [
			{"label": "Old 1", "color": Color(1, 0.84, 0.2), "shape": "square",
				"names": ["A", "B", "C"], "skill": 5, "friendly_fire": 0},
			{"label": "Old 2", "color": Color(0.75, 0.2, 0.45), "shape": "circle",
				"names": ["D", "E", "F"], "skill": 5, "friendly_fire": 0},
		]
		GameConfig.teams = GameConfig._sanitize_teams(legacy)
		ok = _check(ok, "legacy first team becomes player",
			GameConfig.team_controller(0) == "player")
		ok = _check(ok, "legacy second team becomes computer",
			GameConfig.team_controller(1) == "computer")
		ok = _check(ok, "controller found by color",
			GameConfig.team_controller_for_color(Color(1, 0.84, 0.2)) == "player"
			and GameConfig.team_controller_for_color(Color(0.75, 0.2, 0.45)) == "computer")

		# --- 2) staging: apply() deals the configured teams -----------
		# Three configured teams: hero (human), pink computer, BLUE HUMAN.
		GameConfig.teams = [
			{"label": "Team 1", "color": Color(1, 0.84, 0.2), "shape": "square",
				"names": ["Player 1", "Player 2", "Player 3"],
				"skill": 5, "friendly_fire": 0, "controller": "player"},
			{"label": "Team 2", "color": Color(0.75, 0.2, 0.45), "shape": "circle",
				"names": ["Pink One", "Pink Two", "Pink Three"],
				"skill": 5, "friendly_fire": 0, "controller": "computer"},
			{"label": "Team 3", "color": Color(0.35, 0.6, 1), "shape": "triangle",
				"names": ["Blue One", "Blue Two", "Blue Three"],
				"skill": 5, "friendly_fire": 0, "controller": "player"},
		]
		GameConfig.team_size = 3
		GameConfig.enemy_count = 2
		var level := Node2D.new()
		add_child(level)
		var hero := _stage_player(level, "Hero", Vector2(100, 100),
			Color(1, 0.84, 0.2), "square")
		var npc := _stage_npc(level, "Npc", Vector2(500, 100))
		var npc2 := _stage_npc(level, "Npc2", Vector2(600, 100))
		GameConfig.apply(level)
		# Capture the trim/replace verdicts BEFORE the frame processes the
		# queue_free()d figures — afterwards they are freed instances.
		var npc2_queued := npc2.is_queued_for_deletion()
		await get_tree().process_frame  # replacements enter the tree

		# Both enemy slots are kept (enemy_count = 2), dealt round-robin:
		# Npc -> Team 2 (computer, pink), Npc2 -> Team 3 (human, blue).
		ok = _check(ok, "computer team keeps its Npc figure",
			not npc.is_queued_for_deletion() and npc.get_script() == NpcScript
			and npc.get("team_color") == Color(0.75, 0.2, 0.45))
		ok = _check(ok, "computer team wears its name",
			str(npc.get("display_name")) == "Pink One")
		var blue: Node = null
		for node in get_tree().get_nodes_in_group("enemy_team"):
			if node != null and not node.is_queued_for_deletion() \
					and node.get("team_color") is Color \
					and node.get("team_color") == Color(0.35, 0.6, 1):
				blue = node
		ok = _check(ok, "human team's Npc is replaced",
			npc2_queued)
		ok = _check(ok, "human team gets a Player figure on the enemy side",
			blue != null and blue.get_script() == PlayerScript
			and blue.is_in_group("enemy_team")
			and not blue.is_in_group("player_team")
			and str(blue.get("team_shape")) == "triangle"
			and str(blue.get("display_name")) == "Blue One")

		# --- 3) hot-seat flow: teams + control hand-over -------------
		TurnController._scan_teams()
		# _begin_turn keys off the level the controller is bound to; the
		# synthetic level deliberately stays OUT of the "level" group so
		# the controller's _process never starts the first-team roll —
		# bind it directly and drive the turns by hand.
		TurnController._level = level
		var pink_id := ""
		var blue_id := ""
		for id in TurnController._teams:
			if id != TurnController.TEAM_PLAYER:
				if id == TurnController.TEAM_ENEMY:
					pink_id = id
				else:
					if str(id).begins_with("enemy:"):
						# Two enemy colors: tell them apart by member color.
						for member in TurnController.members_of(id):
							if member.get("team_color") == Color(0.75, 0.2, 0.45):
								pink_id = id
							elif member.get("team_color") == Color(0.35, 0.6, 1):
								blue_id = id
		ok = _check(ok, "three teams discovered",
			TurnController._teams.size() == 3)
		ok = _check(ok, "enemy ids resolved", pink_id != "" and blue_id != "")
		ok = _check(ok, "hero team is player-controlled",
			TurnController.is_player_team(TurnController.TEAM_PLAYER))
		ok = _check(ok, "human hot-seat team is player-controlled",
			TurnController.is_player_team(blue_id))
		ok = _check(ok, "computer team is not player-controlled",
			not TurnController.is_player_team(pink_id))

		# The hero figure claims control on _ready; the blue team's turn
		# must take it over — and give it back on the hero team's turn.
		ok = _check(ok, "hero claims control initially",
			hero.get("controlled") == true)
		TurnController._begin_turn(blue_id)
		ok = _check(ok, "hot-seat turn controls the human team's member",
			TurnController.active_member != null
			and TurnController.active_member.get("team_color") == Color(0.35, 0.6, 1)
			and TurnController.active_member.get("controlled") == true)
		ok = _check(ok, "hero drops control during the hot-seat turn",
			hero.get("controlled") == false)
		TurnController._begin_turn(TurnController.TEAM_PLAYER)
		ok = _check(ok, "hero team regains control",
			hero.get("controlled") == true
			and TurnController.active_member == hero)
		var blue_still := false
		for node in get_tree().get_nodes_in_group("enemy_team"):
			if node != null and node.get("controlled") == true:
				blue_still = true
		ok = _check(ok, "hot-seat figure drops control back",
			not blue_still)

		print("ISSUE521 ok=%s" % str(ok).to_lower())
		done.emit(ok)


	func _stage_player(level: Node, figure_name: String, at: Vector2,
			color: Color, shape: String) -> Node:
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
		weapon.set_script(preload("res://Weapon.gd"))
		figure.add_child(weapon)
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
