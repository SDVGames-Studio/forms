extends Node
## Regression check for issue #395: character lines in the night regime.
##  - NightRegime.apply() also builds a CharacterLinesLayer canvas layer
##    IN FRONT of the night mask (so balloons never black out) but below
##    the HUD (OSD/menus at 10).
##  - While a regime is active SpeechBubble.speak() adds the balloon to
##    that layer (not to the figure) and it follows the speaker's
##    on-screen position; without a regime the balloon is a figure child
##    exactly as before (issue #335/#311 path unchanged).
##  - Teammates' balloons are always visible at night.
##  - An ENEMY's balloon is visible exactly while the enemy is seen:
##    inside a teammate's vision wedge, or revealed by a light source
##    (ShotLight) — and hidden again once the light is gone.
##  - Still one balloon per figure: a new line replaces the old balloon.
##
## Run headless: godot --headless res://tests/test_issue395.tscn
## Exit code 0 = pass.

const Bubble := preload("res://scripts/SpeechBubble.gd")

var _fails: Array = []


## A minimal stand-in for a Player/Npc figure (same shape as
## test_issue367): aim_dir in the frame Player uses, plus a Weapon child
## exposing the facing sign.
class StubFigure extends Node2D:
	var view_angle := 0.0

	func aim_dir(facing: float, _dir: float) -> Vector2:
		return Vector2(cos(view_angle) * facing, -sin(view_angle))


## A minimal stand-in for a Weapon: the facing sign the mask asks for.
class StubWeapon extends Node2D:
	var facing := 1.0

	func facing_sign() -> float:
		return facing


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE395 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	# 1) Day path unchanged: with no night regime the balloon is a HUD
	# child of the speaking figure (issue #335), visible.
	var plain := Node2D.new()
	add_child(plain)
	var hero0 := StubFigure.new()
	hero0.name = "Hero0"
	hero0.add_to_group("player_team")
	plain.add_child(hero0)
	Bubble.speak(hero0, "Day light", Bubble.Kind.SPEECH)
	await get_tree().process_frame
	var day_bubble: Node = hero0.get_node_or_null("SpeechBubble")
	_check("day: the balloon still hangs on the figure",
		day_bubble != null and day_bubble.get_parent() == hero0)
	_check("day: the balloon is visible", day_bubble != null
		and day_bubble.visible)
	plain.queue_free()

	# 2) Night regime: apply() builds the character-lines layer in front
	# of the mask, below the HUD.
	var level := Node2D.new()
	add_child(level)
	var night := NightRegime.apply(level)
	await get_tree().process_frame
	var mask_layer: CanvasLayer = level.get_node_or_null("NightMaskLayer")
	var lines: CanvasLayer = level.get_node_or_null("CharacterLinesLayer")
	_check("apply() adds the character-lines layer", lines is CanvasLayer)
	_check("the lines layer sits above the night mask",
		lines != null and mask_layer != null
		and lines.layer > mask_layer.layer)
	_check("the lines layer sits below the HUD (layer 10)",
		lines != null and lines.layer < 10)
	_check("the regime exposes its lines layer",
		night != null and night.lines_layer() == lines)

	# 3) The cast: one teammate whose wedge aims along +x, three enemies.
	var hero := StubFigure.new()
	hero.name = "Hero"
	hero.add_to_group("player_team")
	hero.position = Vector2(100, 100)
	level.add_child(hero)
	var weapon := StubWeapon.new()
	weapon.name = "Weapon"
	hero.add_child(weapon)
	var foe_wedge := StubFigure.new()  # straight ahead of the teammate
	foe_wedge.name = "FoeWedge"
	foe_wedge.add_to_group("enemy_team")
	foe_wedge.position = Vector2(400, 100)
	level.add_child(foe_wedge)
	var foe_far := StubFigure.new()  # beyond every wedge and light
	foe_far.name = "FoeFar"
	foe_far.add_to_group("enemy_team")
	foe_far.position = Vector2(400, 500)
	level.add_child(foe_far)
	var foe_side := StubFigure.new()  # near, but outside the aim angle
	foe_side.name = "FoeSide"
	foe_side.add_to_group("enemy_team")
	foe_side.position = Vector2(130, 165)
	level.add_child(foe_side)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("is_lit() sees the enemy in the wedge",
		night != null and night.is_lit(Vector2(400, 100)))
	_check("is_lit() does not see the distant enemy",
		night != null and not night.is_lit(Vector2(400, 500)))
	_check("is_lit() does not see the off-angle enemy",
		night != null and not night.is_lit(Vector2(130, 165)))

	# 4) Balloons at night: on the lines layer, teammates always shown,
	# enemies exactly while seen.
	Bubble.speak(hero, "Team talk", Bubble.Kind.SPEECH)
	Bubble.speak(foe_wedge, "In your sights", Bubble.Kind.SHOUT)
	Bubble.speak(foe_far, "Hidden", Bubble.Kind.THOUGHT)
	Bubble.speak(foe_side, "Off angle", Bubble.Kind.SPEECH)
	await get_tree().process_frame
	var hero_bubble: Node = null
	var wedge_bubble: Node = null
	var far_bubble: Node = null
	var side_bubble: Node = null
	if lines != null:
		for child in lines.get_children():
			if child.figure == hero:
				hero_bubble = child
			elif child.figure == foe_wedge:
				wedge_bubble = child
			elif child.figure == foe_far:
				far_bubble = child
			elif child.figure == foe_side:
				side_bubble = child
	_check("night: all four balloons moved onto the lines layer",
		hero_bubble != null and wedge_bubble != null
		and far_bubble != null and side_bubble != null)
	_check("night: no balloon hangs on a figure",
		hero.get_node_or_null("SpeechBubble") == null
		and foe_far.get_node_or_null("SpeechBubble") == null)
	_check("night: the teammate's line stays visible",
		hero_bubble != null and hero_bubble.visible)
	_check("night: the balloon follows the speaker on screen",
		hero_bubble != null and hero_bubble.position
			== hero.get_global_transform_with_canvas().origin)
	_check("night: an enemy in the wedge shows its line",
		wedge_bubble != null and wedge_bubble.visible)
	_check("night: a distant enemy's line is hidden",
		far_bubble != null and not far_bubble.visible)
	_check("night: an off-angle enemy's line is hidden",
		side_bubble != null and not side_bubble.visible)

	# 5) A light source reveals the distant enemy's line (the issue's
	# "highlighted with some light source" rule) — and hides it again
	# once the light is gone.
	var flash := ShotLight.create(Color.ORANGE, 150.0)
	level.add_child(flash)
	flash.global_position = foe_far.position
	await get_tree().process_frame
	await get_tree().process_frame
	_check("night: a light reveals the enemy's line",
		far_bubble != null and far_bubble.visible)
	flash.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check("night: the line hides again once the light is gone",
		far_bubble != null and not far_bubble.visible)

	# 6) One balloon per figure: a new line replaces the old balloon.
	var old_bubble := hero_bubble
	Bubble.speak(hero, "Again", Bubble.Kind.SPEECH)
	await get_tree().process_frame
	var fresh: Node = null
	if lines != null:
		for child in lines.get_children():
			if child.figure == hero:
				fresh = child
	_check("a new line replaces the figure's balloon",
		fresh != null and fresh != old_bubble
		and (old_bubble == null or not is_instance_valid(old_bubble)
			or old_bubble.get_parent() == null))
	_check("still one balloon per figure on the layer",
		lines != null and lines.get_child_count() == 4)

	level.queue_free()
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE395 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE395 ok=false (%d failures)" % _fails.size())
		for fail in _fails:
			print("ISSUE395 failure: %s" % fail)
		get_tree().quit(1)
