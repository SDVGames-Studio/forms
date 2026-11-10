extends Node
## Regression check for issue #186: a blast hitting a player-team character
## must produce the same brief visual flash that an NPC hit produces.
##
## Verifies in the real Level scene:
##  1. the controlled player's body visual briefly changes color after
##     take_damage and returns to the team color (like Npc.take_damage).
##
## Run headless: godot --headless res://tests/test_issue186.tscn
## Exit code 0 = pass.

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])


func _body_visual(member: Node) -> Node:
	for child in member.get_children():
		var rect := child as ColorRect
		if rect != null and rect.name != "Shield" \
				and rect.name != "HealthBarBackground" and rect.visible:
			return rect
		var shape := child as Node
		if shape != null and shape.name.ends_with("Shape") and shape.visible:
			return shape
	return null


func _visual_color(visual: Node) -> Color:
	if visual is ColorRect:
		return visual.color
	return visual.shape_color


func _set_visual_color(visual: Node, value: Color) -> void:
	if visual is ColorRect:
		visual.color = value
	else:
		visual.shape_color = value


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run()
	if _failures.is_empty():
		print("ISSUE186: PASS")
		get_tree().quit(0)
	else:
		print("ISSUE186: FAIL")
		get_tree().quit(1)


func _run() -> void:
	var level_scene: PackedScene = load("res://Level.tscn")
	var level: Node = level_scene.instantiate()
	add_child(level)
	await get_tree().process_frame

	var members := get_tree().get_nodes_in_group("player_team")
	_check(members.size() > 0, "player team has members")
	var m: Node = members[0]
	var visual := _body_visual(m)
	_check(visual != null, "member has a body visual")
	if visual == null:
		return
	var team_color := _visual_color(visual)
	m.take_damage(1)
	var flashed := _visual_color(visual)
	_check(flashed != team_color, "body visual flashes after damage")
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(visual):
		_check(false, "visual still valid after flash")
		return
	_check(_visual_color(visual) == team_color,
			"body visual restores the team color")
	level.queue_free()
	await get_tree().process_frame
