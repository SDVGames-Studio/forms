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
	# Nav buttons only exist on the screens with a Nav column
	# (TeamMenu/HotkeysMenu use their own grids — untouched). Issue #622:
	# the pass also descends into a ScrollContainer directly under Nav
	# (LevelsMenu wraps its list) so those buttons adapt too.
	var nav := layout.get_node_or_null("Columns/Nav") as VBoxContainer
	if nav != null:
		var button_width := nav_width(width)
		for child in nav.get_children():
			_apply_nav_width(child, button_width)
	var brand := layout.get_node_or_null(
		"Columns/Brand") as VBoxContainer
	if brand != null:
		# Issue #622: the title must FIT. The authored font size is the
		# maximum (never enlarged past the scene's design); the size then
		# steps down until the text fits the width budget left for the
		# brand column by the margins, the column gap and the other
		# columns' minimum widths.
		var title := brand.get_node_or_null("Title") as Label
		if title != null:
			title.add_theme_font_size_override("font_size",
				_fitting_title_size(title, columns, width, margin))
		var subtitle := brand.get_node_or_null("Subtitle") as Control
		if subtitle != null:
			subtitle.visible = not compact(width)
		var rule := brand.get_node_or_null("AccentRule") as Control
		if rule != null:
			rule.visible = not compact(width)


## Issue #622: resize one nav child to the adapted button width —
## Buttons directly, and a ScrollContainer's content recursively
## (the wrapped list's buttons adapt like the loose ones).
static func _apply_nav_width(child: Control, button_width: int) -> void:
	if child is Button or child is OptionButton or child is CheckButton:
		child.custom_minimum_size = Vector2(button_width,
			child.custom_minimum_size.y)
	elif child is ScrollContainer:
		for grandchild in child.get_children():
			_apply_nav_width(grandchild, button_width)
	elif child is BoxContainer:
		for grandchild in child.get_children():
			_apply_nav_width(grandchild, button_width)


## Issue #622: the largest title size that both respects the width
## class cap (and the scene's authored size — the adaptation never
## ENLARGES a title past its authored design) and fits the brand
## column's width budget. The title also clips as a last-resort
## guardrail (a pathological screen can never push items off-screen
## again). Floor: 32 px.
static func _fitting_title_size(title: Label, columns: BoxContainer,
		width: float, margin: int) -> int:
	title.clip_text = true
	var cap := title_size(width)
	var authored := _authored_title_size(title)
	if authored > 0:
		cap = mini(cap, authored)
	# Below the compact boundary the M4 spec table is authoritative
	# (that fixed design is what test_menu_adaptation asserts); the
	# #622 budget fit guards the REAL canvas classes.
	if width < 800.0:
		return cap
	var budget := width - 2.0 * margin
	if columns != null:
		var sep: float = columns.get_theme_constant("separation")
		var others := columns.get_child_count() - 1
		budget -= sep * others
		for child in columns.get_children():
			if child == title.get_parent():
				continue
			var control := child as Control
			if control != null:
				budget -= control.get_combined_minimum_size().x
	var font := title.get_theme_default_font()
	if font == null:
		return cap
	for size in [96, 72, 56, 48, 40, 32]:
		if size > cap:
			continue
		if font.get_string_size(title.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= budget:
			return size
	return 32


## The title's AUTHORED font size, snapshotted once — later adaptation
## passes must not read their own override as the authored design.
## -1 = no authored override.
static func _authored_title_size(title: Label) -> int:
	if title.has_meta("menu_adapt_title_authored"):
		return int(title.get_meta("menu_adapt_title_authored"))
	var authored := -1
	if title.has_theme_font_size_override("font_size"):
		authored = maxi(1, title.get_theme_font_size("font_size"))
	title.set_meta("menu_adapt_title_authored", authored)
	return authored
