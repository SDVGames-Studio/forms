extends Node
## Regression check for issue #97: the health bar above a character must
## change when the character takes damage.
## Issue #726: the fill must be VISIBLE (height > 0 — the old zero-height
## fill made the bar an empty dark line), always red, and shrink
## symmetrically from both edges toward the centre as HP drops.
##
## Run headless: godot --headless res://tests/test_health_bar.tscn
## Exit code 0 = pass. Two checks:
##  1. A fresh CharacterBody2D with Player.gd attached.
##  2. The real Player inside Level1.tscn.

func _ready() -> void:
	var ok := true
	ok = await _check_fresh() and ok
	ok = await _check_in_scene() and ok
	print("ISSUE97 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


func _check_fresh() -> bool:
	var player := CharacterBody2D.new()
	player.set_script(load("res://scripts/Player.gd"))
	add_child(player)
	await get_tree().process_frame
	var fill: ColorRect = player.get("_bar_fill")
	var w0: float = fill.size.x
	var h0: float = fill.size.y
	player.take_damage(30)
	var expected: float = 62.0 * float(player.health) / 100.0
	var ok: bool = int(player.health) == 70 \
		and absf(w0 - 62.0) < 0.5 \
		and h0 > 0.0 \
		and absf(fill.size.x - expected) < 0.5 \
		and fill.size.y == h0 \
		and fill.color.r > fill.color.g \
		and absf(fill.offset_left + fill.offset_right) < 0.001
	print("ISSUE97 fresh: health=", player.health, " w=", w0, "->", fill.size.x,
		" h=", h0, " color=", fill.color, " ok=", ok)
	player.queue_free()
	return ok


func _check_in_scene() -> bool:
	# Issue #617: the uniform staging names the first figure Team1mate1
	# (no authored "Player" node anymore) and every team defaults to the
	# computer — dress the first team as the human player so the figure
	# under test is a real Player runtime body, as before the rework.
	GameConfig.teams = GameConfig.default_teams()
	GameConfig.teams[0]["controller"] = "player"
	var level: Node = load("res://scenes/levels/Level1.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame
	var player: Node = level.get_node("Team1mate1")
	# The uniform #617 staging: the dressed runtime figure keeps the
	# staged slot name (Team1mate1 is member 1 of the first team).
	for i in 10:
		if player != null and player.get("_bar_fill") != null:
			break
		await get_tree().physics_frame
		player = level.get_node_or_null("Team1mate1")
	var fill: ColorRect = player.get("_bar_fill")
	var w0: float = fill.size.x
	var h0: float = fill.size.y
	player.take_damage(30)
	var ok: bool = int(player.health) == 70 \
		and absf(w0 - 62.0) < 0.5 \
		and h0 > 0.0 \
		and absf(fill.size.x - 43.4) < 0.5 \
		and fill.size.y == h0 \
		and fill.color.r > fill.color.g \
		and absf(fill.offset_left + fill.offset_right) < 0.001
	print("ISSUE97 scene: w ", w0, " -> ", fill.size.x, " h ", h0,
		" color ", fill.color, " ok=", ok)
	level.queue_free()
	return ok
