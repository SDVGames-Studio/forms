extends Node
## Regression check for issue #614: the Finish trigger area is gone and
## the level's real finish — exactly one team left standing — plays the
## celebration overlay and then leaves the level on screen for spectate
## (issue #701 rework).
##
## Asserts:
##   - no level scene references LevelFinish.gd / a "Finish" node /
##     its collision subresource anymore;
##   - the chain config is GONE (issue #701): LevelConfig no longer
##     exposes next_scene and no level scene authors one — a finished
##     level must never auto-begin a new game;
##   - the real win flow: one team alive -> celebration overlay ->
##     NOTHING auto-loads (issue #701 rework: no new game, no forced
##     Main menu) — the level stays on screen for spectate.
##
## Run headless: godot --headless res://tests/test_issue614.tscn
## Exit code 0 = pass.

const TARGET_SCENE := "res://tests/test_issue614_target.tscn"
const LEVEL_SCENES := [
	"res://scenes/levels/Level1.tscn",
	"res://scenes/levels/Level2.tscn",
	"res://scenes/levels/Level3.tscn",
	"res://scenes/levels/Level4.tscn",
	"res://scenes/levels/Level5.tscn",
	"res://scenes/levels/Level6.tscn",
	"res://scenes/levels/Level7.tscn",
	"res://scenes/levels/CustomLevel.tscn",
]

func _ready() -> void:
	# The driver lives directly under /root so no teardown can free it
	# (same pattern as tests/test_issue303.gd).
	var driver := Issue614Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue614Driver extends Node:
	signal done(ok: bool)

	const TARGET_SCENE := "res://tests/test_issue614_target.tscn"

	## Minimal stand-in for a level root: a duck-typed next_scene that
	## the win flow must IGNORE (issue #701 — no authored advance).
	class FakeLevel extends Node2D:
		var next_scene := ""

	## Minimal figure: health is all _alive() looks at.
	class FakeFig extends Node2D:
		var health := 100

	func run() -> void:
		var failures: Array[String] = []
		_check_scenes(failures)
		_check_no_chain(failures)
		await _check_win_flow(failures)

		if failures.is_empty():
			print("ISSUE614 OK: finish removed, real-win celebration + spectate stays")
		else:
			for f in failures:
				print("ISSUE614 FAIL: " + f)
		done.emit(failures.is_empty())

	func _check_scenes(failures: Array[String]) -> void:
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
				if "LevelFinish" in text or 'name="Finish"' in text \
						or "RectangleShape2D_finish" in text:
					failures.append("%s still references the Finish trigger" % path)
			name = dir.get_next()
		# The trigger's script is gone from the project entirely.
		if FileAccess.file_exists("res://scripts/LevelFinish.gd"):
			failures.append("scripts/LevelFinish.gd must be deleted")

	func _check_no_chain(failures: Array[String]) -> void:
		# Issue #701: the level chain is gone — a finished level must
		# never auto-begin a new game, so nothing may configure one.
		var level_config := load("res://scripts/LevelConfig.gd")
		var probe: Node2D = level_config.new()
		for p in probe.get_property_list():
			if p["name"] == "next_scene":
				failures.append("LevelConfig must not expose next_scene (issue #701)")
		probe.free()

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
					failures.append("%s must not author next_scene (issue #701)" % path)
			name = dir.get_next()

	func _check_win_flow(failures: Array[String]) -> void:
		var tree := get_tree()
		var old_current := tree.current_scene

		# A standalone "level" with one living player figure: the enemy
		# team died out, so the real finish condition is met.
		var level := FakeLevel.new()
		# The chain target is still duck-typed onto the root — the win flow
		# must ignore it (issue #701): nothing may auto-load at the finish.
		level.next_scene = TARGET_SCENE
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
		if not TurnController._win_celebrated:
			failures.append("the win must launch the celebration flow")

		# Celebration overlay (banner + confetti CanvasLayer) on the tree —
		# its children appear a couple of frames after the win.
		for i in 6:
			await tree.process_frame
		var overlay := _find_celebration(TurnController)
		if overlay == null:
			failures.append("the win must spawn the celebration overlay")

		# ...then NOTHING: the overlay plays out and the finished level
		# STAYS on screen for spectate (issue #701 rework) — neither a
		# new game nor the Main menu may auto-load. Wait out the
		# celebration (duration 2 s; allow headless slack).
		for i in 400:
			await tree.process_frame
		if tree.current_scene != level:
			failures.append("the win must NOT change the scene — the level "
				+ "stays on screen for spectate (issue #701 rework)")

		# Restore the test scene as current so teardown stays tidy.
		if is_instance_valid(level):
			level.queue_free()
		tree.current_scene = old_current

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
