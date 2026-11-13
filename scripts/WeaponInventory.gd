extends CanvasLayer
## Weapon inventory HUD (issue #49).
##
## Visible only inside level scenes (issue #78: gated by the "level"
## group, never on the main/levels menu screens). On touchscreen devices
## the panel starts hidden and is toggled with an inventory button in the
## top-right corner (issue #78).
##
## Issue #64 refactor: the panel sits in the BOTTOM-RIGHT corner, the
## weapons are laid out as a 2-column TABLE of icon slots (no title, no
## text names — simple geometrical shape icons), and weapons are chosen
## with digit keys or a left mouse click on a slot. Slots ignore
## keyboard focus so arrow keys never touch the inventory.

## Issue #129: on touchscreen devices the inventory becomes the CENTERED
## version: the panel is anchored to the center of the screen and the
## slots/icons grow (~2x), so the grid is comfortably finger-sized.

## Issue #179: tools joined the weapons in THIS panel — one unified
## inventory grid: weapons on keys 1-4 plus the mine on key 9 (issue
## #246), the jackhammer on key 0 (issue #307) and the railgun on key R
## (issue #359), tools on keys 5-8 (issue #227 added the fourth tool,
## Rock).
## The tool LOGIC stays in the ToolInventory autoload; this script only
## renders the shared slots.

var selected_weapon := 0

## Issue #131 (reworked in #143): after the first shot of a turn the
## weapon selection is frozen — but the one-weapon-per-turn constraint is
## a CHARACTER's constraint, not the player's. The lock is tracked per
## character node: a member that already fired keeps its weapon locked
## until the next player turn, while another controlled member may pick
## any weapon freely. TurnController unlocks everyone at the start of a
## fresh player turn.
var _locked_characters: Dictionary = {}


## Issue #143: mark a character as locked to its weapon for the turn.
func lock_for(character: Node) -> void:
	if character != null:
		_locked_characters[character] = true
		# Issue #207: the tool slots must gray out right after the first
		# shot of this character (its tools are locked for the turn).
		refresh_tools()


## Issue #143: true while this character's weapon choice is frozen.
func is_locked_for(character: Node) -> bool:
	return character != null and _locked_characters.has(character)


## Issue #143: start of a fresh player turn — every character unlocked.
## Issue #316 rework: this is also the moment a spent weapon releases the
## panel selection — the turn is over, so the character now changes to
## the NEXT weapon the team can still pay for (the owner's algorithm:
## use the weapon, the budget drops (to zero on the last use), the turn
## ends, THEN the character switches — never mid-attack).
func unlock_all() -> void:
	_locked_characters.clear()
	_advance_off_spent_weapon()


## Issue #316 rework: while the panel points at a weapon whose team
## budget is gone (e.g. the last jackhammer was just drilled), advance
## the selection FORWARD through the list (wrapping) to the next weapon
## with uses left — the spear always qualifies (infinite uses), so the
## scan always terminates. Called only from unlock_all, i.e. at the
## start of a fresh PLAYER turn; during the spent weapon's own turn the
## selection keeps highlighting it (grayed out, unselectable) so the
## wielding character never sees its active weapon morph mid-run.
func _advance_off_spent_weapon() -> void:
	if selected_weapon == WEAPON_SPEAR \
			or can_spend_weapon(TurnController.TEAM_PLAYER, selected_weapon):
		return
	for i in range(1, WEAPONS.size() + 1):
		var idx := (selected_weapon + i) % WEAPONS.size()
		if can_spend_weapon(TurnController.TEAM_PLAYER, idx):
			selected_weapon = idx
			break
	_update_highlight()
	refresh_tools()

var _slots: Array = []
var _tool_slots: Array = []
## Issue #305: the use-count Label of each slot (weapons + tools),
## kept in the same index order as the slot arrays above.
var _slot_counts: Array = []
var _tool_slot_counts: Array = []
## Issue #305: per-team use budgets — team id -> {"weapons": Array,
## "tools": Array} of remaining uses (created lazily by _budget).
var _team_uses: Dictionary = {}

var _panel: PanelContainer
var _toggle_button: Button
var _mobile_open := false
var _mobile_layout_applied := false

const WEAPONS := ["Shotgun", "Rocket", "Grenade", "Spear", "Mine", "Jackhammer", "Railgun"]

## Issue #305: per-team use budgets. Every team starts a round with 5
## uses of each weapon and 5 uses of each tool; the SPEAR is the only
## exception — its uses are infinite (shown as ∞, never spent).
## Issue #359: the RAILGUN is the second exception — each team starts a
## round with exactly ONE railgun shot.
const USES_PER_ITEM := 5
const WEAPON_SPEAR := 3
const WEAPON_RAILGUN := 6
const RAILGUN_USES := 1
## ∞ fallback when the default font has no U+221E glyph.
var _infinity_text := "∞"

## Issue #179: per-tool icon shapes (mirrors the old ToolInventory
## panel): switch = yellow bar pair, teleport = cyan ring, shield =
## blue vertical bar. Issue #227: rock = gray boulder circle.
const TOOL_ICONS: Array = [
	{"shape": "rect", "size": Vector2(30, 6), "color": Color(0.9, 0.9, 0.4, 1)},
	{"shape": "ring", "radius": 9.0, "color": Color(0.2, 0.7, 0.95, 1)},
	{"shape": "rect", "size": Vector2(16, 22), "color": Color(0.25, 0.4, 0.95, 1)},
	{"shape": "circle", "radius": 10.0, "color": Color(0.55, 0.5, 0.45, 1)},
]

## Issue #64: icon shapes per weapon, mirroring the held-weapon visuals
## in Weapon.gd (shotgun: wide yellow bar, rocket: orange bar, grenade:
## green circle, spear: long thin bar; issue #246: mine = dark circle;
## issue #307: jackhammer = steel drill bar).
const ICONS: Array = [
	{"shape": "rect", "size": Vector2(26, 6), "color": Color(0.95, 0.85, 0.3, 1)},
	{"shape": "rect", "size": Vector2(30, 8), "color": Color(0.9, 0.35, 0.15, 1)},
	{"shape": "circle", "radius": 8.0, "color": Color(0.3, 0.7, 0.3, 1)},
	{"shape": "rect", "size": Vector2(40, 4), "color": Color(0.8, 0.8, 0.9, 1)},
	{"shape": "circle", "radius": 8.0, "color": Color(0.22, 0.24, 0.3, 1)},
	{"shape": "rect", "size": Vector2(10, 18), "color": Color(0.85, 0.85, 0.95, 1)},
	{"shape": "rect", "size": Vector2(44, 5), "color": Color(0.55, 0.85, 1.0, 1)},
]

## Issue #271: hover hints. The scripts are preloaded (not the autoload
## singletons — ToolInventory may not exist yet while THIS autoload
## builds its slots) so the damage numbers and tool names are read from
## the live constants and can never drift stale after a balance tweak.
const WeaponFire := preload("res://scripts/Weapon.gd")
const ToolState := preload("res://scripts/ToolInventory.gd")


func _ready() -> void:
	layer = 10
	# Issue #353: this autoload is added AFTER InGameMenu, so inside layer
	# 10 it draws ABOVE the pause dim — its toggle button and weapon slots
	# stayed clickable while the game was paused (GUI input is not blocked
	# by SceneTree pause). The layer keeps processing during the pause so
	# it can hide itself (see _process).
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel = PanelContainer.new()
	# Issue #64: bottom-right corner instead of center-right.
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -150.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = -12.0
	add_child(_panel)

	_toggle_button = Button.new()
	_toggle_button.text = "🎒"
	_toggle_button.custom_minimum_size = Vector2(140, 64)
	_toggle_button.add_theme_font_size_override("font_size", 34)
	_toggle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toggle_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toggle_button.offset_left = -200.0
	_toggle_button.offset_right = -20.0
	_toggle_button.offset_top = 20.0
	_toggle_button.offset_bottom = 84.0
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_toggle_button.visible = false
	add_child(_toggle_button)

	if DisplayServer.is_touchscreen_available():
		_apply_mobile_layout()

	# Issue #64: table (grid) instead of a vertical list, no title.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel.add_child(grid)

	for i in WEAPONS.size():
		var slot := Button.new()
		slot.toggle_mode = true
		slot.custom_minimum_size = Vector2(60, 44)
		# Issue #64: arrow keys must never reach the inventory.
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(set_selected.bind(i))
		slot.add_child(_make_icon(ICONS[i]))
		slot.add_child(_make_count_label())
		# Issue #271: hover hint — name + damage (engine tooltip).
		slot.tooltip_text = _weapon_hint(i)
		_slots.append(slot)
		_slot_counts.append(slot.get_child(1))
		grid.add_child(slot)

## Issue #179: tool slots in the SAME grid, right after the weapons.
	for i in TOOL_ICONS.size():
		var slot := Button.new()
		slot.toggle_mode = true
		slot.custom_minimum_size = Vector2(60, 44)
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(_on_tool_slot_pressed.bind(i))
		slot.add_child(_make_icon(TOOL_ICONS[i]))
		slot.add_child(_make_count_label())
		# Issue #271: tools deal no damage — the hint is the name only.
		slot.tooltip_text = ToolState.TOOLS[i]
		_tool_slots.append(slot)
		_tool_slot_counts.append(slot.get_child(1))
		grid.add_child(slot)

	_update_highlight()
	# Issue #305: ∞ needs the U+221E glyph — fall back when the default
	# font cannot draw it (checked against the supported char map).
	var supported: String = ThemeDB.fallback_font.get_supported_chars()
	if supported.find("∞") < 0:
		_infinity_text = "oo"
	refresh_tools()
	refresh_counts()


## Issue #64: a simple geometrical shape drawn instead of a text name.
## Issue #129: bigger, centered layout for the mobile version.
func _apply_mobile_layout() -> void:
	if _mobile_layout_applied:
		return
	_mobile_layout_applied = true
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	var grid: GridContainer = _panel.get_child(0)
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	for i in _slots.size():
		_slots[i].custom_minimum_size = Vector2(120, 88)
		var icon: ShapeIcon = _slots[i].get_child(0)
		icon.icon_scale = 2.0
		icon.queue_redraw()
		# Issue #305: the use counters grow with the slots.
		_slot_counts[i].add_theme_font_size_override("font_size", 26)
		_slot_counts[i].offset_left = -46.0
		_slot_counts[i].offset_top = -34.0
	for i in _tool_slots.size():
		_tool_slots[i].custom_minimum_size = Vector2(120, 88)
		var ticon: ShapeIcon = _tool_slots[i].get_child(0)
		ticon.icon_scale = 2.0
		ticon.queue_redraw()
		# Issue #305: the use counters grow with the slots.
		_tool_slot_counts[i].add_theme_font_size_override("font_size", 26)
		_tool_slot_counts[i].offset_left = -46.0
		_tool_slot_counts[i].offset_top = -34.0


## Issue #179: tool slot click routes through the ToolInventory logic.
func _on_tool_slot_pressed(tool: int) -> void:
	var tools: Node = get_node_or_null("/root/ToolInventory")
	if tools != null:
		tools.use_tool(tool)
	refresh_tools()


func _make_icon(icon_def: Dictionary) -> Control:
	var icon := ShapeIcon.new()
	icon.icon = icon_def
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	return icon


## Issue #305: the remaining-use counter of one slot — a small outlined
## label pinned to the slot's BOTTOM-RIGHT corner (spear shows ∞).
func _make_count_label() -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = -26.0
	label.offset_right = -3.0
	label.offset_top = -18.0
	label.offset_bottom = -2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	return label


## Issue #305: the team's budget row — created lazily on first touch so
## multi-team levels (enemy:<color> ids) get their own ledger for free.
func _budget(team_id: String) -> Dictionary:
	if not _team_uses.has(team_id):
		var weapons: Array = []
		weapons.resize(WEAPONS.size())
		weapons.fill(USES_PER_ITEM)
		# Issue #359: the railgun is scarce — each team starts a round with
		# exactly ONE shot of it, not the standard five.
		weapons[WEAPON_RAILGUN] = RAILGUN_USES
		var tools: Array = []
		tools.resize(ToolState.TOOLS.size())
		tools.fill(USES_PER_ITEM)
		_team_uses[team_id] = {"weapons": weapons, "tools": tools}
	return _team_uses[team_id]


## Issue #305: uses of a weapon the team may still fire (-1 = infinite,
## the spear).
func weapon_uses_left(team_id: String, weapon: int) -> int:
	if weapon == WEAPON_SPEAR:
		return -1
	var w := clampi(weapon, 0, WEAPONS.size() - 1)
	return int(_budget(team_id)["weapons"][w])


## Issue #305: uses of a tool the team may still spend.
func tool_uses_left(team_id: String, tool: int) -> int:
	var t := clampi(tool, 0, ToolState.TOOLS.size() - 1)
	return int(_budget(team_id)["tools"][t])


## Issue #305: true while the team may still fire this weapon (always
## true for the spear — infinite uses).
func can_spend_weapon(team_id: String, weapon: int) -> bool:
	return weapon == WEAPON_SPEAR or weapon_uses_left(team_id, weapon) > 0


## Issue #327: the weapon a member of this team may actually TAKE
## IN-HANDS — the panel selection while the team can still pay for it,
## otherwise the infinite spear (there is always something to hold).
## The hand sync in Weapon._physics_process resolves through this.
func held_weapon_for(team_id: String) -> int:
	if selected_weapon != WEAPON_SPEAR \
			and not can_spend_weapon(team_id, selected_weapon):
		return WEAPON_SPEAR
	return selected_weapon


## Issue #305: true while the team may still use this tool.
func can_spend_tool(team_id: String, tool: int) -> bool:
	return tool_uses_left(team_id, tool) > 0


## Issue #305: spend one weapon use; false (and no spend) when the
## budget is exhausted. The spear spends nothing and always succeeds.
func spend_weapon(team_id: String, weapon: int) -> bool:
	if not can_spend_weapon(team_id, weapon):
		return false
	if weapon != WEAPON_SPEAR:
		var w := clampi(weapon, 0, WEAPONS.size() - 1)
		_budget(team_id)["weapons"][w] = maxi(0, weapon_uses_left(team_id, w) - 1)
		# Issue #327 reworked for #316: the last use is gone while the
		# PANEL still points at this weapon — the selection now STAYS on
		# the spent weapon for the rest of the turn (the wielding
		# character keeps it in hands, see Weapon's lock-aware hand sync;
		# held_weapon_for still refuses it for everyone else). Only when
		# the next player turn begins does unlock_all advance the panel to
		# the next weapon with uses left — demoting to the spear here, on
		# the spend, made an activated last jackhammer instantly morph
		# into the spear mid-drill. The panel shows the PLAYER team's
		# budget, so an enemy spend never touches the player's selection.
		# The spent slot grays out via refresh_tools below.
		refresh_tools()
	refresh_counts()
	return true


## Issue #305: spend one tool use; false (and no spend) when the
## budget is exhausted.
func spend_tool(team_id: String, tool: int) -> bool:
	if not can_spend_tool(team_id, tool):
		return false
	var t := clampi(tool, 0, ToolState.TOOLS.size() - 1)
	_budget(team_id)["tools"][t] = maxi(0, tool_uses_left(team_id, t) - 1)
	# Issue #327: an armed tool whose last use just left the team budget
	# can no longer be held in-hands — disarm it (the mirror of the
	# weapon-selection demote in spend_weapon; player side only).
	if team_id == TurnController.TEAM_PLAYER \
			and ToolInventory.armed_tool == t \
			and tool_uses_left(team_id, t) == 0:
		ToolInventory.armed_tool = -1
	refresh_counts()
	return true


## Issue #364: a picked-up weapon bundle ADDS one use of that weapon
## to the team's budget (the bundle roll never picks the spear — it is
## infinite already).
func grant_weapon(team_id: String, weapon: int) -> void:
	var w := clampi(weapon, 0, WEAPONS.size() - 1)
	if w == WEAPON_SPEAR:
		return
	_budget(team_id)["weapons"][w] = weapon_uses_left(team_id, w) + 1
	refresh_counts()


## Issue #364: the tool twin of grant_weapon — +1 use of the rolled
## tool to the team's budget.
func grant_tool(team_id: String, tool: int) -> void:
	var t := clampi(tool, 0, ToolState.TOOLS.size() - 1)
	_budget(team_id)["tools"][t] = tool_uses_left(team_id, t) + 1
	refresh_counts()


## Issue #305: fresh round — every team's budgets back to 5/5/5/…
## Called by TurnController._start_round on every level load.
func reset_uses() -> void:
	_team_uses = {}
	refresh_counts()


## Issue #305: repaint every slot's bottom-right counter. The panel is
## the PLAYER's inventory, so it always shows the player team's budget.
func refresh_counts() -> void:
	if _panel == null or _slot_counts.is_empty() \
			or get_node_or_null("/root/TurnController") == null:
		return
	for i in _slot_counts.size():
		_slot_counts[i].text = _infinity_text if i == WEAPON_SPEAR \
			else str(weapon_uses_left(TurnController.TEAM_PLAYER, i))
	for i in _tool_slot_counts.size():
		_tool_slot_counts[i].text = str(tool_uses_left(TurnController.TEAM_PLAYER, i))


## Issue #271: a weapon slot's hover hint — the weapon name plus its
## damage. Numbers come straight from the Weapon.gd firing constants;
## the shotgun shows its 5-pellet spread as a volley (mirrors the spread
## loop in _fire_shotgun).
func _weapon_hint(i: int) -> String:
	var damage := ""
	match WEAPONS[i]:
		"Shotgun":
			damage = "5 × %d" % WeaponFire.PELLET_DAMAGE
		"Rocket":
			damage = str(WeaponFire.ROCKET_DAMAGE)
		"Grenade":
			damage = str(WeaponFire.GRENADE_DAMAGE)
		"Spear":
			damage = str(WeaponFire.SPEAR_DAMAGE)
		"Mine":
			damage = str(WeaponFire.MINE_DAMAGE)
		"Jackhammer":
			damage = "%d/s while pushing" % int(WeaponFire.JACKHAMMER_PUSH_DPS)
		"Railgun":
			damage = "%d-%d" % [WeaponFire.RAILGUN_MIN_DAMAGE,
				WeaponFire.RAILGUN_MAX_DAMAGE]
	return "%s\nDamage: %s" % [WEAPONS[i], damage]


func _process(_delta: float) -> void:
	if _panel == null:
		return
	# Issue #353: while the in-game menu has the game paused, the whole
	# layer hides (inventory button + slots) so nothing of it is clickable
	# above the pause dim. The next unpaused frame restores the layout.
	if get_tree().paused:
		visible = false
		return
	var in_level := _is_in_level()
	# Issue #125: the layer must stay visible on mobile, otherwise the
	# toggle button itself disappears — only the PANEL is toggled.
	_toggle_button.visible = in_level and DisplayServer.is_touchscreen_available()
	if not in_level:
		visible = false
		_panel.visible = false
		return
	if DisplayServer.is_touchscreen_available():
		visible = true
		_panel.visible = _mobile_open
	else:
		visible = true
		_panel.visible = true


func _is_in_level() -> bool:
	return get_tree().get_first_node_in_group("level") != null


func _on_toggle_pressed() -> void:
	_mobile_open = not _mobile_open


func _unhandled_input(event: InputEvent) -> void:
	# Issue #353: no weapon reselection from behind the pause menu.
	if get_tree().paused:
		return
	for i in WEAPONS.size():
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			set_selected(i)


func set_selected(index: int) -> void:
	# Issue #305: a weapon the team can no longer pay for stays
	# unselectable (its slot shows 0 and is grayed out below).
	var idx := clampi(index, 0, WEAPONS.size() - 1)
	if idx != WEAPON_SPEAR \
			and not can_spend_weapon(TurnController.TEAM_PLAYER, idx):
		_update_highlight()
		return
	# Issue #234: picking a weapon puts an armed rock back in the bag —
	# the rock leaves the hand (quota unspent) instead of stacking on the
	# newly selected weapon.
	if ToolInventory.armed_tool == ToolInventory.TOOL_ROCK:
		ToolInventory.armed_tool = -1
	# Issue #131, reworked in #143 + #207: no weapon changes after the
	# first shot of the turn — nor after a tool use (tool or weapon, never
	# both) — but only for the character that actually fired / used the
	# tool. The check uses the currently controlled member, so switching
	# characters restores free selection for the member that has not.
	if is_locked_for(TurnController.active_member) \
			or ToolInventory.has_used_tool(TurnController.active_member):
		_update_highlight()
		return
	selected_weapon = clampi(index, 0, WEAPONS.size() - 1)
	_update_highlight()
	refresh_tools()


func _update_highlight() -> void:
	for i in _slots.size():
		_slots[i].button_pressed = i == selected_weapon


## Issue #179: keep the shared tool slots in sync (armed highlight and
## once-per-turn graying). Called by ToolInventory on every state change.
func refresh_tools() -> void:
	if _panel == null or _tool_slots.is_empty():
		return
	# Autoload startup order: the ToolInventory singleton may not exist
	# yet while this panel builds its slots — skip until it does.
	var tools: Node = get_node_or_null("/root/ToolInventory")
	if tools == null:
		return
	# Issue #207: the WEAPON slots gray out while the active member already
	# used a tool this turn (it can no longer fire) — the mirror of the
	# tool graying below for a character that already fired.
	var weapons_blocked: bool = tools.has_used_tool(TurnController.active_member)
	for i in _slots.size():
		# Issue #305: a spent weapon grays out too — its budget is gone.
		var spent: bool = i != WEAPON_SPEAR \
				and weapon_uses_left(TurnController.TEAM_PLAYER, i) == 0
		_slots[i].modulate = Color(1, 1, 1, 0.35) \
			if weapons_blocked or spent else Color.WHITE
	for i in _tool_slots.size():
		var slot: Button = _tool_slots[i]
		slot.button_pressed = tools.armed_tool == i
		if tools.can_use_now(i):
			slot.modulate = Color.WHITE
		else:
			slot.modulate = Color(1, 1, 1, 0.35)


## Issue #64: minimal icon canvas — draws one shape centered in the slot.
class ShapeIcon extends Control:
	var icon: Dictionary
	var icon_scale := 1.0

	func _draw() -> void:
		var c := size / 2.0
		var col: Color = icon.get("color", Color.WHITE)
		var shape: String = icon.get("shape", "rect")
		if shape == "circle":
			draw_circle(c, icon.get("radius", 8.0) * icon_scale, col)
		elif shape == "ring":
			# Issue #179: outlined circle (teleport tool icon).
			draw_arc(c, icon.get("radius", 8.0) * icon_scale, 0.0, TAU, 32, col, 4.0, true)
		else:
			var s: Vector2 = icon.get("size", Vector2(20, 6)) * icon_scale
			draw_rect(Rect2(c - s / 2.0, s), col)
