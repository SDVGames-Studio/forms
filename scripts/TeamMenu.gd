extends Control
## Team menu, reworked for issue #208: editor for the whole SET of teams.
##
## - The teams sit in a DROP-DOWN at the top, right below the header (owner
##   rework: there could be a lot of them); picking a team in the drop-down
##   edits it, "+ Add team" appends a new team to the set.
## - The editing column is scrollable, so nothing is lost on small screens.
## - The members are shown in a visual window exactly as they look in the
##   game (shape figure + team color + name). The leftmost member is the
##   first in the team; clicking a figure offers to DELETE that member;
##   clicking a member's name edits it in place. Issue #394 rework v3
##   (owner 2026-11-26): the < > arrows sit LEFT and RIGHT of the
##   character strip and scroll it once the team outgrows the row, and
##   the + card is PINNED right of the strip — the same size as a member
##   card and always present, so adding a teammate never depends on
##   where the row is scrolled.
## - The shape picker is graphical: one little figure per shape.
## - "Save" persists the whole set to user://team.cfg (GameConfig.teams).
##
## Issue #394 rework v4 (owner 2026-11-28): the roster edited here is
## fully DECOUPLED from the level setup's team composition — the
## roster members are chosen first when a level fields a team, and
## level extras ("mateK") never appear here. Roster edits never touch
## a team's "level_members" count and vice versa.
##
## Owner rework (issue #208): there is NO "Player Team"/"Enemies" concept —
## the teams are just an ordered set with neutral names; in the game the
## player may choose ANY team and the computer plays any of the left ones.
## Until that in-game choice lands, the levels keep applying teams[0] to
## the player figures and teams[1]'s AI parameters to the computer (issue
## #180 behavior, unchanged).
##
## The default set of teams mirrors the teams that are in the levels.

const SHAPES: Array[String] = ["square", "circle", "triangle", "star", "ellipse"]

## Issue #394 rework v3 (owner 2026-11-26): the pinned + card appends
## teammates up to GameConfig.MAX_LEVEL_TEAM_MEMBERS — the same bound
## the level-config grid edits (#537) and the team sanitizer keep, so
## the team menu, the level menu and the persisted team.cfg agree.
## GameConfig.MAX_TEAM_MEMBERS (3) stays untouched: it pins the staged
## trio the authored levels field and the RL action space
## (tests/test_issue422.gd).

## Issue #394 rework: plate metrics shared by the member cards and the
## "+" card so both plates look exactly the same, and one plate-width
## scroll step for the < > arrows.
const PLATE_SQUARE := Vector2(80, 80)
const PLATE_NAME := Vector2(80, 34)
const PLATE_FIGURE := Vector2(56, 56)
const ROW_SEPARATION := 8

## Palette for new teams — the first two slots match the two teams the
## levels are authored with (player yellow, NPC pink).
const TEAM_PALETTE: Array[Color] = [
	Color(1, 0.84, 0.2), Color(0.75, 0.2, 0.45), Color(0.35, 0.6, 1),
	Color(0.3, 0.8, 0.4), Color(0.9, 0.3, 0.3), Color(0.2, 0.8, 0.85),
	Color(0.95, 0.6, 0.2), Color(0.65, 0.4, 0.95),
]

## Emitted instead of the scene change when Back/Esc is pressed while
## the menu runs inside the in-game settings overlay (issue #304).
signal back_requested

## True while this menu is instanced into the in-game settings overlay
## (issue #304); Back then returns to that overlay instead of changing
## the scene, which would drop the running level.
var in_game := false

@onready var _team_select: OptionButton = %TeamSelect
@onready var _add_team_button: Button = %AddTeamButton
@onready var _editing_label: Label = %EditingLabel
## Issue #589: the selected team's NAME is editable in place — the
## drop-down and the "Editing:" caption follow the edit live.
@onready var _name_edit: LineEdit = %TeamNameEdit
@onready var _shape_picker: HBoxContainer = %ShapePicker
@onready var _color: ColorPickerButton = %TeamColorPicker
## Issue #524: per-team language picker (English/Spanish/Russian/
## French/Arabic) — the team's teammates' spoken lines follow it.
@onready var _language: OptionButton = %LanguageSelect
@onready var _members_row: HBoxContainer = %MembersRow
## Issue #394 rework: the members row sits in a horizontal scroller
## driven by the < > arrows (the scrollbar itself stays hidden).
@onready var _members_scroll: ScrollContainer = %MembersScroll
@onready var _scroll_left: Button = %ScrollLeft
@onready var _scroll_right: Button = %ScrollRight
## Issue #394 rework v3: the + card is PINNED right of the scroller —
## it never scrolls away, so "add a teammate" is always on screen.
@onready var _plus_button: Button = %PlusButton
@onready var _plus_name_slot: Control = %PlusNameSlot
@onready var _skill: HSlider = %SkillSlider
@onready var _friendly_fire: HSlider = %FriendlyFireSlider
@onready var _save_button: Button = %SaveButton
@onready var _back_button: Button = %BackButton
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog
## Issue #348: the menu follows the main-menu template (MenuBackground
## artwork + MenuTheme); in overlay mode the artwork and footer hide and
## the shared shadow dim shows the paused game through instead.
@onready var _background: Control = $Background
@onready var _shadow: ColorRect = $Shadow
@onready var _footer: Control = $Footer

## Index into GameConfig.teams of the team being edited.
var _selected := 0
var _shape_buttons: Array[Button] = []
## Member index offered for deletion (dialog is open); -1 = none.
var _pending_member := -1


func _ready() -> void:
	# Main-menu spec §9 (M4 hardening): adapt to the viewport width.
	MenuAdapt.apply(self)

	# Issue #648: footer version tracks application/config/version
	# (single source of truth with the main menu footer).
	var version_label := get_node_or_null("Footer/VersionLabel") as Label
	if version_label != null:
		version_label.text = "v%s" % ProjectSettings.get_setting(
			"application/config/version", "0.0.0")
	# Issue #304 (rework, #348 template): when opened on top of the in-game
	# settings overlay the game stays visible behind the shared shadow dim
	# — the same dim the pause panel casts — instead of the standalone
	# background artwork.
	if in_game:
		_background.visible = false
		_shadow.visible = true
		_footer.visible = false
	# Load the saved customisation before filling in the controls.
	GameConfig.load_team()
	GameConfig.load_teams()
	_add_team_button.pressed.connect(_on_add_team_pressed)
	_team_select.item_selected.connect(_on_team_selected)
	# Issue #589: renaming the selected team from the menu.
	_name_edit.text_changed.connect(_on_team_name_changed)
	_color.color_changed.connect(_on_color_changed)
	for language in GameConfig.LANGUAGES:
		_language.add_item(language)
	_language.item_selected.connect(func(index: int) -> void:
		_team()["language"] = GameConfig.LANGUAGES[index])
	_skill.value_changed.connect(
		func(value: float) -> void: _team()["skill"] = int(value))
	_friendly_fire.value_changed.connect(
		func(value: float) -> void: _team()["friendly_fire"] = int(value))
	_save_button.pressed.connect(_on_save_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	_build_shape_picker()
	# Issue #394 rework: the < > arrows scroll the members row; the
	# arrows re-evaluate whenever the row or its viewport resizes.
	_scroll_left.pressed.connect(func() -> void: _scroll_members(-1))
	_scroll_right.pressed.connect(func() -> void: _scroll_members(1))
	# Issue #394 rework v3 (owner 2026-11-26): the arrows flank the
	# character strip and share the character square's height, hugging
	# the strip's top edge where the squares sit.
	_scroll_left.custom_minimum_size = Vector2(36, PLATE_SQUARE.y)
	_scroll_right.custom_minimum_size = Vector2(36, PLATE_SQUARE.y)
	# The pinned + card appends a teammate from wherever the row is.
	_plus_button.custom_minimum_size = PLATE_SQUARE
	_plus_button.pressed.connect(_on_add_member)
	_members_scroll.resized.connect(_update_scroll_arrows)
	_members_row.resized.connect(_update_scroll_arrows)
	# The scrollbar's max/page retune AFTER the resize (and silently) —
	# its `changed` signal is what actually announces a new overflow.
	_members_scroll.get_h_scroll_bar().changed.connect(_update_scroll_arrows)
	_refresh_all()


func _on_back_pressed() -> void:
	# Issue #304: in overlay mode the host settings screen listens and
	# frees this menu; standalone still changes the scene.
	if in_game:
		back_requested.emit()
		return
	get_tree().change_scene_to_file("res://scenes/menus/SettingsMenu.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the settings menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()


## The team dictionary currently being edited.
func _team() -> Dictionary:
	return GameConfig.teams[_selected]


func _refresh_all() -> void:
	_rebuild_team_list()
	_rebuild_members()
	_sync_controls()


## Fill every control from the selected team (without echoing signals).
func _sync_controls() -> void:
	var team := _team()
	_editing_label.text = "Editing: %s" % team["label"]
	# Issue #589: the name field shows the team's current name (setting
	# .text emits no text_changed, so this cannot echo back).
	_name_edit.text = str(team["label"])
	_color.color = team["color"]
	# Issue #524: the team's language — sanitized against the supported
	# set (an old/corrupt team.cfg value shows and saves as English).
	_language.select(maxi(0, GameConfig.LANGUAGES.find(
			GameConfig._valid_language(str(team.get("language", GameConfig.DEFAULT_LANGUAGE))))))
	_skill.set_value_no_signal(clampi(int(team["skill"]), 0, 10))
	_friendly_fire.set_value_no_signal(clampi(int(team["friendly_fire"]), 0, 10))
	for i in _shape_buttons.size():
		_shape_buttons[i].set_pressed_no_signal(SHAPES[i] == team["shape"])


# ------------------------------------------------------------------ teams --

func _rebuild_team_list() -> void:
	# Owner rework (#208): a drop-down — the set can hold a lot of teams.
	_team_select.clear()
	for i in GameConfig.teams.size():
		var team: Dictionary = GameConfig.teams[i]
		_team_select.add_icon_item(_swatch(team["color"]), str(team["label"]), i)
	_team_select.select(_selected)


func _on_team_selected(index: int) -> void:
	_selected = index
	_refresh_all()


## Issue #589: a non-empty edit renames the selected team immediately
## (an emptied or whitespace-only field keeps the previous name — the
## same rule as the level-config rename, #537). The drop-down entry and
## the "Editing:" caption follow without rebuilding the whole list.
func _on_team_name_changed(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return
	var team := _team()
	team["label"] = cleaned
	_editing_label.text = "Editing: %s" % cleaned
	_team_select.set_item_text(_selected, cleaned)


func _on_add_team_pressed() -> void:
	if GameConfig.teams.size() >= GameConfig.MAX_TEAMS:
		return
	var count := GameConfig.teams.size() + 1
	var names: Array[String] = []
	# Issue #617 rework v2: a fresh team fields the default squad —
	# two members (the level default is 3 teams × 2 mates).
	for i in range(1, GameConfig.DEFAULT_TEAM_MEMBERS + 1):
		names.append("Member %d" % i)
	GameConfig.teams.append({
		"label": "Team %d" % count,
		"color": TEAM_PALETTE[(count - 1) % TEAM_PALETTE.size()],
		"shape": SHAPES[count % SHAPES.size()],
		"names": names,
		"skill": 5,
		"friendly_fire": 0,
		"language": GameConfig.DEFAULT_LANGUAGE,
		# Issue #394 rework v4: a fresh team's LEVEL member count starts
		# at the default squad size — the level setup edits it separately
		# (the roster and the level composition stay decoupled).
		"level_members": GameConfig.DEFAULT_TEAM_MEMBERS,
	})
	_selected = GameConfig.teams.size() - 1
	_refresh_all()


func _on_color_changed(color: Color) -> void:
	_team()["color"] = color
	_rebuild_team_list()
	_rebuild_members()


# ----------------------------------------------------------------- shapes --

## Graphical shape picker: one button per shape, each showing the little
## figure drawn exactly like in the game (the modular character).
func _build_shape_picker() -> void:
	for shape in SHAPES:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(88, 88)
		button.tooltip_text = shape.capitalize()
		var picked := shape
		button.pressed.connect(func() -> void: _on_shape_picked(picked))
		var visual: Control = load("res://scripts/ModularCharacterVisual.gd").new()
		visual.size = Vector2(56, 56)
		# Issue #394: anchors-only centering kept the stale offsets, so the
		# figure's top-left sat on the button's center and spilled out of
		# the square. KEEP_SIZE recenters while preserving the figure size.
		visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		visual.set_team_look(Color(0.9, 0.9, 0.95), shape)
		visual.set_expression("neutral")
		button.add_child(visual)
		_shape_buttons.append(button)
		_shape_picker.add_child(button)


func _on_shape_picked(shape: String) -> void:
	_team()["shape"] = shape
	for i in _shape_buttons.size():
		_shape_buttons[i].set_pressed_no_signal(SHAPES[i] == shape)
	_rebuild_members()


# ---------------------------------------------------------------- members --

## The visual members window: one card per member — the game figure on a
## clickable button (click = offer to delete) plus the editable name.
## The row lives in a horizontal scroller driven by the < > arrows (one
## plate-width step per press); the + card that appends a teammate is
## NOT part of the scroller — it stays on screen at the strip's right
## end whatever the scroll position (issue #394 rework v3).
func _rebuild_members() -> void:
	_clear_children(_members_row)
	var team := _team()
	var names: Array = team["names"]
	## The + card's name slot must match the members' LineEdit footprint
	## (the theme may demand more height than PLATE_NAME).
	var name_min_height := PLATE_NAME.y
	for i in names.size():
		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override("separation", 4)
		var figure := Button.new()
		figure.custom_minimum_size = PLATE_SQUARE
		figure.tooltip_text = "Click to remove this member" \
				if names.size() > 1 else "A team keeps at least one member"
		var visual: Control = load("res://scripts/ModularCharacterVisual.gd").new()
		visual.size = PLATE_FIGURE
		# Issue #394: center the figure inside its square button (see the
		# shape-picker note above for why KEEP_SIZE is required).
		visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		# Issue #560: the card shows the REAL in-game figure — team color,
		# team silhouette and this member's resting personality (the same
		# member index the gameplay figures pass to apply_team_look).
		visual.apply_team_look(team["color"], str(team["shape"]), i)
		figure.add_child(visual)
		var index := i
		figure.pressed.connect(func() -> void: _on_member_clicked(index))
		var name_edit := LineEdit.new()
		name_edit.text = str(names[i])
		name_edit.max_length = 16
		name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_edit.custom_minimum_size = PLATE_NAME
		name_edit.add_theme_font_size_override("font_size", 14)
		name_min_height = maxi(name_min_height,
				name_edit.get_combined_minimum_size().y)
		name_edit.text_changed.connect(
			func(text: String) -> void: _team()["names"][index] = text)
		card.add_child(figure)
		card.add_child(name_edit)
		_members_row.add_child(card)
	# Issue #394 rework v3: the pinned + plate always shows — it only
	# gives up at the game's hard member bound — and its name-slot
	# footprint matches the members' LineEdit height so the plates row
	# up evenly.
	var full := names.size() >= GameConfig.MAX_LEVEL_TEAM_MEMBERS
	_plus_button.disabled = full
	if full:
		_plus_button.tooltip_text = "Team is full (%d members)" \
				% GameConfig.MAX_LEVEL_TEAM_MEMBERS
	else:
		_plus_button.tooltip_text = "Add a member"
	_plus_name_slot.custom_minimum_size = Vector2(PLATE_NAME.x, name_min_height)
	# Issue #394 rework v3: a rebuilt row starts at its LEFT end — the
	# leftmost member is the team's first, so a team switch (or a delete)
	# must not keep the previous view's stale scroll offset.
	_members_scroll.scroll_horizontal = 0
	_update_scroll_arrows.call_deferred()

## Issue #394 rework: one arrow click scrolls the row by one plate
## (plate width + row separation) so the next hidden card slides in.
## The scrollbar's max_value is the CONTENT width — the scrollable
## range is max_value - page (the viewport width).
func _scroll_members(direction: int) -> void:
	var max_scroll := _max_row_scroll()
	var step := PLATE_SQUARE.x + ROW_SEPARATION
	_members_scroll.scroll_horizontal = int(clampf(
			_members_scroll.scroll_horizontal + direction * step, 0.0,
			float(max_scroll)))
	_update_scroll_arrows()

## The farthest the members row can scroll (0 when it all fits).
func _max_row_scroll() -> int:
	var bar := _members_scroll.get_h_scroll_bar()
	return maxi(0, int(round(bar.max_value - bar.page)))

## Issue #394 rework: < disables at the row's left edge, > at its right
## edge (and both while the whole team is visible — nothing overflows).
func _update_scroll_arrows() -> void:
	if not is_instance_valid(_members_scroll):
		return
	var max_scroll := _max_row_scroll()
	_scroll_left.disabled = max_scroll <= 0 \
			or _members_scroll.scroll_horizontal <= 0
	_scroll_right.disabled = max_scroll <= 0 \
			or _members_scroll.scroll_horizontal >= max_scroll


## Clicking a member's figure asks for confirmation, then deletes it.
func _on_member_clicked(index: int) -> void:
	var names: Array = _team()["names"]
	if names.size() <= 1:
		return
	_pending_member = index
	_delete_dialog.dialog_text = "Remove %s from %s?" % [names[index], _team()["label"]]
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_member < 0:
		return
	var names: Array = _team()["names"]
	if _pending_member < names.size():
		names.remove_at(_pending_member)
	_pending_member = -1
	_rebuild_members()


func _on_add_member() -> void:
	var names: Array = _team()["names"]
	# Issue #394 rework v3: the menu follows the game's hard member
	# bound the level-config grid and the sanitizer also keep.
	if names.size() >= GameConfig.MAX_LEVEL_TEAM_MEMBERS:
		return
	names.append("Member %d" % (names.size() + 1))
	_rebuild_members()
	# Issue #394: keep the fresh member in sight — the row scrolls to its
	# right end so the new plate (and its name field) is on screen.
	_scroll_to_end.call_deferred()

## Issue #394: jump the members row to its right end (after adding a
## member the tail is the interesting part).
func _scroll_to_end() -> void:
	_members_scroll.scroll_horizontal = _max_row_scroll()
	_update_scroll_arrows()


# ------------------------------------------------------------------- save --

func _on_save_pressed() -> void:
	GameConfig.save_teams()
	_save_button.text = "Saved!"
	get_tree().create_timer(2.0).timeout.connect(
		func() -> void: _save_button.text = "Save")


# ---------------------------------------------------------------- helpers --

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Small square icon in the team color for the team-list buttons.
func _swatch(color: Color) -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
