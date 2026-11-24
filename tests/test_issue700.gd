extends Node
## Regression check for issue #700: a character must never turn to the
## opposite side by itself because of the ground's shape under it — only
## the player or the computer (a walk ORDER driven through
## Character.move()) may flip the figure's facing.
##
## The bug: Weapon derived the facing from the raw velocity along the
## walking tangent. On curved ground, releasing the walk key leaves a
## one-tick BACKWARDS tangential velocity (move_and_slide converts the
## leftover along-gravity component into tangent motion on a tilted
## floor), so the figure flipped left the moment D was released.
##
## Checks:
##  1. COMMAND BOOKKEEPING: move() records the commanded axis (clamped
##     to [-1, 1]); walk_command() exposes it; 0.0 = planted.
##  2. PLAYER TURN: move(+1) turns the facing right, move(-1) turns it
##     left — the ONLY way the facing ever changes now.
##  3. NO AUTO-TURN: a passive backwards tangential velocity (the exact
##     release-on-curve artifact) never flips the facing; a passive
##     forward one does not either — knockback/explosions/ground can
##     shove a figure around without turning it.
##  4. COMPUTER TURN: the bot executor actuates the very same move() API
##     (BotController orders walks through figure.call("move", ±1.0)),
##     so the facing flips for the computer exactly like for the player.
##  5. LEGACY FALLBACK: a plain body without walk_command() (stand-ins
##     that predate the accessor) keeps the old velocity-based facing.
##
## Run headless: godot --headless res://tests/test_issue700.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")

var failures: Array[String] = []


## A figure whose brain is the TEST: _control stays silent so the test
## drives move() itself and can pre-plant the exact post-slide velocity
## the real curve release produced (the ground artifact the old code
## misread as a walk).
class TestFigure extends Character:
	func _control(_delta: float) -> void:
		pass


## A pre-#700 plain body: no walk_command, no gravity-frame accessors —
## pins the Weapon's velocity fallback for parents that predate them.
class LegacyBody extends CharacterBody2D:
	pass


func _check(ok: bool, label: String) -> void:
	print("ISSUE700 ", label, " -> ", ok)
	if not ok:
		failures.append(label)


## A figure with a collision box and a real Weapon child named "Weapon"
## (the scene convention Character._keep_weapon_in_front relies on).
func _make_figure() -> TestFigure:
	var figure := TestFigure.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	figure.add_child(shape)
	var gun := Node2D.new()
	gun.name = "Weapon"
	gun.set_script(WeaponScript)
	figure.add_child(gun)
	add_child(figure)
	return figure


func _facing_of(node: Node) -> float:
	return float(node.get("_facing"))


func _ready() -> void:
	# Let the tree settle before the first commanded tick.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- 1. Command bookkeeping (pure Character state). -----------------
	var figure := _make_figure()
	figure.move(2.0)
	_check(absf(figure.walk_command() - 1.0) < 0.001,
			"move() records the clamped axis (2.0 -> 1.0)")
	figure.move(-3.0)
	_check(absf(figure.walk_command() + 1.0) < 0.001,
			"move() records the clamped axis (-3.0 -> -1.0)")
	figure.move(0.0)
	_check(figure.walk_command() == 0.0, "move(0.0) records a planted figure")
	var gun: Node2D = figure.get_node("Weapon")

	# --- 2. The player turns the figure — and ONLY the player. ----------
	figure.move(1.0)
	await get_tree().physics_frame
	_check(_facing_of(gun) == 1.0, "move(+1) turns the facing right")

	# --- 3. No auto-turn from the ground's shape. -----------------------
	# The exact release artifact: the command is 0 (key released) while
	# the velocity still points BACKWARDS along the tangent for a tick.
	figure.move(0.0)
	figure.velocity = -figure.current_tangent() * 90.0
	await get_tree().physics_frame
	_check(_facing_of(gun) == 1.0,
			"a passive backwards slide never turns the figure (the #700 bug)")
	# Same symmetry forward: passive motion is not a turn either.
	figure.move(0.0)
	figure.velocity = figure.current_tangent() * 90.0
	await get_tree().physics_frame
	_check(_facing_of(gun) == 1.0,
			"a passive forward shove never turns the figure either")

	# --- 4. The computer turns the figure through the same API. ---------
	figure.call("move", -1.0)  # BotController's exact actuation call.
	await get_tree().physics_frame
	_check(_facing_of(gun) == -1.0,
			"a computer walk order (figure.call(\"move\", -1)) turns it left")
	figure.move(1.0)
	await get_tree().physics_frame
	_check(_facing_of(gun) == 1.0,
			"a computer walk order turns it back right")

	figure.queue_free()

	# --- 5. Legacy parents keep the velocity fallback. ------------------
	var legacy := LegacyBody.new()
	var legacy_gun := Node2D.new()
	legacy_gun.name = "Weapon"
	legacy_gun.set_script(WeaponScript)
	legacy.add_child(legacy_gun)
	add_child(legacy)
	await get_tree().physics_frame
	legacy.velocity = Vector2(-90.0, 0.0)
	await get_tree().physics_frame
	_check(_facing_of(legacy_gun) == -1.0,
			"bodies without walk_command() keep velocity-based facing")
	legacy.queue_free()

	if failures.is_empty():
		print("ISSUE700 OK: the figure turns only on a player/computer walk order")
	else:
		for f in failures:
			push_error("FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)
