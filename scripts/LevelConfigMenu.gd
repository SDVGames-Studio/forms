extends Control
## Level configuration menu (issue #137).
##
## Shown after the player picks a level in the levels menu. Lets them set
## team size and enemy count before the level begins; AI behavior lives
## in the team menu since issue #180. Start applies the settings and
## loads the level, Back returns to the levels menu.
##
## Issue #521 (one-device multiplayer): the menu also edits the TEAM SET
## for the level — add/remove teams and choose who plays each one,
## computer or player. Player teams are played by humans in hot-seat on
## this device (the configured teams beyond the first are dealt across
## the level's enemy figures; GameConfig.apply swaps a player team's
## computer figures for human figures). Start persists the set to
## team.cfg together with the controller choices.
##
## Issue #537 rework: the "Your team size" and "Enemy count" rows are
## GONE — since #521 the level follows the team set, so each team's
## size is shown right in the team row as a little grid of member
## squares (one square per member, wearing the team's shape and color)
## next to the team name on the left.
##
## Issue #537 rework v2 (owner follow-up): the grid is now CLICK-TO-
## EDIT and tiered — clicking a filled square removes that teammate,
## clicking a free square ("+" sign) appends one. The grid grows
## 1x4 → 2x8 (from the fourth member) → 4x16 (from the sixteenth) with
## shrinking cells so the grid's FOOTPRINT stays the same; 64
## teammates per team is the hard maximum, one the minimum. Adding a
## team PULLS the next definition from the game's team set (the team
## menu is where new teams are made) — past the end of the set the
## deal wraps to the first team wearing a FRESH color.
##
## Issue #537 rework v3 (owner follow-up 2026-11-14): the hints are
## GONE (item 1) and the level now fields EXACTLY the per-team counts
## picked here (item 2, GameConfig.menu_team_sizes). Between the team
## name and the grid sits a COLOR SQUARE (item 5) — the picker recolors
## the team for THIS GAME ONLY; a DOUBLE-CLICK on the team name (item
## 6) renames it, also for this game only. Start persists the set with
## the ORIGINAL names and colors — the overrides live and die with the
## level run.
##
## Issue #537 rework v4 (owner follow-up 2026-11-14): the color square
## is a plain ColorRect filled with the team's ACTUAL color — the old
## ColorPickerButton wore the menu theme's flat gray Button style and
## hid the color — and it keeps one size, vertically centered, in
## every row (a taller 2x8-tier row stretched it before).

## Palette for teams added here (mirrors TeamMenu's).
const TEAM_PALETTE: Array[Color] = [
	Color(1, 0.84, 0.2), Color(0.75, 0.2, 0.45), Color(0.35, 0.6, 1),
	Color(0.3, 0.8, 0.4), Color(0.9, 0.3, 0.3), Color(0.2, 0.8, 0.85),
	Color(0.95, 0.6, 0.2), Color(0.65, 0.4, 0.95),
]

## Issue #537: recessed background of one member square (matches the
## theme's darker panel tone so the shape pops on it).
const MEMBER_CELL_BG := Color(0.122, 0.137, 0.169)

## Issue #537 rework v2: the member-grid tiers — [rows, columns]. Up
## to three members the grid is 1x4, from the fourth member 2x8, from
## the sixteenth 4x16 (64 teammates is the maximum, so the top tier's
## grid runs full with no free spot left).
const GRID_TIERS: Array[Array] = [[1, 4], [2, 8], [4, 16]]

## Fixed footprint of the member grid — every tier's cells shrink to
## keep this width (and, with square cells, this height).
const GRID_WIDTH := 124.0
const GRID_SEPARATION := 2.0

## The "+" sign on a free spot (the theme's muted text tone).
const PLUS_COLOR := Color(0.467, 0.49, 0.545)

## Issue #537 v2 (item 5): the game's team set as it was when the menu
## opened — the source every "+ Add team" pulls from, so the level can
## only field teams that exist in the game (the team menu makes new
## ones).
var _game_team_set: Array = []

## Issue #537 rework v3 (items 5+6): every team's ORIGINAL label and
## color as the menu opened, by team index — Start persists these while
## the level plays the per-game overrides. Kept index-aligned with the
## live set (a removed team drops its entry, an added team has none —
## additions persist, being new definitions).
var _game_identity: Array = []

## Issue #537 rework v3 (item 6): the team row whose name is being
## renamed right now (-1 = none) — that row builds a LineEdit instead
## of the name Label.
var _rename_team_index := -1

## Issue #537 rework v4: the color square's picker — one shared popup,
## created on first open (see _open_color_picker). The square itself
## stays a plain ColorRect so the team color always reads.
var _color_popup: Popup
var _color_picker: ColorPicker
var _color_team_index := -1

@onready var _title: Label = %Title
@onready var _turn_time: SpinBox = %TurnTimeSpinBox
@onready var _night_regime: CheckButton = %NightRegimeCheck
@onready var _spawn_regime: OptionButton = %SpawnRegimeOption
@onready var _teams_list: VBoxContainer = %TeamsList
@onready var _add_team_button: Button = %AddTeamButton
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	# Main-menu spec §9 (M4 hardening): adapt to the viewport width.
	MenuAdapt.apply(self)
	_turn_time.value_changed.connect(func(value: float) -> void: GameConfig.turn_time = value)
	# Issue #367: the night regime is picked here, before the game.
	_night_regime.toggled.connect(func(on: bool) -> void: GameConfig.night_regime = on)
	# Issue #523: the spawn regime is picked here, before the game.
	for label in SpawnRegime.REGIME_LABELS:
		_spawn_regime.add_item(label)
	_spawn_regime.item_selected.connect(func(index: int) -> void:
		GameConfig.spawn_regime = index)
	# `select` does not emit `item_selected`, so the stored choice is
	# restored without being written back.
	_spawn_regime.select(GameConfig.spawn_regime)
	# Issue #521: the team set for the level — loaded here (once) and
	# edited directly in GameConfig.teams; Start persists it.
	GameConfig.load_teams()
	_game_team_set = GameConfig.teams.duplicate(true)
	_game_identity = []
	for team in GameConfig.teams:
		_game_identity.append({
			"label": str(team["label"]),
			"color": team["color"] if team.get("color") is Color else Color(1, 1, 1),
		})
	_add_team_button.pressed.connect(_on_add_team_pressed)
	_rebuild_team_rows()
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_turn_time.set_value_no_signal(GameConfig.turn_time)
	# Setting the property directly does not emit `toggled`, so the
	# stored choice is restored without being written back.
	_night_regime.button_pressed = GameConfig.night_regime
	if GameConfig.level_path.is_empty():
		# Opened directly (e.g. from the editor): fall back to level 1.
		GameConfig.level_path = "res://scenes/levels/Level1.tscn"
	_title.text = _title.text + " — " + GameConfig.level_path.get_file().get_basename()
	_start_button.grab_focus()


func _on_start_pressed() -> void:
	# Issue #537 rework v3 (item 2): from here on the level takes every
	# team's SIZE from this menu's grids.
	GameConfig.menu_team_sizes = true
	# Issue #521: persist the edited team set (with the controller
	# choices) before the level applies it. Issue #537 rework v3
	# (items 5+6): the per-game color/name overrides are NOT persisted —
	# the save carries each team's ORIGINAL label and color while the
	# live set (the one the level plays) keeps the overrides.
	var live: Array = GameConfig.teams.duplicate(true)
	GameConfig.teams = GameConfig.teams.duplicate(true)
	for i in mini(GameConfig.teams.size(), _game_identity.size()):
		GameConfig.teams[i]["label"] = _game_identity[i]["label"]
		GameConfig.teams[i]["color"] = _game_identity[i]["color"]
	GameConfig.save_teams()
	GameConfig.teams = live
	GameConfig._sync_from_teams()
	# Issue #463: the picked level's endless background music starts with
	# the level and survives the scene change (autoload).
	MusicManager.play_for_level(GameConfig.level_path)
	get_tree().change_scene_to_file(GameConfig.level_path)


# -------------------------------------------------- teams (issue #521) --

## One row per configured team (issue #537 layout): the team NAME on
## the left, then the little member GRID — one square per member of the
## team, each square wearing the team's shape and color — then who
## plays it (Computer/Player) and a Remove button. The minimum is two
## teams, the maximum GameConfig.MAX_TEAMS.
func _rebuild_team_rows() -> void:
	for child in _teams_list.get_children():
		_teams_list.remove_child(child)
		child.queue_free()
	for i in GameConfig.teams.size():
		var team: Dictionary = GameConfig.teams[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# Issue #537 rework v3 (item 6): a DOUBLE-CLICK on the team name
		# swaps it for an inline LineEdit; Enter (or clicking away)
		# commits the rename — for this game only (see _on_start_pressed).
		if i == _rename_team_index:
			var edit := LineEdit.new()
			edit.text = str(team["label"])
			edit.custom_minimum_size = Vector2(64, 0)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.add_theme_font_size_override("font_size", 16)
			edit.select_all()
			edit.text_submitted.connect(func(_text: String) -> void:
				_commit_team_rename(i, edit.text))
			edit.focus_exited.connect(func() -> void:
				_commit_team_rename(i, edit.text))
			row.add_child(edit)
			edit.call_deferred("grab_focus")
		else:
			var label := Label.new()
			label.text = str(team["label"])
			label.custom_minimum_size = Vector2(64, 0)
			label.add_theme_font_size_override("font_size", 18)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.clip_text = true
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed \
						and event.double_click:
					_begin_team_rename(i))
			row.add_child(label)
		# Issue #537 rework v4 (owner 2026-11-14): the color square must
		# SHOW the team's actual color — a themed ColorPickerButton painted
		# as a flat gray button (the menu theme styles every Button, and
		# ColorPickerButton inherits those styles), hiding the color. The
		# square is now a plain ColorRect FILLED with the team color —
		# theme-proof — that opens a color picker popup on click. The
		# recolor stays for this game only (Start persists the original).
		var color: Color = team["color"] if team.get("color") is Color else Color(1, 1, 1)
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(38, 38)
		# Same size and vertical CENTER in every row — a 2x8-tier row is
		# taller, and a stretched swatch sat larger than in other rows.
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_STOP
		var swatch_team_index := i
		swatch.gui_input.connect(func(event: InputEvent) -> void:
			if _is_left_click(event):
				_open_color_picker(swatch_team_index, swatch))
		row.add_child(swatch)
		row.add_child(_build_member_grid(team, i))
		var controller := OptionButton.new()
		controller.add_item("Computer")
		controller.add_item("Player")
		controller.select(1 if GameConfig.team_controller(i) == "player" else 0)
		controller.custom_minimum_size = Vector2(0, 40)
		controller.add_theme_font_size_override("font_size", 16)
		var team_index := i
		controller.item_selected.connect(func(index: int) -> void:
			var choice := "player" if index == 1 else "computer"
			GameConfig.teams[team_index]["controller"] = choice)
		row.add_child(controller)
		var remove := Button.new()
		remove.text = "Remove"
		remove.custom_minimum_size = Vector2(0, 40)
		remove.add_theme_font_size_override("font_size", 16)
		remove.disabled = GameConfig.teams.size() <= 2
		remove.pressed.connect(func() -> void: _on_remove_team_pressed(i))
		row.add_child(remove)
		_teams_list.add_child(row)
	_add_team_button.disabled = GameConfig.teams.size() >= GameConfig.MAX_TEAMS


## Issue #537 rework v2: the team's little grid table — tiered by the
## member count (see GRID_TIERS), every cell a recessed gray square.
## FILLED squares carry the team's shape centered in the team's color
## (a triangle team shows triangles); clicking one removes that
## teammate. FREE squares carry a "+" sign; clicking one appends a
## teammate. Cells shrink per tier so the grid keeps one footprint.
func _build_member_grid(team: Dictionary, team_index: int) -> GridContainer:
	var members: Array = team["names"]
	var shape := str(team["shape"])
	var color: Color = team["color"] if team.get("color") is Color else Color(1, 1, 1)
	var tier := _tier_for(members.size())
	var rows: int = tier[0]
	var columns: int = tier[1]
	var cell_size := (GRID_WIDTH - (columns - 1) * GRID_SEPARATION) / columns
	var grid := GridContainer.new()
	grid.columns = columns
	# Issue #537 rework v4 (owner: "check the position of first Color
	# square"): every tier's cell rounding made the grid a few pixels
	# narrower/wider, and the EXPAND name label ate the difference — so
	# the color square sat further right on taller-tier rows. The grid
	# now owns ONE fixed slot of GRID_WIDTH in every row, so the square
	# keeps the same x in all rows at any window width.
	grid.custom_minimum_size = Vector2(GRID_WIDTH, 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", int(GRID_SEPARATION))
	grid.add_theme_constant_override("v_separation", int(GRID_SEPARATION))
	for slot in rows * columns:
		var filled := slot < members.size()
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(cell_size, cell_size)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var bg := ColorRect.new()
		bg.color = MEMBER_CELL_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bg)
		if filled:
			# Owner item 1: the shape sits CENTERED in the gray square —
			# a full-rect anchor with a small inset does exactly that at
			# every tier's cell size.
			var visual: Control = load("res://scripts/ModularCharacterVisual.gd").new()
			visual.set_anchors_preset(Control.PRESET_FULL_RECT)
			var inset := cell_size * 0.14
			visual.offset_left = inset
			visual.offset_top = inset
			visual.offset_right = -inset
			visual.offset_bottom = -inset
			visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Issue #560: the cell shows the REAL in-game figure — team
			# color, team silhouette and the member's resting personality
			# (the slot index, same as the gameplay member index).
			visual.apply_team_look(color, shape, slot)
			cell.add_child(visual)
			# Owner item 2: clicking a filled square removes the teammate.
			cell.gui_input.connect(func(event: InputEvent) -> void:
				if _is_left_click(event):
					_remove_member(team_index, slot))
		else:
			# Owner item 3: every free spot shows a "+" and appends a
			# teammate when clicked.
			var plus := Label.new()
			plus.text = "+"
			plus.set_anchors_preset(Control.PRESET_FULL_RECT)
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.add_theme_font_size_override("font_size", maxi(9, int(cell_size * 0.8)))
			plus.add_theme_color_override("font_color", PLUS_COLOR)
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(plus)
			cell.gui_input.connect(func(event: InputEvent) -> void:
				if _is_left_click(event):
					_add_member(team_index))
		grid.add_child(cell)
	return grid


## The tier a member count plays in: the smallest grid with a FREE
## spot left (so the "+" is always available), or the top tier at the
## 64-teammate maximum where the grid simply runs full.
static func _tier_for(member_count: int) -> Array:
	for tier in GRID_TIERS:
		if member_count < tier[0] * tier[1]:
			return tier
	return GRID_TIERS[GRID_TIERS.size() - 1]


func _is_left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT


## Issue #537 rework v4: recolor a team in the LIVE set (this game
## only — Start persists the original from _game_identity). The
## picker's color_changed drives this; kept as a method so tests can
## drive the exact same path.
func _apply_team_color(team_index: int, picked: Color) -> void:
	if team_index >= 0 and team_index < GameConfig.teams.size():
		GameConfig.teams[team_index]["color"] = picked


## Issue #537 rework v4: open the shared color-picker popup under the
## clicked color square. Live color_changed updates the team's color
## in the live set; closing rebuilds the rows so the member-grid
## shapes wear the new color too. The popup is clamped on screen.
func _open_color_picker(team_index: int, swatch: Control) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	_color_team_index = team_index
	if _color_popup == null:
		_color_picker = ColorPicker.new()
		_color_picker.edit_alpha = false
		_color_picker.custom_minimum_size = Vector2(296, 396)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		margin.add_child(_color_picker)
		_color_popup = Popup.new()
		_color_popup.add_child(margin)
		add_child(_color_popup)
		_color_picker.color_changed.connect(func(picked: Color) -> void:
			_apply_team_color(_color_team_index, picked))
		# Rebuilding on close recolors the member-grid shapes as well.
		_color_popup.popup_hide.connect(func() -> void:
			_color_team_index = -1
			_rebuild_team_rows())
	_color_picker.color = GameConfig.teams[team_index]["color"] \
			if GameConfig.teams[team_index].get("color") is Color else Color(1, 1, 1)
	var origin: Vector2 = swatch.global_position
	var size := Vector2(320, 420)
	var view := get_viewport().get_visible_rect().size
	origin.x = minf(origin.x, maxf(view.x - size.x, 0.0))
	origin.y = minf(origin.y + swatch.size.y + 8.0, maxf(view.y - size.y, 0.0))
	_color_popup.popup(Rect2i(origin, size))


## Issue #537 rework v3 (item 6): a double-click on the team name turns
## the label into an inline LineEdit (rebuilt with _rename_team_index).
func _begin_team_rename(team_index: int) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	_rename_team_index = team_index
	_rebuild_team_rows()


## Issue #537 rework v3 (item 6): Enter or clicking away commits the
## rename (an empty name keeps the old one). The LineEdit's own signals
## may fire twice (submit + focus loss) — committing an already-committed
## index is a harmless rebuild.
func _commit_team_rename(team_index: int, text: String) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	_rename_team_index = -1
	var cleaned := text.strip_edges()
	if not cleaned.is_empty():
		GameConfig.teams[team_index]["label"] = cleaned
	_rebuild_team_rows()


## Owner item 2: a filled square's click drops that teammate; one is
## the floor — a team always fields at least one figure.
func _remove_member(team_index: int, member_index: int) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	var names: Array = GameConfig.teams[team_index]["names"]
	if member_index < 0 or member_index >= names.size() or names.size() <= 1:
		return
	names.remove_at(member_index)
	_rebuild_team_rows()


## Owner item 3: a free square's click appends a teammate, up to the
## 4x16 tier's 64.
func _add_member(team_index: int) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	var names: Array = GameConfig.teams[team_index]["names"]
	if names.size() >= GameConfig.MAX_LEVEL_TEAM_MEMBERS:
		return
	names.append("Member %d" % (names.size() + 1))
	_rebuild_team_rows()


func _on_add_team_pressed() -> void:
	if GameConfig.teams.size() >= GameConfig.MAX_TEAMS:
		return
	# Owner item 5: the level can only field teams that EXIST in the
	# game — "+ Add team" pulls the next definition from the game's set
	# (the team menu is where new ones are made). Past the end of the
	# set the deal wraps to the first team wearing a fresh color.
	var source: Dictionary = _game_team_set[
		GameConfig.teams.size() % _game_team_set.size()].duplicate(true)
	GameConfig.teams.append({
		"label": str(source["label"]),
		"color": _fresh_color(source),
		"shape": str(source["shape"]),
		"names": _default_member_names(),
		"skill": clampi(int(source.get("skill", 5)), 0, 10),
		"friendly_fire": clampi(int(source.get("friendly_fire", 0)), 0, 10),
		"controller": "computer",
		"language": str(source.get("language", GameConfig.DEFAULT_LANGUAGE)),
	})
	_rebuild_team_rows()


## The added team's color: the source team's own if the level does not
## wear it yet, else the first palette color free in the level.
func _fresh_color(source: Dictionary) -> Color:
	if source.get("color") is Color and not _color_in_use(source["color"]):
		return source["color"]
	for color in TEAM_PALETTE:
		if not _color_in_use(color):
			return color
	return source["color"] if source.get("color") is Color else TEAM_PALETTE[0]


func _color_in_use(color: Color) -> bool:
	for team in GameConfig.teams:
		if team.get("color") is Color and team["color"] == color:
			return true
	return false


func _default_member_names() -> Array[String]:
	var names: Array[String] = []
	for i in range(1, GameConfig.DEFAULT_TEAM_MEMBERS + 1):
		names.append("Member %d" % i)
	return names


func _on_remove_team_pressed(index: int) -> void:
	if GameConfig.teams.size() <= 2:
		return
	GameConfig.teams.remove_at(index)
	# Issue #537 rework v3: keep the original-identity list aligned with
	# the live set — the removed team's original leaves with it.
	if index >= 0 and index < _game_identity.size():
		_game_identity.remove_at(index)
	_rename_team_index = -1
	_rebuild_team_rows()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/LevelsMenu.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the levels menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
