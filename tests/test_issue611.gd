extends Node
## Regression check for issue #611 (slice 1): Player and Npc share ONE
## Character base (scripts/Character.gd) — a pure body with the public
## controller API — and neither carries a copy of the shared mechanics.
##
##  1. INHERITANCE: both figure scripts extend Character.gd directly and
##     inherit the shared state/helpers (health, view_angle, aim_dir,
##     current_tangent, reanchor_gravity_frame) plus their classic
##     per-side defaults (name/color).
##  2. PURE BODY: the base source reads no Input and hosts no AI — the
##     brains stay in Player.gd / Npc.gd.
##  3. NO DUPLICATION: take_damage / heal / _build_health_bar /
##     set_shielded exist ONLY in the base.
##  4. API MECHANICS: move() walks the gravity-frame tangent and plants
##     on 0; aim() slews and clamps the view angle; jump() refuses
##     mid-air; fire() reports the missing Weapon.
##  5. BEHAVIOR KEPT: damage/shield/heal/death flow through the base for
##     BOTH classes exactly as before (player still emits
##     health_changed; the NPC dies and frees at 0 health).
##
## Run headless: godot --headless res://tests/test_issue611.tscn
## Exit code 0 = pass.

const CharacterScript := preload("res://scripts/Character.gd")
const PlayerScript := preload("res://scripts/Player.gd")
const NpcScript := preload("res://scripts/Npc.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)


func _ready() -> void:
	# --- 1) inheritance -------------------------------------------
	for pair in [["Player", PlayerScript], ["Npc", NpcScript]]:
		var name: String = pair[0]
		var script: Script = pair[1]
		_check(script.get_base_script() == CharacterScript,
				"%s.gd extends Character.gd directly" % name)
	var npc := NpcScript.new()
	_check(npc.display_name == "Enemy" and npc.team_color == Color(0.75, 0.2, 0.45, 1),
			"NPC keeps its classic name/color defaults (%s / %s)"
			% [npc.display_name, str(npc.team_color)])
	for method in ["move", "aim", "fire", "jump", "aim_dir", "current_tangent",
			"current_gravity", "reanchor_gravity_frame", "take_damage", "heal",
			"set_shielded", "set_display_name"]:
		_check(npc.has_method(method), "NPC inherits %s() from Character" % method)
	npc.free()
	var player := PlayerScript.new()
	for method in ["move", "aim", "fire", "jump"]:
		_check(player.has_method(method), "Player inherits %s() from Character" % method)
	player.free()

	# --- 2) pure body ----------------------------------------------
	var base_src := FileAccess.get_file_as_string("res://scripts/Character.gd")
	_check(not base_src.contains("Input."), "Character.gd reads no Input (pure body)")
	_check(not base_src.contains("_nearest_opponent") and not base_src.contains("TurnController.active_member"),
			"Character.gd hosts no AI heuristics")

	# --- 3) no duplication -----------------------------------------
	for pair in [["Player", "res://scripts/Player.gd"], ["Npc", "res://scripts/Npc.gd"]]:
		var name: String = pair[0]
		var src := FileAccess.get_file_as_string(pair[1])
		for shared in ["func take_damage", "func heal", "func _build_health_bar",
				"func set_shielded", "func _update_bar", "func _die"]:
			_check(not src.contains(shared),
					"%s.gd carries no copy of %s (it lives in Character)"
					% [name, shared.replace("func ", "")])

	# --- 4) API mechanics ------------------------------------------
	var fig: CharacterBody2D = NpcScript.new()
	fig.velocity = Vector2(12.0, -7.0)
	fig.move(1.0)
	_check(absf(fig.velocity.x - float(fig.SPEED)) < 0.001
			and absf(fig.velocity.y - (-7.0)) < 0.001,
			"move(1) walks the flat-frame tangent at SPEED, keeps the fall component (got %s)"
			% str(fig.velocity))
	fig.move(0.0)
	_check(absf(fig.velocity.x) < 0.001 and absf(fig.velocity.y - (-7.0)) < 0.001,
			"move(0) plants the figure, keeps the fall component (got %s)"
			% str(fig.velocity))
	fig.move(-0.25)
	_check(absf(fig.velocity.x + 0.25 * float(fig.SPEED)) < 0.001,
			"move(-0.25) walks back at a quarter speed (got %s)" % str(fig.velocity))
	fig.aim(0.5)
	_check(absf(fig.view_angle - 0.5) < 0.001, "aim(0.5) slews the view angle")
	fig.aim(100.0)
	_check(absf(fig.view_angle - float(fig.VIEW_MAX)) < 0.001,
			"aim clamps at +VIEW_MAX (got %f)" % fig.view_angle)
	fig.view_angle = 0.0
	fig.aim(-100.0)
	_check(absf(fig.view_angle + float(fig.VIEW_MAX)) < 0.001,
			"aim clamps at -VIEW_MAX (got %f)" % fig.view_angle)
	_check(fig.jump() == false and fig.velocity.y == -7.0,
			"jump() refuses mid-air and leaves the velocity alone")
	_check(fig.fire() == false, "fire() reports the missing Weapon")
	var aim_vec: Vector2 = fig.aim_dir(1.0, 0.0)
	fig.view_angle = 0.0
	var flat_vec: Vector2 = fig.aim_dir(1.0, 0.0)
	_check(absf(flat_vec.angle() - 0.0) < 0.001,
			"aim_dir() at view 0 faces the flat tangent (got %s)" % str(flat_vec))
	_check(absf(aim_vec.angle() - float(fig.VIEW_MAX)) < 0.001,
			"aim_dir() carries the slewed view angle away from the floor (got %s)"
			% str(aim_vec))
	fig.free()

	# --- 5) behavior kept -------------------------------------------
	var hero: CharacterBody2D = PlayerScript.new()
	add_child(hero)
	var received := [-1]
	hero.health_changed.connect(func(h: int, _m: int) -> void: received[0] = h)
	hero.take_damage(30)
	_check(hero.health == 70 and received[0] == 70,
			"player damage still flows and emits health_changed")
	hero.set_shielded(true)
	hero.take_damage(30)
	_check(hero.health == 70 and not hero.shielded,
			"the shield still blocks exactly ONE hit and is consumed")
	hero.heal(10)
	_check(hero.health == 80, "heal still clamps upward (80)")
	hero.queue_free()

	var enemy: CharacterBody2D = NpcScript.new()
	add_child(enemy)
	enemy.take_damage(30)
	_check(enemy.health == 70, "NPC damage flows through the base (70)")
	enemy.take_damage(999)
	_check(enemy.health == 0, "NPC dies at 0 health through the base")
	for i in 30:
		await get_tree().physics_frame
	_check(not is_instance_valid(enemy) or enemy.is_queued_for_deletion(),
			"the dead NPC still shrink-frees via the shared death tween")

	print("ISSUE611 failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
