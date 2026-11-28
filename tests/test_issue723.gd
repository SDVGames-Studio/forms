extends Node
## Regression check for issue #723 (Weapon Visual Redesign 4e —
## Arsenal Consistency & Cleanup, the final sub-issue of the #680
## roadmap).
##
##  1. INVENTORY: the migration is complete — every WEAPON slot (the
##     eleven weapons; the rock TOOL is out of the arsenal's scope by
##     the issue text) renders through its own cartoon sprite, and
##     only the rock tool keeps the plain rectangle fill.
##  2. CONSISTENT CONVENTIONS: all eleven generator scripts share the
##     one recipe — the character outline color (31, 20, 41), the 16x
##     work scale and the 1.8 in-game-px bold outline — and every
##     registry draw size is exactly a quarter of its texture's pixel
##     size (the shared 4:1 source:draw ratio), so the on-screen
##     outline weight reads the same across the whole arsenal.
##  3. REGISTRY BANDS: every textured entry stays inside the shared
##     hold bands (anchor in the #559 26-34 band, waist-hold
##     lift_keep/drop present), every recoil is >= 0 with the
##     melee/contact styles at 0, every readable size clears the
##     floor, and the spear's size.x — the only size gameplay reads
##     (the sweep hitbox) — stays pinned.
##  4. CLEANUP: assets/weapons holds exactly the eleven referenced
##     weapon PNGs (plus their .import sidecars) — no unused duplicate
##     art left behind.
##  5. HELD PATH: each of the eleven weapons wires its registry sprite
##     into _held_sprite at the shared quarter scale with the plain
##     ColorRect path off.
##
## Run headless: godot --headless res://tests/test_issue723.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const WeaponVisualsScript := preload("res://scripts/WeaponVisuals.gd")

## The eleven WEAPON slots (registry style indices — everything
## except the rock TOOL at 4).
const WEAPON_SLOTS := [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]
## The melee/contact styles whose own motion IS the animation.
const ZERO_RECOIL_SLOTS := [3, 6, 9, 11]

## One [slot, texture, name] row per weapon — the full arsenal map
## (the texture consts are themselves constant, so the table is too).
const ARSENAL := [
	[0, WeaponVisualsScript.SHOTGUN_TEX, "shotgun"],
	[1, WeaponVisualsScript.ROCKET_LAUNCHER_TEX, "rocket launcher"],
	[2, WeaponVisualsScript.GRENADE_TEX, "grenade"],
	[3, WeaponVisualsScript.SPEAR_TEX, "spear"],
	[5, WeaponVisualsScript.MINE_TEX, "mine"],
	[6, WeaponVisualsScript.JACKHAMMER_TEX, "jackhammer"],
	[7, WeaponVisualsScript.RAILGUN_TEX, "railgun"],
	[8, WeaponVisualsScript.PISTOL_TEX, "pistol"],
	[9, WeaponVisualsScript.BASEBALL_BAT_TEX, "baseball bat"],
	[10, WeaponVisualsScript.CIRCULAR_SAW_TEX, "circular saw"],
	[11, WeaponVisualsScript.SHOVEL_TEX, "entrenching shovel"],
]

## The eleven generator scripts (the art's source of truth).
const GENERATORS := [
	"res://scripts/gen_shotgun.py",
	"res://scripts/gen_rocket_launcher.py",
	"res://scripts/gen_grenade.py",
	"res://scripts/gen_spear.py",
	"res://scripts/gen_mine.py",
	"res://scripts/gen_jackhammer.py",
	"res://scripts/gen_railgun.py",
	"res://scripts/gen_pistol.py",
	"res://scripts/gen_baseball_bat.py",
	"res://scripts/gen_circular_saw.py",
	"res://scripts/gen_entrenching_shovel.py",
]

## The shared generator recipe every weapon sprite is authored with.
const RECIPE_SCALE := "S = 16.0"
const RECIPE_OUTLINE_WIDTH := "W_OUT = int(1.8 * S)"
const RECIPE_OUTLINE_COLOR := "O = (31, 20, 41, 255)"

## The eleven weapon texture files — the full expected contents of
## assets/weapons (PNG plus .import sidecar each).
const WEAPON_TEXTURES := [
	"res://assets/weapons/shotgun.png",
	"res://assets/weapons/rocket_launcher.png",
	"res://assets/weapons/grenade.png",
	"res://assets/weapons/spear.png",
	"res://assets/weapons/mine.png",
	"res://assets/weapons/jackhammer.png",
	"res://assets/weapons/railgun.png",
	"res://assets/weapons/pistol.png",
	"res://assets/weapons/baseball_bat.png",
	"res://assets/weapons/circular_saw.png",
	"res://assets/weapons/entrenching_shovel.png",
]

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: %s" % message)


## A shooter whose aim_dir answers the test's live aim vector (the
## #680 recipe — Weapon.gd only reads aim_dir/current_gravity here).
class AimShooter:
	extends CharacterBody2D
	var aim := Vector2(1, 0)
	func aim_dir(_facing: float, _grav: float = 1.0) -> Vector2:
		return aim
	func current_gravity() -> Vector2:
		return Vector2.DOWN


func _make_weapon(aim: Vector2) -> Node2D:
	var shooter := AimShooter.new()
	shooter.aim = aim
	add_child(shooter)
	var gun := Node2D.new()
	gun.set_script(WeaponScript)
	shooter.add_child(gun)
	return gun


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var styles: Array = WeaponVisualsScript.STYLES

	# --- 1) Inventory: every weapon migrated, rock tool plain --------
	_check(styles.size() == 12,
			"the slot order must stay intact — 12 entries (got %s)"
			% styles.size())
	for row in ARSENAL:
		var slot: int = row[0]
		var tex: Texture2D = row[1]
		var label: String = row[2]
		_check(WeaponVisualsScript.textured(slot)
					and styles[slot]["texture"] == tex,
				"the %s must carry its own sprite (slot %d)" % [label, slot])
	# The rock TOOL stays the one plain rectangle (out of scope, #723).
	_check(not styles[4].has("texture")
				and styles[4]["color"] == Color(0.55, 0.5, 0.45, 1),
			"only the rock tool may keep its plain rectangle fill")

	# --- 2) Consistent conventions: one recipe, one draw ratio -------
	for gen_path in GENERATORS:
		var src := FileAccess.get_file_as_string(gen_path)
		_check(src.length() > 0,
				"the generator must exist and read (%s)" % gen_path)
		if src.length() == 0:
			continue
		_check(src.contains(RECIPE_SCALE),
				"the generator must keep the 16x work scale (%s)" % gen_path)
		_check(src.contains(RECIPE_OUTLINE_WIDTH),
				"the generator must keep the 1.8 in-game-px bold outline (%s)"
				% gen_path)
		_check(src.contains(RECIPE_OUTLINE_COLOR),
				"the generator must keep the character outline color (%s)"
				% gen_path)
	for row in ARSENAL:
		var slot: int = row[0]
		var tex: Texture2D = row[1]
		var label: String = row[2]
		var size: Vector2 = styles[slot]["size"]
		_check(size == Vector2(tex.get_width(), tex.get_height()) * 0.25,
				("the %s draw size must stay the exact 4:1 quarter of its "
				+ "texture (slot %d, got %s for %dx%d)")
				% [label, slot, size, tex.get_width(), tex.get_height()])

	# --- 3) Registry bands: holds, recoil, readability ----------------
	for slot in WEAPON_SLOTS:
		var s: Dictionary = styles[slot]
		var label: String = "slot %d" % slot
		for row in ARSENAL:
			if row[0] == slot:
				label = row[2]
		var hold_anchor: float = WeaponVisualsScript.anchor(slot)
		_check(hold_anchor >= 26.0 and hold_anchor <= 34.0,
				"the %s anchor must stay in the #559 band (got %s)"
				% [label, hold_anchor])
		_check(s.has("lift_keep") and s.has("drop"),
				"the %s must carry the waist-hold tuning" % label)
		var lift_keep: float = WeaponVisualsScript.lift_keep(slot)
		var drop: float = WeaponVisualsScript.drop(slot)
		_check(lift_keep >= 0.25 and lift_keep <= 0.45,
				"the %s lift_keep must stay in the hold band (got %s)"
				% [label, lift_keep])
		_check(drop >= 5.0 and drop <= 12.0,
				"the %s drop must stay in the hold band (got %s)"
				% [label, drop])
		_check(WeaponVisualsScript.recoil(slot) >= 0.0,
				"the %s must resolve a recoil magnitude" % label)
		_check(not (WeaponVisualsScript.flash_style(slot) as Dictionary)
				.is_empty(),
				"the %s must resolve flash data" % label)
		var size: Vector2 = styles[slot]["size"]
		_check(size.x >= 16.0 and size.y >= 8.0,
				"the %s must stay readable at gameplay scale (got %s)"
				% [label, size])
	for slot in ZERO_RECOIL_SLOTS:
		_check(WeaponVisualsScript.recoil(slot) == 0.0,
				"the melee/contact slot %d must keep recoil 0" % slot)
	_check(is_equal_approx(WeaponVisualsScript.recoil(10),
				WeaponVisualsScript.DEFAULT_RECOIL),
			"the saw must keep the part-3 default throw kick")
	# The spear's size.x feeds the sweep hitbox — frozen (#721).
	_check((styles[3]["size"] as Vector2).x == 40.0,
			"the spear size.x must stay 40 (the sweep hitbox reads it, got %s)"
			% styles[3]["size"])

	# --- 4) Cleanup: exactly the eleven referenced PNGs --------------
	var dir := DirAccess.open("res://assets/weapons")
	_check(dir != null, "assets/weapons must open")
	if dir != null:
		var names := {}
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname != "." and fname != "..":
				names[fname] = true
			fname = dir.get_next()
		dir.list_dir_end()
		_check(names.size() == WEAPON_TEXTURES.size() * 2,
				"assets/weapons must hold exactly the 11 PNGs and their "
				+ ".import sidecars (got %s entries)" % names.size())
		for tex_path: String in WEAPON_TEXTURES:
			var base: String = tex_path.get_file()
			_check(names.has(base),
					"the referenced weapon PNG must exist (%s)" % base)
			_check(names.has(base + ".import"),
					"the weapon PNG import sidecar must exist (%s)" % base)

	# --- 5) Held path: every weapon draws its registry sprite --------
	for weapon_idx in range(11):
		var gun := _make_weapon(Vector2(1, 0))
		gun.selected_weapon = weapon_idx
		gun._update_held()
		var style_idx: int = gun._held_style_index()
		var s: Dictionary = styles[style_idx]
		_check(gun._held_sprite.texture == s["texture"],
				"the held weapon %d must draw its registry sprite (style %d)"
				% [weapon_idx, style_idx])
		_check(gun._held_sprite.scale.distance_to(Vector2(0.25, 0.25)) < 0.01,
				"the held weapon %d sprite must draw at the quarter scale (got %s)"
				% [weapon_idx, gun._held_sprite.scale])
		_check(not gun._held.visible,
				"the plain ColorRect path must be off for weapon %d"
				% weapon_idx)
		gun.get_parent().queue_free()
		await get_tree().physics_frame

	_finish()


func _finish() -> void:
	if failures == 0:
		print("ISSUE723 ok=true (arsenal consistency & cleanup: inventory, conventions, bands, assets, held path)")
	else:
		print("ISSUE723 ok=false failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
