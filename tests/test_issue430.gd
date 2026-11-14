extends Node
## Regression check for issue #430: the shotgun's range was too short.
## Pellets fly straight at PELLET_SPEED for PELLET_LIFETIME seconds —
## 900 px/s * 0.35 s = 315 px, while Npc.gd's shotgun band (issue #66)
## claimed 360. The fix raises the flight time to 0.5 s = 450 px and
## aligns the NPC band with the real flight range.
##
## Run headless: godot --headless res://tests/test_issue430.tscn
## Exit code 0 = pass.

const WeaponScript := preload("res://scripts/Weapon.gd")
const ProjectileScript := preload("res://scripts/Projectile.gd")
const NpcScript := preload("res://scripts/Npc.gd")


func _ready() -> void:
	var ok := true

	# --- A real _fire_shotgun volley: holder Node2D -> weapon, pellets
	# land on the holder's parent (the test root). _aim() falls back to
	# +x for a plain Node2D parent, so every pellet flies right. ---
	var holder := Node2D.new()
	add_child(holder)
	var weapon := Node2D.new()
	weapon.set_script(WeaponScript)
	holder.add_child(weapon)
	await get_tree().process_frame  # let _ready() build the held weapon

	weapon._fire_shotgun()

	var pellets: Array = []
	for child in get_children():
		if child != holder and child is Area2D \
				and child.get_script() == ProjectileScript \
				and child.type == ProjectileScript.Type.PELLET:
			pellets.append(child)
	print("ISSUE430 pellet_count=", pellets.size(), " (want 5)")
	ok = ok and pellets.size() == 5

	var speed_ok := true
	var lifetime_ok := true
	for pellet in pellets:
		speed_ok = speed_ok and is_equal_approx(
			pellet.velocity.length(), WeaponScript.PELLET_SPEED)
		lifetime_ok = lifetime_ok and is_equal_approx(
			pellet.lifetime, WeaponScript.PELLET_LIFETIME)
	var range := WeaponScript.PELLET_SPEED * WeaponScript.PELLET_LIFETIME
	print("ISSUE430 pellet_speed_ok=", speed_ok, " lifetime_ok=", lifetime_ok,
		" range=", range, " (want 450)")
	ok = ok and speed_ok and lifetime_ok and is_equal_approx(range, 450.0)

	# The fired volley must carry the new lifetime itself (0.5, not 0.35).
	var volley_ok := true
	for pellet in pellets:
		volley_ok = volley_ok and is_equal_approx(pellet.lifetime, 0.5)
	print("ISSUE430 volley_lifetime_0.5s=", volley_ok)
	ok = ok and volley_ok

	# --- The NPC shotgun band now matches the real flight range. ---
	var band_ok := is_equal_approx(NpcScript.SHOTGUN_RANGE_NPC, range)
	print("ISSUE430 npc_band_matches_range=", band_ok, " band=",
		NpcScript.SHOTGUN_RANGE_NPC)
	ok = ok and band_ok

	print("ISSUE430 ok=", ok)
	get_tree().quit(0 if ok else 1)
