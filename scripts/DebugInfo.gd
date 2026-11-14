extends Object
class_name DebugInfo
## Issue #252: debug-mode helpers, shared by every figure script.
##
## While GameConfig.debug_mode is on (default, switched in the settings
## menu) every character gets a small set of debug visuals:
##  - an HP NUMBER near the figure (under the health bar),
##  - a DAMAGE NUMBER that pops up for a second when the figure takes
##    damage,
##  - the tiny CENTRE-TO-TOP arrow (scripts/DebugArrow.gd).
## The ACTION LOG lines themselves render in the OSD's top-right corner
## (OSD.log_action) — this class is the one door figures log through.

const OSDScript := preload("res://scripts/OSD.gd")
const ArrowScript := preload("res://scripts/DebugArrow.gd")
const HitboxScript := preload("res://scripts/DebugHitbox.gd")

## Issue #554: group of every live debug-visual node (figure texts, the
## arrow, the hitbox overlays). attach() registers them all here so a
## settings flip can retarget their VISIBILITY at once — the switch
## applies to the RUNNING level without the level restart.
const DEBUG_VISUALS_GROUP := "debug_visuals"

## Issue #402: hitbox overlay palette. The FIRST hitbox of a figure is
## transparent purple (the issue's main request); a figure with several
## different collision hitboxes gets a DIFFERENT color per shape so they
## stay distinguishable. The index wraps for exotic figures.
const HITBOX_COLORS: Array[Color] = [
	Color(0.6, 0.2, 0.95, 1.0),  # purple — the first/main hitbox
	Color(1.0, 0.55, 0.1, 1.0),  # orange
	Color(0.1, 0.85, 0.8, 1.0),  # teal
	Color(0.95, 0.25, 0.45, 1.0),  # crimson
	Color(0.55, 0.9, 0.25, 1.0),  # lime
]

## Seconds a damage number stays up (issue #252: "appears for a second").
const DAMAGE_POPUP_TIME := 1.0


## Issue #554: the visuals are ALWAYS built and registered in the
## DEBUG_VISUALS_GROUP — only their VISIBILITY follows the live flag, so
## flipping the switch mid-level shows/hides them immediately (the old
## "nothing is built while off" contract needed a level restart).
static func attach(character: Node) -> void:
	var hp_label := Label.new()
	hp_label.name = "DebugHp"
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.offset_left = -70.0
	hp_label.offset_top = -38.0
	hp_label.offset_right = 70.0
	hp_label.offset_bottom = -22.0
	hp_label.add_theme_font_size_override("font_size", 12)
	_register(hp_label)
	character.add_child(hp_label)
	# Tiny centre-to-top arrow.
	var arrow := ArrowScript.new()
	arrow.name = "DebugArrow"
	_register(arrow)
	character.add_child(arrow)
	# Damage number, hidden until the figure actually takes damage.
	var popup := Label.new()
	popup.name = "DebugDamage"
	popup.offset_left = 10.0
	popup.offset_top = -96.0
	popup.offset_right = 90.0
	popup.offset_bottom = -78.0
	popup.add_theme_font_size_override("font_size", 20)
	popup.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
	popup.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.1, 1.0))
	popup.add_theme_constant_override("outline_size", 6)
	popup.add_to_group(DEBUG_VISUALS_GROUP)
	popup.visible = false
	character.add_child(popup)
	# Issue #402: a transparent hitbox overlay per collision shape — purple
	# for the first shape, a different palette color per further one. Each
	# overlay is parented to the SHAPE node itself, so it inherits authored
	# offsets and the FigurePose gravity tilt (#270) exactly.
	var hitbox_index := 0
	for child in character.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			var hitbox: Node2D = HitboxScript.new()
			hitbox.name = "DebugHitbox%d" % hitbox_index
			hitbox.set("overlay_color", hitbox_color(hitbox_index))
			_register(hitbox)
			child.add_child(hitbox)
			hitbox_index += 1


## Issue #554: register a freshly built debug visual in the live group and
## give it the CURRENT switch state (the damage popup overrides this back
## to hidden right after — it waits for an actual damage event).
static func _register(visual: Node) -> void:
	visual.add_to_group(DEBUG_VISUALS_GROUP)
	if visual is CanvasItem:
		(visual as CanvasItem).visible = GameConfig.debug_mode


## Issue #554: apply the CURRENT debug mode to every live debug visual —
## figures built under either switch state keep their nodes; only the
## visibility flips, so the settings toggle hits the RUNNING level at
## once instead of from the next level on. Call after changing
## GameConfig.debug_mode (DebugMenu._on_debug_toggled).
static func sync_debug_visuals(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(DEBUG_VISUALS_GROUP):
		if node is CanvasItem:
			(node as CanvasItem).visible = GameConfig.debug_mode


## Issue #402: the palette color for hitbox number `index` (wraps).
static func hitbox_color(index: int) -> Color:
	return HITBOX_COLORS[wrapi(index, 0, HITBOX_COLORS.size())]


## Issue #252: refresh the HP number near the figure (no-op when absent).
static func update_hp(character: Node, hp: int, max_hp: int) -> void:
	var label := character.get_node_or_null(NodePath("DebugHp")) as Label
	if label != null:
		label.text = "HP %d/%d" % [hp, max_hp]


## Issue #252: pop the damage number up for a second near the figure
## (issue #554: the popup now always exists — skip while the debug mode
## is off so it never pops on top of a hidden overlay set).
static func show_damage(character: Node, amount: int) -> void:
	if not GameConfig.debug_mode:
		return
	var popup := character.get_node_or_null(NodePath("DebugDamage")) as Label
	if popup == null:
		return
	popup.text = "-%d" % amount
	popup.modulate.a = 1.0
	popup.visible = true
	var tween := popup.create_tween()
	tween.tween_interval(DAMAGE_POPUP_TIME)
	tween.tween_callback(func() -> void: popup.visible = false)


## Issue #252: one line for the OSD's top-right action log (rendered only
## while the debug mode is on — see OSD._push_log).
static func log(text: String) -> void:
	OSDScript.log_action(text)
