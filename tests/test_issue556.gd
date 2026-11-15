extends Node
## Regression check for issue #556: expressive characters in gameplay.
##
##  1. LIVE PLAYER: a real Player figure (square team, then triangle)
##     wears a ModularCharacterVisual body — the authored ColorRect is
##     hidden, the modular visual carries the team color + silhouette +
##     a resting personality, and the Weapon stays the LAST child;
##  2. LIVE NPC: a real Npc (square team and star team) gets the same
##     modular body ("VisualShape") with its team look; the gameplay
##     surfaces stay put (collision layers, health bar);
##  3. PERSONALITIES: different member indices rest in different moods,
##     every personality is a valid expression, and the helper is total
##     (wraps, negative safe);
##  4. API PARITY: set_shape/set_shape_color speak the ShapeVisual
##     protocol, so FigurePose.is_body_child accepts the visual (gravity
##     alignment, animator targeting and the hit flash route through it);
##  5. RE-RUN RESTYLE: calling the team-shape apply again (GameConfig
##     re-run) restyles the SAME node — no stale first silhouette;
##  6. PURE VISUAL: the swap never writes physics — the collision
##     transform and velocity stay put while the look changes.
##
## Run headless: godot --headless res://tests/test_issue556.tscn
## Exit code 0 = pass.

const VisualScript := preload("res://scripts/ModularCharacterVisual.gd")
const PlayerScript := preload("res://scripts/Player.gd")
const NpcScript := preload("res://scripts/Npc.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _ready() -> void:
	# --- the stage: a floor keeps the real figures grounded -------------
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(2000, 40)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(0, 20)
	add_child(floor_body)

	# --- 1) a live Player figure wears the modular character ------------
	# Authored exactly like the levels: a body ColorRect + a Weapon node.
	var player := PlayerScript.new()
	player.name = "Player"
	player.position = Vector2(0, -32)  # 64 px body resting on the floor
	player.display_name = "Player 1"
	player.team_shape = "triangle"
	player.team_color = Color(0.2, 0.6, 0.95, 1)
	var rect := ColorRect.new()
	rect.name = "PlayerVisual"
	rect.offset_left = -32.0
	rect.offset_top = -32.0
	rect.offset_right = 32.0
	rect.offset_bottom = 32.0
	player.add_child(rect)
	# The levels author a collision capsule/box — without it the figure
	# never lands and the physics check below could never settle.
	var body_shape := CollisionShape2D.new()
	var body_rect := RectangleShape2D.new()
	body_rect.size = Vector2(64, 64)
	body_shape.shape = body_rect
	body_shape.name = "PlayerShape"
	player.add_child(body_shape)
	var weapon_node := Node2D.new()
	weapon_node.name = "Weapon"
	player.add_child(weapon_node)
	add_child(player)

	var p_visual: Node = player.get_node_or_null("PlayerVisualShape")
	_check(p_visual != null and p_visual.has_method("apply_team_look"),
			"a square/triangle Player wears the ModularCharacterVisual body")
	_check(p_visual != null and p_visual.body_shape == "triangle",
			"the Player body visual carries the team silhouette")
	_check(p_visual != null
			and p_visual.body_color == Color(0.2, 0.6, 0.95, 1),
			"the Player body visual carries the team color")
	_check(not rect.visible,
			"the authored square ColorRect body is hidden")
	_check(p_visual != null
			and int(p_visual.get_index()) < int(weapon_node.get_index()),
			"the Weapon draws in front of the body visual")
	_check(p_visual != null
			and int(p_visual.expression)
				in VisualScript.PERSONALITIES,
			"the Player rests in a personality expression")
	var player_expr := int(p_visual.expression) if p_visual != null else -1

	# --- 2) live Npcs: square AND star teams get the same body ----------
	var npc := NpcScript.new()
	npc.name = "Npc"
	npc.position = Vector2(-200, -29)  # capsule resting on the floor
	npc.team_shape = "square"
	npc.team_color = Color(0.9, 0.3, 0.3, 1)
	add_child(npc)

	var n_visual: Node = npc.get_node_or_null("VisualShape")
	_check(n_visual != null and n_visual.has_method("apply_team_look"),
			"a SQUARE-team Npc wears the ModularCharacterVisual body too")
	_check(n_visual != null and n_visual.body_shape == "square",
			"the square silhouette stays a square")
	_check(n_visual != null
			and n_visual.body_color == Color(0.9, 0.3, 0.3, 1),
			"the Npc body visual carries the team color")
	_check(npc._visual != null and not npc._visual.visible,
			"the Npc's authored/code ColorRect body is hidden")
	_check(npc.collision_layer == 2 and npc.collision_mask == 1 | 2 | 8,
			"the Npc collision layers are untouched")
	var npc_weapon: Node = npc.get_node_or_null("Weapon")
	_check(npc_weapon != null
			and npc.get_child(npc.get_child_count() - 1) == npc_weapon,
			"the Npc Weapon stays the LAST child")
	var npc_expr := int(n_visual.expression) if n_visual != null else -2
	_check(npc_expr in VisualScript.PERSONALITIES,
			"the Npc rests in a personality expression")

	var npc2 := NpcScript.new()
	npc2.name = "Npc2"
	npc2.position = Vector2(200, -29)
	npc2.team_shape = "star"
	npc2.team_color = Color(0.95, 0.75, 0.1, 1)
	add_child(npc2)
	var n2_visual: Node = npc2.get_node_or_null("VisualShape")
	_check(n2_visual != null and n2_visual.body_shape == "star",
			"a star-team Npc carries the star silhouette")
	_check(n2_visual != null and n_visual != null
			and int(n2_visual.expression) != npc_expr
			and player_expr != npc_expr,
			"different members rest in different personalities")

	# --- 3) the personality helper is total and stays in the set --------
	var seen: Array = []
	for i in 8:
		var mood: int = VisualScript.personality_for_index(i)
		_check(mood in VisualScript.PERSONALITIES,
				"personality_for_index(%d) stays a valid expression" % i)
		if not seen.has(mood):
			seen.append(mood)
	_check(seen.size() >= 2,
			"consecutive members cycle through several personalities")
	_check(VisualScript.personality_for_index(-1)
			in VisualScript.PERSONALITIES,
			"personality_for_index is safe for negative indices")

	# --- 4) ShapeVisual API parity ---------------------------------------
	var standalone: Control = VisualScript.new()
	standalone.size = Vector2(64, 64)
	add_child(standalone)
	standalone.set_shape("circle")
	standalone.set_shape_color(Color(0.5, 0.2, 0.8, 1))
	_check(standalone.body_shape == "circle"
			and standalone.body_color == Color(0.5, 0.2, 0.8, 1),
			"set_shape/set_shape_color speak the ShapeVisual protocol")
	_check(FigurePose.is_body_child(standalone),
			"FigurePose.is_body_child accepts the modular visual")
	_check(FigurePose.is_body_child(n_visual),
			"the live Npc body rotates with gravity like the old visual")
	var capsule: Node = null
	for child in npc.get_children():
		var shape_child := child as CollisionShape2D
		if shape_child != null and shape_child.shape is CapsuleShape2D:
			capsule = shape_child
			break
	_check(capsule != null and capsule.position == Vector2.ZERO
			and capsule.rotation == 0.0,
			"the Npc collision capsule is untouched by the visual swap")

	# --- 5) re-runs restyle the SAME node --------------------------------
	# GameConfig drives apply_team_setup — point its classic team fields
	# at a fresh look so the re-run must visibly restyle the figure.
	GameConfig.team_shape = "circle"
	GameConfig.team_color = Color(0.95, 0.75, 0.1, 1)
	var before: Node = npc2.get_node("VisualShape")
	npc2.set_team_shape("circle")
	var after: Node = npc2.get_node_or_null("VisualShape")
	_check(after == before and after.body_shape == "circle",
			"a team-shape re-run restyles the same node in place")
	_check(after.body_color == Color(0.95, 0.75, 0.1, 1),
			"the restyle keeps the team color")
	player.apply_team_setup()
	_check(player.get_node_or_null("PlayerVisualShape") == p_visual
			and p_visual.body_shape == "circle",
			"a Player GameConfig re-run restyles the same node in place")

	# --- 6) the swap is purely visual ------------------------------------
	# Let the figures settle first, then re-apply the look and make sure
	# the settled physics state is byte-identical afterwards.
	for i in 6:
		await get_tree().physics_frame
	var pos_before := player.global_position
	var vel_before: Vector2 = player.velocity
	player._apply_team_shape()
	for i in 6:
		await get_tree().physics_frame
	_check(player.global_position == pos_before
			and player.velocity == vel_before,
			"re-applying the look never writes the figure's physics")

	# A frame so every queued draw pass really runs headless.
	for i in 3:
		await get_tree().process_frame
	_check(is_instance_valid(player) and is_instance_valid(npc)
			and is_instance_valid(npc2) and is_instance_valid(standalone),
			"the draw pass leaves every instance alive")

	if failures == 0:
		print("PASS: issue #556 expressive gameplay characters")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
