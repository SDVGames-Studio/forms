extends Node
## Regression check for issue #701: a new game must never begin by
## itself when the game (level) finishes — and the finish must not
## yank the player out either (rework, 2026-11-26): after the
## celebration the finished level STAYS on screen so the player (or
## players) can spectate it; leaving to the Main menu goes through
## the standard in-game menu (ESC -> Main Menu), nothing new added.
##
## Checks:
##  1. CHAIN GONE: LevelConfig exposes no next_scene property and no
##     level scene authors one — there is no chain left to follow.
##  2. WIN FLOW: one team left standing -> celebration overlay ->
##     the scene NEVER changes (no new game, no forced Main menu),
##     the level stays live in the spectate state, and the standard
##     exit (the in-game menu's Main Menu button) is still there.
##
## Run headless: godot --headless res://tests/test_issue701.tscn
## Exit code 0 = pass.

const NEW_GAME_SCENE := "res://tests/test_issue701_target.tscn"
const MAIN_SCENE := "res://scenes/Main.tscn"


func _ready() -> void:
	# The driver must survive whatever the win flow does to the scene,
	# so it lives directly under /root (same pattern as
	# tests/test_issue614.gd).
	var driver := Issue701Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue701Driver extends Node:
	signal done(ok: bool)

	const NEW_GAME_SCENE := "res://tests/test_issue701_target.tscn"
	const MAIN_SCENE := "res://scenes/Main.tscn"

	## Minimal stand-in for a level root: the OLD chain property, still
	## duck-typed on the root — the win flow must ignore it.
	class FakeLevel extends Node2D:
		var next_scene := ""

	## Minimal figure: health is all _alive() looks at.
	class FakeFig extends Node2D:
		var health := 100

	func run() -> void:
		var failures: Array[String] = []
		_check_chain_gone(failures)
		await _check_win_flow(failures)

		if failures.is_empty():
			print("ISSUE701 OK: a finished level stays for spectate, "
				+ "never begins a new game")
		else:
			for f in failures:
				print("ISSUE701 FAIL: " + f)
		done.emit(failures.is_empty())

	func _check_chain_gone(failures: Array[String]) -> void:
		var level_config := load("res://scripts/LevelConfig.gd")
		var probe: Node2D = level_config.new()
		for p in probe.get_property_list():
			if p["name"] == "next_scene":
				failures.append("LevelConfig must not expose next_scene")
		probe.free()

		# No level scene may author a chain target — no new game can be
		# configured to auto-begin at the finish.
		var dir := DirAccess.open("res://scenes/levels")
		if dir == null:
			failures.append("cannot open res://scenes/levels")
			return
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.ends_with(".tscn"):
				var path := "res://scenes/levels/" + name
				var text := FileAccess.get_file_as_string(path)
				if "next_scene" in text:
					failures.append("%s must not author next_scene" % path)
			name = dir.get_next()

	func _check_win_flow(failures: Array[String]) -> void:
		var tree := get_tree()
		var old_current := tree.current_scene

		# A standalone "level" with one living player figure: the enemy
		# team died out, so the real finish condition is met. The root
		# still carries a duck-typed next_scene pointing at a "new game"
		# scene — exactly what must NOT auto-begin at the finish.
		var level := FakeLevel.new()
		level.next_scene = NEW_GAME_SCENE
		level.name = "FakeLevel"
		level.add_to_group("level")
		var hero := FakeFig.new()
		hero.add_to_group("player_team")
		level.add_child(hero)
		var foe := FakeFig.new()
		foe.health = 0
		foe.add_to_group("enemy_team")
		level.add_child(foe)
		tree.root.add_child(level)
		# Let TurnController notice the level (its _process scans the
		# "level" group) and build the HUD for the round roll.
		for i in 5:
			await tree.process_frame
		TurnController._teams = ["player", "enemy"]
		# The gate: only a scene-level level (current_scene) celebrates.
		tree.current_scene = level
		TurnController._check_win()

		if not TurnController.game_over:
			failures.append("one team alive must set game_over")

		# Celebration overlay (banner + confetti CanvasLayer) on the tree —
		# its children appear a couple of frames after the win.
		for i in 6:
			await tree.process_frame
		if _find_celebration(TurnController) == null:
			failures.append("the win must still play the celebration overlay")

		# ...then NOTHING: the overlay plays out and the finished level
		# STAYS on screen for spectate (rework) — neither a next_scene
		# new game nor the Main menu may auto-load. Wait out the
		# celebration (duration 2 s; allow headless slack).
		for i in 400:
			await tree.process_frame
		if tree.current_scene != level:
			failures.append("the finish must NOT change the scene — the "
				+ "level stays on screen for spectate")
		if TurnController.get("_level") != level:
			failures.append("the finished level must stay live for spectate")
		var hint: Label = TurnController.get("_hint_label")
		if hint == null or hint.text != TurnController.HINT_SPECTATE:
			failures.append("the spectate hint must be up after the finish")

		# The standard exit is unchanged: the in-game menu (autoload)
		# still offers its Main Menu button — the owner's "exit with
		# standard menu tools" path, no new tools.
		if _find_main_menu_button() == null:
			failures.append("InGameMenu must keep the Main Menu button")

		# Restore the test scene as current so teardown stays tidy.
		if is_instance_valid(level):
			level.queue_free()
		tree.current_scene = old_current

	func _find_main_menu_button() -> Button:
		var menu := get_tree().root.get_node_or_null("InGameMenu")
		if menu == null:
			return null
		var buttons: Array = menu.find_children(
			"MainMenuButton", "Button", true, false)
		if buttons.is_empty():
			return null
		return buttons[0]

	func _find_celebration(root: Node) -> Node:
		# The celebration overlay is the CanvasLayer carrying a confetti
		# CPUParticles2D (the HUD layer has no particles).
		var stack: Array[Node] = [root]
		var candidate: Node = null
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node != root and node is CanvasLayer:
				for child in node.get_children():
					if child is CPUParticles2D:
						candidate = node
			for child in node.get_children():
				stack.append(child)
		return candidate
