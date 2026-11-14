extends Node
## Regression check for issue #546: the computer uses ALL weapons and
## tools.
##
##  1. ARSENAL BANDS: every distance band now rotates through every
##     weapon that fits it — melee [spear, bat, jackhammer], close/flat
##     [shotgun, pistol], open lane [rocket, railgun], ballistic
##     [grenade, mine] (+ railgun on a terrain-clear line). The FIRST
##     pick of each band (rotation 0, fresh budgets) is exactly the
##     classic pick, so the pre-#546 behaviour is preserved;
##  2. COVERAGE: across the bands' rotations every weapon index 0..8
##     is reachable — nothing in the arsenal is dead weight for the AI;
##  3. BUDGET: a spent weapon leaves its band's rotation, the spear
##     always qualifies;
##  4. MINE SAFETY: the point-blank hold-fire rule of #120 covers the
##     mine (same lob, grenade-sized blast) — no self-harm throws;
##  5. ROCK tool: in the ballistic band the AI can lob the rock instead
##     of a weapon on its rotation slot — it spends the team's rock
##     budget, marks the turn action spent (tool OR weapon, #207) and
##     locks the weapon choice; the gate never fires outside the
##     ballistic band or off its rotation slot;
##  6. SWITCH tool: a badly hurt AI hands its turn to the healthiest
##     living teammate (and spends a switch use); a healthy AI never
##     switches — two hurt figures cannot ping-pong the turn;
##  7. TELEPORT/SHIELD (#221) still fire for a hurt AI — with #546 all
##     four tools now have an AI path;
##  8. DRILL RIDE: an NPC-fired jackhammer keeps pushing the driller —
##     the idle branch no longer zeroes the drill velocity (#316 ride,
##     now granted to the computer too), so the drill really travels.
##
## Run headless: godot --headless res://tests/test_issue546.tscn
## Exit code 0 = pass.

const NpcScript := preload("res://scripts/Npc.gd")
const ProjectileBodyScript := preload("res://scripts/ProjectileBody.gd")

## Weapon slot order (WeaponInventory.WEAPONS): 0 shotgun, 1 rocket,
## 2 grenade, 3 spear, 4 mine, 5 jackhammer, 6 railgun, 7 pistol, 8 bat.
const SLOT_SHOTGUN := 0
const SLOT_ROCKET := 1
const SLOT_GRENADE := 2
const SLOT_SPEAR := 3
const SLOT_MINE := 4
const SLOT_JACKHAMMER := 5
const SLOT_RAILGUN := 6
const SLOT_PISTOL := 7
const SLOT_BAT := 8

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _make_npc(x: float, tint: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.set_script(NpcScript)
	body.set("team_color", Color(0.8, 0.1 + 0.05 * tint, 0.1 + 0.03 * tint, 1))
	add_child(body)
	body.global_position = Vector2(x, 0.0)
	return body


func _make_foe(x: float) -> CharacterBody2D:
	var foe := CharacterBody2D.new()
	foe.add_to_group("player_team")
	foe.set("health", 100)
	add_child(foe)
	foe.global_position = Vector2(x, 0.0)
	return foe


## The set of weapons a band's rotation produces over `spins` turns
## (each acting window advances the rotation by one, see Npc._pick_rotation).
func _band_picks(npc: CharacterBody2D, distance: float, height: float,
		spins: int) -> Array:
	var seen: Array = []
	for i in spins:
		npc._pick_weapon(distance, height)
		var pick := int(npc._weapon.selected_weapon)
		if not seen.has(pick):
			seen.append(pick)
		npc._pick_rotation += 1
	return seen


func _has_all(seen: Array, wanted: Array) -> bool:
	for w in wanted:
		if not seen.has(w):
			return false
	return true


func _ready() -> void:
	# Let the physics space come up before the railgun line probes.
	await get_tree().physics_frame
	await get_tree().physics_frame
	seed(546)

	# ---- 1+2) Bands rotate through the whole arsenal -----------------
	var chooser := _make_npc(0.0, 1.0)
	WeaponInventory.reset_uses()
	var melee := _band_picks(chooser, 60.0, 0.0, 9)
	_check(_has_all(melee, [SLOT_SPEAR, SLOT_BAT, SLOT_JACKHAMMER]),
			"melee band must rotate spear/bat/jackhammer (got %s)" % str(melee))
	var close := _band_picks(chooser, 150.0, 0.0, 6)
	_check(_has_all(close, [SLOT_SHOTGUN, SLOT_PISTOL]),
			"close band must rotate shotgun/pistol (got %s)" % str(close))
	var flat := _band_picks(chooser, 300.0, 0.0, 6)
	_check(_has_all(flat, [SLOT_SHOTGUN, SLOT_PISTOL]),
			"flat mid band must rotate shotgun/pistol (got %s)" % str(flat))
	var lane := _band_picks(chooser, 550.0, 0.0, 6)
	_check(_has_all(lane, [SLOT_ROCKET, SLOT_RAILGUN]),
			"open lane must rotate rocket/railgun (got %s)" % str(lane))
	# Ballistic band without a target: no line probe possible, the
	# rotation keeps to grenade/mine.
	var far_no_target := _band_picks(chooser, 2200.0, 0.0, 6)
	_check(_has_all(far_no_target, [SLOT_GRENADE, SLOT_MINE]),
			"ballistic band must rotate grenade/mine (got %s)" % str(far_no_target))
	# With a far target on a CLEAR line the railgun joins the band.
	var far_foe := _make_foe(2200.0)
	chooser._target = far_foe
	var far_clear := _band_picks(chooser, 2200.0, 0.0, 9)
	_check(_has_all(far_clear, [SLOT_GRENADE, SLOT_MINE, SLOT_RAILGUN]),
			"ballistic band on a clear line must also rotate the railgun (got %s)"
			% str(far_clear))
	# A wall on the line removes the railgun candidate again.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40.0, 600.0)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector2(1100.0, 0.0)
	# The body must flush into the physics space before the ray probes.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var far_walled := _band_picks(chooser, 2200.0, 0.0, 6)
	_check(_has_all(far_walled, [SLOT_GRENADE, SLOT_MINE]) \
			and not far_walled.has(SLOT_RAILGUN),
			"a wall on the line must keep the railgun out of the band (got %s)"
			% str(far_walled))
	# Rotation 0 / fresh budget keeps the classic first pick everywhere.
	chooser._pick_rotation = 0
	WeaponInventory.reset_uses()
	chooser._target = null
	wall.queue_free()
	chooser._pick_weapon(60.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == SLOT_SPEAR,
			"fresh melee pick stays the spear")
	chooser._pick_weapon(150.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == SLOT_SHOTGUN,
			"fresh close pick stays the shotgun")
	chooser._pick_weapon(550.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == SLOT_ROCKET,
			"fresh open-lane pick stays the rocket")
	chooser._pick_weapon(2200.0, 0.0)
	_check(int(chooser._weapon.selected_weapon) == SLOT_GRENADE,
			"fresh ballistic pick stays the grenade")
	# Coverage: every weapon of the arsenal appeared above.
	var all_seen: Array = []
	for band in [melee, close, flat, lane, far_no_target, far_clear]:
		for w in band:
			if not all_seen.has(w):
				all_seen.append(w)
	for w in range(9):
		_check(all_seen.has(w),
				"weapon slot %d must be reachable by the computer" % w)

	# ---- 3) Budget filters the rotation ------------------------------
	var spender := _make_npc(0.0, 2.0)
	WeaponInventory.reset_uses()
	var team := TurnController.team_id_of(spender)
	for i in 5:
		WeaponInventory.spend_weapon(team, SLOT_SHOTGUN)
	var close_after := _band_picks(spender, 150.0, 0.0, 4)
	_check(close_after == [SLOT_PISTOL],
			"a spent shotgun must leave the pistol alone in the band (got %s)"
			% str(close_after))
	WeaponInventory.spend_weapon(team, SLOT_RAILGUN)
	var lane_after := _band_picks(spender, 550.0, 0.0, 4)
	_check(lane_after == [SLOT_ROCKET],
			"a spent railgun must leave the rocket alone in the band (got %s)"
			% str(lane_after))

	# ---- 4) Mine point-blank guard -----------------------------------
	var miner := _make_npc(0.0, 3.0)
	WeaponInventory.reset_uses()
	miner._weapon.selected_weapon = SLOT_MINE
	var mine_foe := _make_foe(100.0)
	miner._target = mine_foe
	var mine_fired: bool = miner._shoot()
	_check(not mine_fired and int(miner._weapon.selected_weapon) == SLOT_SPEAR,
			"a point-blank mine must hold fire and fall back to the spear")

	# ---- 5) Rock tool -------------------------------------------------
	var thrower := _make_npc(0.0, 4.0)
	WeaponInventory.reset_uses()
	thrower._weapon.selected_weapon = SLOT_GRENADE
	var rock_team := TurnController.team_id_of(thrower)
	var rock_before := WeaponInventory.tool_uses_left(
			rock_team, ToolInventory.TOOL_ROCK)
	var threw: bool = thrower._throw_rock_tool()
	_check(threw and WeaponInventory.tool_uses_left(
				rock_team, ToolInventory.TOOL_ROCK) == rock_before - 1,
			"the rock throw must spend one use of the team budget")
	_check(bool(thrower._tool_used) and bool(thrower._weapon_locked),
			"the rock is this character's turn action (tool OR weapon)")
	var rock_seen := false
	for child in get_children():
		if child is RigidBody2D and child.get_script() == ProjectileBodyScript \
				and int(child.get("kind")) == ProjectileBodyScript.Kind.ROCK:
			rock_seen = true
	_check(rock_seen, "the rock must leave the hand as a ROCK projectile")
	# The gate never fires outside the ballistic band.
	thrower._weapon.selected_weapon = SLOT_SHOTGUN
	thrower._pick_rotation = thrower.ROCK_ROTATION - 1
	_check(not thrower._try_throw_rock(),
			"the rock may only replace a ballistic-band weapon")
	# ...and only on its rotation slot, not in the first fights.
	thrower._weapon.selected_weapon = SLOT_GRENADE
	thrower._pick_rotation = 0
	_check(not thrower._try_throw_rock(),
			"the rock must wait for its rotation slot")
	WeaponInventory.reset_uses()
	thrower._pick_rotation = thrower.ROCK_ROTATION - 1
	_check(thrower._try_throw_rock(),
			"on its rotation slot the rock replaces the weapon throw")
	# A spent rock budget refuses the throw.
	WeaponInventory.reset_uses()
	for i in 5:
		WeaponInventory.spend_tool(rock_team, ToolInventory.TOOL_ROCK)
	thrower._weapon.selected_weapon = SLOT_GRENADE
	thrower._tool_used = false
	thrower._weapon_locked = false
	_check(not thrower._throw_rock_tool(),
			"a spent rock budget must refuse the throw")

	# ---- 6) Switch tool ------------------------------------------------
	# Isolated far to the side — earlier foes must not sit inside the
	# teleport/shield bands and hijack the turn-start decisions.
	var hurt := _make_npc(5000.0, 5.0)
	var healthy := _make_npc(5050.0, 5.0)
	hurt.set("health", 10)
	healthy.set("health", 100)
	var switch_foe := _make_foe(5800.0)
	WeaponInventory.reset_uses()
	TurnController.active_member = hurt
	hurt._begin_my_turn()
	var switch_team := TurnController.team_id_of(hurt)
	_check(TurnController.active_member == healthy,
			"a badly hurt AI must hand its turn to the healthiest teammate")
	_check(WeaponInventory.tool_uses_left(
				switch_team, ToolInventory.TOOL_SWITCH) == 4,
			"the hand-over must spend one switch use")
	_check(bool(hurt._tool_used),
			"the switching figure's turn action is spent")
	# A healthy receiver never switches itself.
	TurnController.active_member = healthy
	healthy._begin_my_turn()
	_check(TurnController.active_member == healthy and not healthy._tool_used,
			"a healthy teammate must keep the turn it received")
	# Two hurt figures never ping-pong: nobody meaningfully healthier.
	hurt._tool_used = false
	healthy.set("health", 10)
	TurnController.active_member = hurt
	WeaponInventory.reset_uses()
	hurt._begin_my_turn()
	_check(TurnController.active_member == hurt,
			"with no healthier teammate the hurt AI keeps its turn")

	# ---- 7) Teleport + shield still fire (#221, all four tools now) ---
	var runner := _make_npc(10000.0, 6.0)
	runner.set("health", 20)
	var near_foe := _make_foe(10120.0)  # 120 px from the runner
	runner._begin_my_turn()
	_check(runner.global_position.distance_to(Vector2(10000.0, 0.0)) > 100.0
			and bool(runner._tool_used),
			"a hurt AI at point-blank must teleport away")
	var guard := _make_npc(20000.0, 7.0)
	guard.set("health", 20)
	var guard_foe := _make_foe(20300.0)  # 300 px — shield band, no teleport
	guard._begin_my_turn()
	_check(bool(guard.get("shielded")) and bool(guard._tool_used),
			"a hurt AI near the threat must raise the shield")

	# ---- 8) Jackhammer drill ride -------------------------------------
	var driller := _make_npc(30000.0, 8.0)
	# A physics tick first — the body must be in the space before the
	# drill starts (in real play the NPC has lived for the whole level).
	await get_tree().physics_frame
	driller._weapon._start_jackhammer(1.0)
	var start_x: float = driller.global_position.x
	for i in 240:
		await get_tree().physics_frame
		if driller._weapon._drill_left <= 0.0:
			break
	await get_tree().physics_frame
	_check(driller.global_position.x - start_x > 100.0,
			"the drill must carry the driller along its run (moved %f px)"
			% (driller.global_position.x - start_x))
	_check(absf(driller.velocity.x) < 0.001
			and driller._weapon._drill_left <= 0.0,
			"the drill must finish and hand normal physics back (vel.x %f)"
			% driller.velocity.x)

	if failures == 0:
		print("PASS: issue #546 computer uses all weapons and tools")
		get_tree().quit(0)
	else:
		print("FAIL: %d check(s) failed" % failures)
		get_tree().quit(1)
