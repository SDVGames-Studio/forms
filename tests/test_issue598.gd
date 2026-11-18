extends Node
## Regression check for issue #598: the character's LINE (speech
## balloon) renders in front of EVERYTHING, and the character's HP bar
## in front of everything EXCEPT the line. Both layer constants live in
## CharacterStats (LINE_Z/HP_Z) and must clear the highlight rings
## (z 50 — LevelItem/ProjectileBody) so no overlapping body, terrain or
## projectile can cover them.
##
## Run headless: godot --headless res://tests/test_issue598.tscn
## Exit code 0 = pass.

const Stats := preload("res://scripts/CharacterStats.gd")
const Bubble := preload("res://scripts/SpeechBubble.gd")

## The tallest in-world z the bar/line must beat: the highlight rings
## (LevelItem, ProjectileBody) sit at z 50.
const RING_Z := 50


func _ready() -> void:
	var ok := true
	ok = await _check_player_hp() and ok
	ok = await _check_npc_hp() and ok
	ok = await _check_line() and ok
	print("ISSUE598 PASS=", ok)
	get_tree().quit(0 if ok else 1)


## A real Player figure: its HealthBarBackground lifts to HP_Z.
func _check_player_hp() -> bool:
	var player := CharacterBody2D.new()
	player.set_script(load("res://scripts/Player.gd"))
	add_child(player)
	await get_tree().process_frame
	var result := _bar_ok(player, "player")
	player.queue_free()
	return result


## A real Npc figure: the same HP lift (issue #108 — no player/NPC
## difference). On hosts where the ncnn GDExtension cannot load
## (pre-existing: the prebuilt .so needs a newer GLIBC), Npc.gd fails
## to COMPILE through its BotController preload, so no bar is built —
## then the lift is pinned statically in the authored source instead.
func _check_npc_hp() -> bool:
	var npc := CharacterBody2D.new()
	npc.set_script(load("res://scripts/Npc.gd"))
	add_child(npc)
	await get_tree().process_frame
	if npc.get_node_or_null(NodePath("HealthBarBackground")) != null:
		var result := _bar_ok(npc, "npc")
		npc.queue_free()
		return result
	npc.queue_free()
	var source := FileAccess.get_file_as_string("res://scripts/Npc.gd")
	var lift := source.contains("background.z_index = Stats.HP_Z")
	print("ISSUE598 npc hp (source-level, script un-compilable on this "
			+ "host) ok=", lift)
	return lift


## The bar sits at exactly HP_Z — above the rings (50), strictly below
## the line's LINE_Z — and carries its fill child along (the fill is a
## child of the background, so the whole bar rides the same layer).
func _bar_ok(figure: Node, tag: String) -> bool:
	var bar := figure.get_node_or_null(NodePath("HealthBarBackground")) as CanvasItem
	if bar == null:
		print("FAIL ", tag, ": no HealthBarBackground")
		return false
	var fill: CanvasItem = null
	if bar.get_child_count() > 0:
		fill = bar.get_child(0) as CanvasItem
	var ok := bar.z_index == Stats.HP_Z \
			and bar.z_index > RING_Z \
			and bar.z_index < Stats.LINE_Z
	if not ok:
		print("FAIL ", tag, ": bar z=", bar.z_index, " (want ", Stats.HP_Z,
				", between ring ", RING_Z, " and line ", Stats.LINE_Z, ")")
	if fill != null and fill.z_index >= Stats.LINE_Z:
		print("FAIL ", tag, ": fill z=", fill.z_index, " pierces the line layer")
		ok = false
	print("ISSUE598 ", tag, " hp z=", bar.z_index, " ok=", ok)
	return ok


## A spoken line pops above everything: the balloon (a Control child of
## the figure) sits at LINE_Z, strictly above the same figure's HP bar.
func _check_line() -> bool:
	var player := CharacterBody2D.new()
	player.set_script(load("res://scripts/Player.gd"))
	add_child(player)
	await get_tree().process_frame
	Bubble.speak(player, "Front of everything!")
	await get_tree().process_frame
	var balloon := player.get_node_or_null(NodePath("SpeechBubble")) as CanvasItem
	var ok := balloon != null \
			and balloon.z_index == Stats.LINE_Z \
			and balloon.z_index > Stats.HP_Z \
			and balloon.z_index > RING_Z
	if not ok:
		print("FAIL line: balloon=", balloon,
				" z=", balloon.z_index if balloon != null else -1,
				" (want ", Stats.LINE_Z, " > hp ", Stats.HP_Z, ")")
	else:
		print("ISSUE598 line z=", balloon.z_index, " ok=true")
	player.queue_free()
	return ok
