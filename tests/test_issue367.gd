extends Node
## Regression check for issue #367 (rework v3: the vision MASK layer).
##  - The level configuration menu carries a "Night regime" check that
##    reads/writes GameConfig.night_regime and restores the stored
##    choice when reopened (unchanged since the first round).
##  - NightRegime.apply(level) builds a dedicated NightMaskLayer canvas
##    layer ABOVE the world canvas (0) and the background (-100) but
##    BELOW the HUD (OSD/menus live at 10+) — owner rework 2026-11-07:
##    a new layer must hide ALL beyond characters' vision, background
##    included, and all beyond vision must be totally black — with a
##    full-rect black ColorRect whose shader carves the vision out. No
##    CanvasModulate is used anymore (it never darkened the background
##    canvas layer, and the old PointLight2D wedge lit only the ground).
##  - Every player-team figure that can aim gets ONE vision wedge that
##    follows the figure's LIVE aim direction (view angle AND facing);
##    enemy figures get none.
##  - Every active ShotLight is revealed through the mask (the issue's
##    flash rule: a shot beyond vision shows its flash), and a freed
##    light stops being revealed.
##
## Run headless: godot --headless res://tests/test_issue367.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://LevelConfigMenu.tscn")

var _fails: Array = []


## A minimal stand-in for a Player/Npc figure: enough aim plumbing for
## the night mask (aim_dir in the same frame Player uses, plus a Weapon
## child exposing the facing sign).
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

	# 2) apply() builds the mask layer over the world, under the HUD.
	var level := Node2D.new()
	add_child(level)
	var night := NightRegime.apply(level)
	await get_tree().process_frame
	var layer: CanvasLayer = level.get_node_or_null("NightMaskLayer")
	_check("apply() adds the mask canvas layer", layer is CanvasLayer)
	_check("the mask layer sits above the world and background",
		layer != null and layer.layer > 0)
	_check("the mask layer sits below the HUD (layer 10)",
		layer != null and layer.layer < 10)
	var mask: ColorRect = null
	if layer != null:
		mask = layer.get_node_or_null("NightMask")
	_check("the mask is a full-rect black overlay",
		mask is ColorRect and mask.color == Color.BLACK
		and mask.anchor_left == 0.0 and mask.anchor_right == 1.0
		and mask.anchor_top == 0.0 and mask.anchor_bottom == 1.0)
	_check("the mask ignores the mouse", mask != null
		and mask.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("the mask hides via the night shader", mask != null
		and mask.material is ShaderMaterial
		and (mask.material as ShaderMaterial).shader.resource_path
			== "res://scripts/night_mask.gdshader")
	_check("no CanvasModulate darkness is used anymore",
		level.get_node_or_null("NightModulate") == null)

	# 3) Vision wedges: teammates only, aimed along the live aim.
	var hero := StubFigure.new()
	hero.name = "Hero"
	hero.add_to_group("player_team")
	hero.position = Vector2(100, 100)
	level.add_child(hero)
	var weapon := StubWeapon.new()
	weapon.name = "Weapon"
	hero.add_child(weapon)
	var foe := StubFigure.new()
	foe.name = "Foe"
	foe.add_to_group("enemy_team")
	foe.position = Vector2(500, 120)
	level.add_child(foe)
	await get_tree().process_frame
	var mat: ShaderMaterial = null
	if mask != null:
		mat = mask.material
	var wedge_count := -1
	var wedges = []
	if mat != null:
		wedge_count = mat.get_shader_parameter("wedge_count")
		wedges = mat.get_shader_parameter("wedges")
	_check("exactly one vision wedge — the teammate's",
		wedge_count == 1)
	_check("the wedge sits on the teammate",
		wedges.size() > 0 and is_equal_approx(wedges[0].x, 100.0)
		and is_equal_approx(wedges[0].y, 100.0))
	_check("the wedge starts aimed horizontally ahead",
		wedges.size() > 0 and wedges[0].z > 0.99
		and absf(wedges[0].w) < 0.01)
	_check("the wedge geometry matches the issue's mock",
		mat != null
		and is_equal_approx(mat.get_shader_parameter("vision_radius"),
			NightRegime.VISION_RADIUS))
	_check("the mask attaches no vision nodes to the figure",
		hero.get_child_count() == 1  # just the stub Weapon
		and hero.get_node_or_null("VisionField") == null)

	# 3b) The wedge follows the LIVE aim (owner rework): raising the
	# view angle must rotate the wedge up, and flipping the facing must
	# mirror it.
	hero.view_angle = PI / 4.0
	await get_tree().process_frame
	if mat != null:
		wedges = mat.get_shader_parameter("wedges")
	_check("the wedge follows the view angle",
		wedges.size() > 0
		and absf(wedges[0].z - sqrt(0.5)) < 0.01
		and absf(wedges[0].w + sqrt(0.5)) < 0.01)
	weapon.facing = -1.0
	hero.view_angle = 0.0
	await get_tree().process_frame
	if mat != null:
		wedges = mat.get_shader_parameter("wedges")
	_check("the wedge follows the weapon facing",
		wedges.size() > 0 and wedges[0].z < -0.99
		and absf(wedges[0].w) < 0.01)

	# 3c) A dead (freed) teammate's wedge disappears.
	var mate := StubFigure.new()
	mate.name = "Mate"
	mate.add_to_group("player_team")
	mate.position = Vector2(150, 100)
	level.add_child(mate)
	await get_tree().process_frame
	if mat != null:
		wedge_count = mat.get_shader_parameter("wedge_count")
	_check("a second teammate adds a second wedge", wedge_count == 2)
	mate.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if mat != null:
		wedge_count = mat.get_shader_parameter("wedge_count")
	_check("a freed teammate's wedge disappears", wedge_count == 1)

	# 4) Light sources: every active ShotLight is revealed.
	var flash := ShotLight.create(Color.ORANGE, 120.0)
	level.add_child(flash)
	flash.global_position = Vector2(700, 60)
	await get_tree().process_frame
	var light_count := -1
	var lights = []
	if mat != null:
		light_count = mat.get_shader_parameter("light_count")
		lights = mat.get_shader_parameter("lights")
	_check("the mask reveals the active light", light_count == 1)
	_check("the light hole carries position and radius",
		lights.size() > 0 and is_equal_approx(lights[0].x, 700.0)
		and is_equal_approx(lights[0].y, 60.0)
		and is_equal_approx(lights[0].z, 120.0))
	flash.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if mat != null:
		light_count = mat.get_shader_parameter("light_count")
	_check("a freed light stops being revealed", light_count == 0)

	level.queue_free()
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("ISSUE367 ok=true")
		get_tree().quit(0)
	else:
		print("ISSUE367 ok=false (%d failures)" % _fails.size())
		for fail in _fails:
			print("ISSUE367 failure: %s" % fail)
		get_tree().quit(1)
