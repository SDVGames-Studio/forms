extends Node
## Regression test for issue #161: the player's characters must be
## breakable — an NPC must be able to kill them.
##
## A minimal level stages ONE player figure (which never acts) against ONE
## enemy NPC. The duel runs for up to 150 simulated seconds (several
## turns). The NPC must land damage and reduce the player to 0 health
## within that window; the player must also be damageable directly
## (take_damage updates health and emits health_changed).
##
## Run headless: godot --headless res://tests/test_issue161.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true
	ok = _check_take_damage() and ok
	ok = await _check_npc_kills_player() and ok
	print("ISSUE161 ALL_OK=", ok)
	get_tree().quit(0 if ok else 1)


## Mechanism check: Player.take_damage must actually lower health.
func _check_take_damage() -> bool:
	var player: CharacterBody2D = load("res://Player.gd").new()
	add_child(player)
	var received := [0]
	player.health_changed.connect(func(h: int, _m: int) -> void: received[0] = h)
	player.take_damage(30)
	var ok: bool = player.health == 70 and received[0] == 70
	print("ISSUE161 take_damage: health=", player.health,
		" signal=", received[0], " ok=", ok)
	player.queue_free()
	return ok


## Gameplay check: an NPC kills an idle player within a few turns.
func _check_npc_kills_player() -> bool:
	var level := Node2D.new()
	level.name = "TestLevel"
	level.add_to_group("level")
	add_child(level)

	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	var gshape := CollisionShape2D.new()
	var gbox := RectangleShape2D.new()
	gbox.size = Vector2(4000, 120)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position = Vector2(1000, 600)
	level.add_child(ground)

	# Player figure: never acts, just stands there.
	var player: CharacterBody2D = load("res://Player.gd").new()
	player.name = "Player"
	player.display_name = "Player"
	var pshape := CollisionShape2D.new()
	var pcapsule := CapsuleShape2D.new()
	pcapsule.radius = 24.0
	pcapsule.height = 64.0
	pshape.shape = pcapsule
	player.add_child(pshape)
	player.position = Vector2(850, 480)
	level.add_child(player)

	# Enemy NPC close enough to attack (ATTACK_RANGE = 500).
	var npc: CharacterBody2D = load("res://Npc.gd").new()
	npc.name = "Enemy"
	npc.display_name = "Enemy"
	npc.difficulty = 2
	var nshape := CollisionShape2D.new()
	ncapsule(nshape)
	nshape.position = Vector2.ZERO
	npc.add_child(nshape)
	npc.position = Vector2(1150, 480)
	level.add_child(npc)

	for i in 20:
		await get_tree().physics_frame

	# Let the duel run: turns alternate, the player skips, the NPC shoots.
	# 150 simulated seconds comfortably spans several turns (TURN_TIME 30
	# s, shot handover ~1.5 s + projectile wait).
	var start_health: int = player.health
	var frames := 0
	while frames < 150 * 60 and player.health > 0 and is_instance_valid(player) \
			and not TurnController.game_over:
		await get_tree().physics_frame
		frames += 1

	var seconds := float(frames) / 60.0
	var dead: bool = player.health == 0 or TurnController.game_over
	var took_damage: bool = player.health < start_health
	# A few turns means well under the full window.
	var quick: bool = seconds <= 150.0
	print("ISSUE161 duel: start_health=", start_health,
		" end_health=", (player.health if is_instance_valid(player) else 0),
		" seconds=", snappedf(seconds, 0.1),
		" game_over=", TurnController.game_over,
		" took_damage=", took_damage, " dead=", dead, " ok=", took_damage and dead and quick)
	level.queue_free()
	return took_damage and dead and quick


func ncapsule(shape: CollisionShape2D) -> void:
	var capsule := CapsuleShape2D.new()
	capsule.radius = 24.0
	capsule.height = 64.0
	shape.shape = capsule
