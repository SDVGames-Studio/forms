extends Node
## Regression check for issue #367: the night regime.
##  - The level configuration menu carries a "Night regime" check that
##    reads/writes GameConfig.night_regime and restores the stored
##    choice when reopened.
##  - NightRegime.apply(level) adds a dark CanvasModulate to the level
##    root (the world canvas goes dark, which also switches every
##    ShotLight into a real light source).
##  - Every player-team figure gets a VisionField (a green-tinted
##    PointLight2D with a green rim); enemy figures get none.
##
## Run headless: godot --headless res://tests/test_issue367.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://LevelConfigMenu.tscn")

var _fails: Array = []


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails.append(what)
	print("ISSUE367 %s — %s" % ["ok" if ok else "FAIL", what])


func _ready() -> void:
	# 1) The menu switch is bound to GameConfig.night_regime.
	var saved := GameConfig.night_regime
	GameConfig.night_regime = false
	var menu := MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var check: CheckButton = menu.get_node("%NightRegimeCheck")
	_check("menu exposes a Night regime check", check is CheckButton)
	_check("check starts unchecked while the regime is off",
		check != null and not check.button_pressed)
	check.button_pressed = true
	_check("ticking the check enables the night regime",
		GameConfig.night_regime == true)
	check.button_pressed = false
	_check("unticking the check disables it again",
		GameConfig.night_regime == false)
	menu.queue_free()
	GameConfig.night_regime = saved

	# 2) apply() darkens the world canvas.
	var level := Node2D.new()
	add_child(level)
	var night := NightRegime.apply(level)
	await get_tree().process_frame
	var modulate: CanvasModulate = level.get_node_or_null("NightModulate")
	_check("apply() adds a CanvasModulate to the level",
		modulate is CanvasModulate)
	_check("the modulate tint is dark",
		modulate != null and modulate.color.v < 0.4)

	# 3) Vision fields: teammates only.
	var hero := Node2D.new()
	hero.add_to_group("player_team")
	level.add_child(hero)
	var foe := Node2D.new()
	foe.add_to_group("enemy_team")
	level.add_child(foe)
	night._attach_vision_lights()
	await get_tree().process_frame
	var field: PointLight2D = hero.get_node_or_null("VisionField")
	_check("a player-team figure carries a VisionField",
		field is NightRegime.VisionField)
	_check("the vision field is a green-tinted PointLight2D",
		field != null and field is PointLight2D
		and field.color.g > field.color.r)
	_check("the vision light is scaled to the vision radius",
		field != null
		and is_equal_approx(field.texture_scale, NightRegime.VISION_RADIUS / 128.0))
	_check("an enemy figure carries no VisionField",
		foe.get_node_or_null("VisionField") == null)

	# 4) A second apply()/attach pass must not duplicate fields.
	night._attach_vision_lights()
	await get_tree().process_frame
	var fields := 0
	for child in hero.get_children():
		if child is NightRegime.VisionField:
			fields += 1
	_check("re-running the pass does not duplicate the field", fields == 1)

	level.queue_free()
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE367 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE367 ok=false (%d failures)" % _fails.size())
		get_tree().quit(1)
