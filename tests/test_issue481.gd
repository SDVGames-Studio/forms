extends Node
## Regression check for issue #481: "the computer is able to change
## weapon after the use" — an NPC on LevelDuelBig thrust the spear and
## then switched to the shotgun, firing two more shots in one turn.
## The player-side rule (issues #131/#143) locks the weapon choice on
## the FIRST shot of the turn; the NPC's distance-based re-pick silently
## bypassed it. Now the NPC carries the same per-turn lock.
##
## 1. Control: a fresh NPC still picks by distance (spear point-blank,
##    shotgun at close range) while it has NOT fired this turn.
## 2. Lock: after a committed shot (_shoot through the real Weapon
##    npc_fire), the re-pick is a no-op — the fired weapon stays in
##    hands at every distance band.
## 3. _switch_weapon: refused while locked, applied while unlocked.
## 4. Hold-fire fallback: a locked AI never swaps guns to dodge its own
##    safety checks — the grenade-unsafe path holds fire instead of
##    trading the locked grenade for the spear; unlocked it still falls
##    back to the spear and commits on the next order.
## 5. Turn reset: _begin_my_turn() unlocks the choice again.
## 6. npc_fire() commit reporting: a gated call (between-shots delay)
##    reports false and must not lock anything.
##
## Run headless: godot --headless res://tests/test_issue481.tscn
## Exit code 0 = pass.

const NpcScript := preload("res://scripts/Npc.gd")

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _make_npc() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.set_script(NpcScript)
	return body


## Fresh-turn weapon state: full quotas, no cooldowns (what
## TurnController.reset_shots gives every acting member at turn start).
func _fresh_weapon(npc: CharacterBody2D) -> void:
	npc._weapon.reset_shots()
	npc._weapon.set("_cooldown_left", 0.0)


func _ready() -> void:
	await get_tree().process_frame

	# 1) Control — the unlocked pick by distance is unchanged.
	var npc := _make_npc()
	add_child(npc)
	npc.set("ai_friendly_fire", 0)
	npc._pick_weapon(60.0, 0.0)
	_check(int(npc._weapon.selected_weapon) == 3,
			"point-blank must still pick the spear while unlocked")
	npc._pick_weapon(150.0, 0.0)
	_check(int(npc._weapon.selected_weapon) == 0,
			"close range must still pick the shotgun while unlocked")
	_check(not bool(npc._weapon_locked),
			"merely picking a weapon must not lock the choice")

	# 2) A committed spear shot locks the choice for the turn...
	npc._weapon.selected_weapon = 3  # spear — infinite budget, no world deps
	var fired: bool = npc._shoot()
	_check(fired, "the spear order must commit on an empty battlefield")
	_check(bool(npc._weapon_locked),
			"a committed shot must lock the weapon choice for the turn")
	# ...and every distance band keeps the fired weapon in hands.
	npc._pick_weapon(60.0, 0.0)
	_check(int(npc._weapon.selected_weapon) == 3,
			"locked: point-blank re-pick must keep the fired weapon")
	npc._pick_weapon(150.0, 0.0)
	_check(int(npc._weapon.selected_weapon) == 3,
			"locked: close-range re-pick must keep the fired weapon")
	npc._pick_weapon(450.0, 300.0)
	_check(int(npc._weapon.selected_weapon) == 3,
			"locked: height-band re-pick must keep the fired weapon")

	# 3) _switch_weapon gate.
	_check(not npc._switch_weapon(2),
			"locked: a weapon switch must be refused")
	_check(int(npc._weapon.selected_weapon) == 3,
			"locked: a refused switch must not touch the held weapon")
	npc._weapon_locked = false
	_check(npc._switch_weapon(2),
			"unlocked: a weapon switch must apply")
	_check(int(npc._weapon.selected_weapon) == 2,
			"unlocked: the switch must change the held weapon")

	# 4) Hold-fire fallback — a point-blank target 60 px away (inside
	# GRENADE_MIN_RANGE = 130). A plain Node2D: _grenade_unsafe only
	# measures the target's position.
	var foe := Node2D.new()
	add_child(foe)
	foe.global_position = npc.global_position + Vector2(60.0, 0.0)
	npc._target = foe
	npc._weapon_locked = true
	_check(not npc._shoot(),
			"locked: the unsafe-grenade order must hold fire")
	_check(int(npc._weapon.selected_weapon) == 2,
			"locked: the unsafe-grenade path must not swap to the spear")
	_check(bool(npc._weapon_locked),
			"locked: a held (not fired) order must not change the lock")
	npc._weapon_locked = false
	_check(not npc._shoot(),
			"unlocked: the unsafe-grenade order still holds fire this tick")
	_check(int(npc._weapon.selected_weapon) == 3,
			"unlocked: the unsafe-grenade path still falls back to the spear")
	_fresh_weapon(npc)
	_check(npc._shoot(),
			"the spear fallback commits on the next order")
	_check(bool(npc._weapon_locked),
			"the committed spear locks the choice like any shot")

	# 5) A fresh turn unlocks the choice.
	npc._begin_my_turn()
	_check(not bool(npc._weapon_locked),
			"_begin_my_turn must unlock the weapon choice")
	npc._pick_weapon(150.0, 0.0)
	_check(int(npc._weapon.selected_weapon) == 0,
			"after the turn reset the distance pick works again")

	# 6) npc_fire() commit reporting — the between-shots delay (set by
	# the check-4 spear) gates the call: false, nothing committed.
	_check(not npc._weapon.npc_fire(),
			"a call gated by the between-shots delay must report false")
	_check(not bool(npc._weapon_locked),
			"a gated no-op call must not lock the choice")

	npc.queue_free()
	foe.queue_free()
	for i in 5:
		await get_tree().physics_frame

	if failures == 0:
		print("issue481: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		print("issue481: %d CHECK(S) FAILED" % failures)
		get_tree().quit(1)
