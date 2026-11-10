extends Node
## Regression check for issue #282 (weapon/tool drawn behind the
## character): when a team plays a NON-SQUARE body shape, Player and Npc
## append the ShapeVisual body AFTER the scene's Weapon node, so the held
## weapon/tool ColorRect drew BEHIND the figure. The fix keeps the Weapon
## node the LAST child of every figure (tree order decides which
## CanvasItem draws on top among same-z siblings).
##
## Run headless: godot --headless res://tests/test_issue282.tscn
## Exit code 0 = pass.

const LEVELS := [
	preload("res://Level.tscn"),
	preload("res://Level2.tscn"),
	preload("res://Level3.tscn"),
	preload("res://Level4.tscn"),
	preload("res://Level5.tscn"),
	preload("res://LevelDuel.tscn"),
]

## A shape that forces the ShapeVisual body path in both Player and Npc.
const SHAPE := "circle"


func _ready() -> void:
	# Play circles BEFORE the levels settle so the deferred GameConfig.apply
	# (if it runs) applies the same non-square shape the direct calls below.
	GameConfig.team_shape = SHAPE
	var ok := true
	for level_res in LEVELS:
		var level: Node = level_res.instantiate()
		add_child(level)
		# Let _ready + deferred GameConfig.apply settle.
		await get_tree().physics_frame
		await get_tree().physics_frame
		ok = _check_level(level) and ok
		level.queue_free()
		await get_tree().physics_frame
	print("ISSUE282 ok=", ok)
	get_tree().quit(0 if ok else 1)


func _check_level(level: Node) -> bool:
	var lvl_name := String(level.name)
	var ok := true
	var figures: Array = []
	for group in ["player_team", "enemy_team"]:
		for node in level.get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and not figures.has(node):
				figures.append(node)
	for fig in figures:
		# Apply the non-square shape through the real entry points —
		# Player.apply_team_setup (what GameConfig.apply calls) and
		# Npc.set_team_shape (idempotent re-runs are fine).
		if fig.has_method("apply_team_setup"):
			fig.call("apply_team_setup")
		if fig.has_method("set_team_shape"):
			fig.call("set_team_shape", SHAPE)
		ok = _check_figure(fig) and ok
	print("ISSUE282 ", lvl_name, " figures=", figures.size(), " ok=", ok)
	return ok


## Issue #282 core assertion: the Weapon node is the LAST child of the
## figure, so the held weapon/tool draws IN FRONT of every body visual.
func _check_figure(fig: Node) -> bool:
	var weapon := fig.get_node_or_null("Weapon")
	if weapon == null:
		print("ISSUE282 FAIL ", fig.name, ": no Weapon node")
		return false
	var last_ok: bool = weapon.get_index() == fig.get_child_count() - 1
	# The non-square body visual must exist AND draw before the weapon.
	var body_before := false
	for i in fig.get_child_count():
		var child := fig.get_child(i)
		if child == weapon:
			break
		if child.has_method("set_shape_color") and str(child.name).find("Shape") != -1 \
				and not (child is CollisionShape2D):
			body_before = true
	var ok: bool = last_ok and body_before
	if not ok:
		print("ISSUE282 FAIL ", fig.name, ": weapon_index=", weapon.get_index(),
				" children=", fig.get_child_count(), " body_before=", body_before)
	return ok
