extends Node
## Regression check for issue #271: every inventory slot shows a hover
## hint — the item name plus the damage number for weapons. Tools deal
## no damage, so their hint is the name only.
##
## Run headless: godot --headless res://tests/test_issue271.tscn
## Exit code 0 = pass.

const WeaponFire := preload("res://scripts/Weapon.gd")
const ToolState := preload("res://scripts/ToolInventory.gd")
const HudScript := preload("res://scripts/WeaponInventory.gd")


func _ready() -> void:
	var ok := true
	var hud: CanvasLayer = get_node_or_null("/root/WeaponInventory")
	if hud == null:
		print("ISSUE271 weapon_inventory_loaded=false")
		get_tree().quit(1)
		return
	# The autoload builds its slots in _ready — wait one frame to be safe.
	await get_tree().process_frame

	var slots: Array = hud.get("_slots")
	var tool_slots: Array = hud.get("_tool_slots")
	var names: Array = HudScript.WEAPONS

	var slot_count_ok: bool = slots.size() == names.size() \
			and tool_slots.size() == ToolState.TOOLS.size()
	print("ISSUE271 slot_counts=", slot_count_ok,
		" weapons=", slots.size(), " tools=", tool_slots.size())
	ok = ok and slot_count_ok

	# --- Weapon hints: name + the live damage constant per weapon. ---
	var damages: Array = [
		"5 × %d" % WeaponFire.PELLET_DAMAGE,
		str(WeaponFire.ROCKET_DAMAGE),
		str(WeaponFire.GRENADE_DAMAGE),
		str(WeaponFire.SPEAR_DAMAGE),
		str(WeaponFire.MINE_DAMAGE),
		"%d/s while pushing" % int(WeaponFire.JACKHAMMER_PUSH_DPS),
		"%d-%d" % [WeaponFire.RAILGUN_MIN_DAMAGE,
				WeaponFire.RAILGUN_MAX_DAMAGE],
		"%d × %d shots" % [WeaponFire.PISTOL_DAMAGE,
				int(WeaponFire.SHOTS_PER_TURN[7])],
	]
	for i in mini(slots.size(), names.size()):
		var tip: String = slots[i].tooltip_text
		var has_name: bool = tip.contains(names[i])
		var has_damage: bool = tip.contains("Damage") and tip.contains(damages[i])
		print("ISSUE271 weapon ", i, " ", names[i], " name=", has_name,
			" damage=", has_damage, " tip=", JSON.stringify(tip))
		ok = ok and has_name and has_damage

	# --- Tool hints: the name only, never a damage line. ---
	for i in mini(tool_slots.size(), ToolState.TOOLS.size()):
		var tip: String = tool_slots[i].tooltip_text
		var has_name: bool = tip.contains(ToolState.TOOLS[i])
		var no_damage: bool = not tip.contains("Damage")
		print("ISSUE271 tool ", i, " ", ToolState.TOOLS[i], " name=", has_name,
			" no_damage=", no_damage, " tip=", JSON.stringify(tip))
		ok = ok and has_name and no_damage

	print("ISSUE271 ok=", ok)
	get_tree().quit(0 if ok else 1)
