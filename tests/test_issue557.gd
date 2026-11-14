extends Node
## Regression check for issue #557: the modular geometric character.
##
##  1. COMPONENT: ModularCharacterVisual is a pure VISUAL Control — no
##     physics/collision descendants and no gameplay-script dependency;
##  2. SQUARE EXAMPLE: SquareCharacter.tscn instantiates as the yellow
##     square with a bold outline and a full expressive face (eyes,
##     eyebrows and mouth all non-NONE);
##  3. CONFIGURABILITY: body color and every facial feature change at
##     runtime from code; each feature changes INDEPENDENTLY (the others
##     keep their values), and a mutated instance never leaks back into
##     the packed scene — the body color changes without modifying the
##     scene;
##  4. REUSE: the same component takes every ShapeVisual silhouette
##     (square, circle, triangle, star, ellipse), embedded the in-game
##     way (child of a CharacterBody2D), and the draw pass runs headless
##     without errors.
##
## Run headless: godot --headless res://tests/test_issue557.tscn
## Exit code 0 = pass.

const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")
const SquareScene := preload("res://scenes/characters/SquareCharacter.tscn")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _ready() -> void:
	# --- 1) pure visual component ---------------------------------------
	var root := SquareScene.instantiate()
	_check(root is Control and not (root is PhysicsBody2D),
			"SquareCharacter root is a Control, not a physics body")
	var square := root as Control
	_check(square.get_script() == VisualScript,
			"SquareCharacter uses ModularCharacterVisual")
	_check(square.find_children("*", "PhysicsBody2D", true, false).is_empty()
			and square.find_children("*", "CollisionShape2D", true, false).is_empty()
			and square.find_children("*", "Area2D", true, false).is_empty(),
			"the visual component carries no collision/physics nodes")

	# --- 2) the square example ------------------------------------------
	_check(square.body_shape == "square", "the example body is a square")
	_check(square.body_color == Color(1, 0.84, 0.2, 1),
			"the example body is the classic yellow")
	_check(square.outline_width >= 4.0 and square.outline_color.a > 0.99,
			"the example body has a bold opaque outline")
	_check(square.eye_style != VisualScript.EyeStyle.NONE
			and square.eyebrow_style != VisualScript.EyebrowStyle.NONE
			and square.mouth_style != VisualScript.MouthStyle.NONE,
			"the example face has eyes, eyebrows and a mouth")
	add_child(square)

	# --- 3) configurability, independently -------------------------------
	square.body_color = Color(0.2, 0.5, 1.0)
	_check(square.body_color == Color(0.2, 0.5, 1.0),
			"body color changes from code")
	square.eye_style = VisualScript.EyeStyle.WIDE
	square.eyebrow_style = VisualScript.EyebrowStyle.ANGRY
	square.mouth_style = VisualScript.MouthStyle.OPEN
	_check(square.eye_style == VisualScript.EyeStyle.WIDE
			and square.eyebrow_style == VisualScript.EyebrowStyle.ANGRY
			and square.mouth_style == VisualScript.MouthStyle.OPEN,
			"every facial feature restyles from code")
	square.mouth_style = VisualScript.MouthStyle.FROWN
	_check(square.eye_style == VisualScript.EyeStyle.WIDE
			and square.eyebrow_style == VisualScript.EyebrowStyle.ANGRY,
			"facial features restyle independently of each other")

	var again: Control = SquareScene.instantiate()
	_check(again.body_color == Color(1, 0.84, 0.2, 1),
			"a fresh instance is still yellow — the color change never "
			+ "touched the scene")
	add_child(again)

	# --- 4) reuse for other geometric shapes ------------------------------
	var host := CharacterBody2D.new()
	add_child(host)
	for shape in ["square", "circle", "triangle", "star", "ellipse"]:
		var visual: Control = VisualScript.new()
		visual.body_shape = shape
		visual.size = Vector2(64, 64)
		host.add_child(visual)
	_check(host.get_child_count() == 5,
			"every ShapeVisual silhouette embeds under a CharacterBody2D "
			+ "(the in-game visual pattern)")

	# A frame so every queued draw pass really runs headless.
	await get_tree().process_frame
	_check(is_instance_valid(square) and is_instance_valid(host),
			"the draw pass leaves every instance alive")

	if failures == 0:
		print("PASS: issue #557 modular geometric character")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
