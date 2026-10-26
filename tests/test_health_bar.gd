extends Node
## Regression check for issue #97: the health bar above a character must
## change when the character takes damage.
##
## Run headless: godot --headless res://tests/test_health_bar.tscn
## Exit code 0 = pass. Two checks:
##  1. A fresh CharacterBody2D with Player.gd attached.
##  2. The real Player inside Level.tscn.

func _ready() -> void:
	var ok := true
	ok = await _check_fresh() and ok
	ok = await _check_in_scene() and ok
	print("ISSUE97 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


func _check_fresh() -> bool:
	var player := CharacterBody2D.new()
	player.set_script(load("res://Player.gd"))
	add_child(player)
	await get_tree().process_frame
	player.take_damage(30)
	var fill: ColorRect = player.get("_bar_fill")
	var expected: float = 62.0 * float(player.health) / 100.0
	var ok: bool = int(player.health) == 70 \
		and absf(fill.size.x - expected) < 0.5 \
		and fill.color.r < fill.color.g
	print("ISSUE97 fresh: health=", player.health, " width=", fill.size.x,
		" expected=", expected, " color=", fill.color, " ok=", ok)
	player.queue_free()
	return ok


func _check_in_scene() -> bool:
	var level: Node = load("res://Level.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame
	var player: Node = level.get_node("Player")
	var fill: ColorRect = player.get("_bar_fill")
	var w0: float = fill.size.x
	var c0: Color = fill.color
	player.take_damage(30)
	var ok: bool = int(player.health) == 70 \
		and absf(fill.size.x - 43.4) < 0.5 \
		and fill.color != c0
	print("ISSUE97 scene: width ", w0, " -> ", fill.size.x,
		" color ", c0, " -> ", fill.color, " ok=", ok)
	level.queue_free()
	return ok
