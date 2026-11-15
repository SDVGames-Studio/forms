extends Object
class_name MenuAdapt
## Small-viewport adaptation for the #348 menu template
## (docs/ui/main_menu.md §9, milestone M4 hardening, 2026-11-14).
##
## Every template screen (Main + the scenes/menus family) is built from
## full-rect anchors + containers, so it never breaks — but the desktop
## spacing (72 px margins, 64 px column gap, 96 px title, 340 px nav
## buttons) needs ~850 px of width. On small landscape viewports
## (mobile/web embeds) the composition adapts while keeping the visual
## identity: proportional margins, tighter column gap, smaller title,
## and below 800 px the subtitle + accent rule yield their space (the
## FORMS brand stays). Portrait phones are out of scope (the game plays
## landscape; documented in the M4 PR).
##
## Usage — one line in each menu script's _ready():
##   MenuAdapt.apply(self)
## The layout re-adapts automatically when the viewport resizes.

## Proportional side margins: 72 px at the 1152 base width, never
## below 16 px.
static func margins(width: float) -> int:
	return clampi(roundi(width * 0.0625), 16, 72)

## Brand title size steps down on narrow viewports.
static func title_size(width: float) -> int:
	if width >= 1024.0:
		return 96
	if width >= 800.0:
		return 72
	return 56

## Column gap between the brand and the navigation.
static func separation(width: float) -> int:
	if width >= 1024.0:
		return 64
	if width >= 800.0:
		return 32
	return 24

## Nav button width (heights stay per-scene).
static func nav_width(width: float) -> int:
	if width >= 1024.0:
		return 340
	if width >= 800.0:
		return 300
	return 264

## Below 800 px the subtitle and accent rule hide — the brand keeps its
## title only, so the wide desktop sentence stops squeezing the nav.
static func compact(width: float) -> bool:
	return width < 800.0


## Apply the adaptation to a template screen root. width < 0 reads the
## current viewport (the production path: menus re-adapt automatically
## when the viewport resizes). An explicit width is STICKY: later
## `resized` signals re-apply that width, so layout passes landing after
## a forced width never override it (tests use this).
static func apply(root: Control, width: float = -1.0) -> void:
	if root == null:
		return
	var layout := root.get_node_or_null("Layout") as MarginContainer
	if layout == null:
		return
	if width >= 0.0:
		layout.set_meta("menu_adapt_width", width)
	elif layout.has_meta("menu_adapt_width"):
		layout.remove_meta("menu_adapt_width")
	_apply_at(root, layout, width)
	# Re-adapt when the viewport size changes (full-rect anchors resize
	# the margin container). One connection per layout instance.
	if not layout.has_meta("menu_adapt"):
		layout.set_meta("menu_adapt", true)
		layout.resized.connect(func() -> void:
			MenuAdapt.apply(root, _stored_width(layout)))


static func _stored_width(layout: MarginContainer) -> float:
	if layout != null and layout.has_meta("menu_adapt_width"):
		return float(layout.get_meta("menu_adapt_width"))
	return -1.0


static func _apply_at(root: Control, layout: MarginContainer,
		width: float) -> void:
	if width < 0.0:
		var viewport := root.get_viewport_rect()
		width = viewport.size.x
	var margin := margins(width)
	layout.add_theme_constant_override("margin_left", margin)
	layout.add_theme_constant_override("margin_right", margin)
	var columns := layout.get_node_or_null("Columns") as BoxContainer
	if columns != null:
		columns.add_theme_constant_override("separation",
			separation(width))
	var brand := layout.get_node_or_null(
		"Columns/Brand") as VBoxContainer
	if brand != null:
		var title := brand.get_node_or_null("Title") as Label
		if title != null:
			title.add_theme_font_size_override("font_size",
				title_size(width))
		var subtitle := brand.get_node_or_null("Subtitle") as Control
		if subtitle != null:
			subtitle.visible = not compact(width)
		var rule := brand.get_node_or_null("AccentRule") as Control
		if rule != null:
			rule.visible = not compact(width)
	# Nav buttons only exist on the screens with a Nav column
	# (TeamMenu/HotkeysMenu use their own grids — untouched).
	var nav := layout.get_node_or_null("Columns/Nav") as VBoxContainer
	if nav != null:
		var button_width := nav_width(width)
		for child in nav.get_children():
			var control := child as Control
			if control is Button or control is OptionButton \
					or control is CheckButton:
				control.custom_minimum_size = Vector2(button_width,
					control.custom_minimum_size.y)
