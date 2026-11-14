extends Node
## Regression check for issue #354: "character shouldn't take a weapon
## in-hands in the idle".
##
## Every figure used to draw its held-weapon rectangle at ALL times —
## waiting teammates, the whole enemy team between its turns, every
## figure during the first-team roll and after the game ended, all
## walked around with a shotgun in hands. The weapon now enters the
## hands ONLY of the acting member (TurnController.active_member while
## a turn is running); idle characters stand empty-handed.
##
## Checks:
##  1. No turn running (fresh field / roll / game over): the held
##     weapon is hidden.
##  2. The acting member during its team's turn: visible.
##  3. Another member of the SAME team in the same frame: hidden.
##  4. The turn passes (active team/member cleared): the previous
##     wielder's weapon hides again.
##
## Run headless: godot --headless res://tests/test_issue354.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A stand-in figure with a real Weapon child (a plain CharacterBody2D,
## like DamageProbe in test_issue359 — Weapon only reads optional
## accessors from its parent).
func _make_figure() -> CharacterBody2D:
	var figure := CharacterBody2D.new()
	add_child(figure)
	var gun := Node2D.new()
	gun.name = "Weapon"
	gun.set_script(WeaponScript)
	figure.add_child(gun)
	return figure


func _held_rect(figure: CharacterBody2D) -> ColorRect:
	var gun := figure.get_node("Weapon")
	# _held is the FIRST ColorRect Weapon._ready adds (before the
	# charge bar) — find it by type, not by auto-generated name.
	for child in gun.get_children():
		var rect := child as ColorRect
		if rect != null:
			return rect
	return null


func _ready() -> void:
	# NOTE: deliberately NO node in the "level" group — TurnController
	# then leaves the hand-set turn state alone (its watchdogs only run
	# inside levels), which is exactly what this test needs.
	var tc := get_node("/root/TurnController")
	var a := _make_figure()
	var b := _make_figure()

	# --- 1. No turn running: both figures idle, no weapon in hands. ---
	tc.active_team = ""
	tc.active_member = null
	await get_tree().physics_frame
	var rect_a := _held_rect(a)
	var rect_b := _held_rect(b)
	print("ISSUE354 idle a=", rect_a.visible, " b=", rect_b.visible)
	_check(rect_a != null and not rect_a.visible,
			"idle figure must NOT hold a weapon (no turn running)")
	_check(rect_b != null and not rect_b.visible,
			"idle teammate must NOT hold a weapon (no turn running)")

	# --- 2. A's turn: only A takes the weapon in hands. ---
	tc.active_team = "player"
	tc.active_member = a
	await get_tree().physics_frame
	print("ISSUE354 acting a=", rect_a.visible, " b=", rect_b.visible)
	_check(rect_a.visible,
			"the acting member must hold the weapon during its turn")
	# --- 3. B stays idle in the same frame. ---
	_check(not rect_b.visible,
			"a non-acting teammate must stay empty-handed mid-turn")

	# --- 4. The turn passes: A's weapon leaves the hands again. ---
	tc.active_team = ""
	tc.active_member = null
	await get_tree().physics_frame
	print("ISSUE354 after-turn a=", rect_a.visible, " b=", rect_b.visible)
	_check(not rect_a.visible,
			"after the turn ends the figure must be empty-handed again")

	# Leave the autoload clean.
	tc.active_team = ""
	tc.active_member = null

	if failures == 0:
		print("PASS: issue #354 no weapon in hands while idle")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
