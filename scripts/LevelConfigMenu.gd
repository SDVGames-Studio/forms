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
##
## Issue #643: the levels menu is GONE — the level is chosen right
## here, in the menu's TOP LINE: a drop-down with every available
## level (the stock skirmish maps, the two spectate duels, and every
## level saved in the editor) with a filter field to its right that
## narrows the drop-down's list as you type. The filter only hides
## entries — it never changes the pick; START always runs the
## explicitly chosen level (the spectate duels start directly, like
## the old levels-menu buttons did).
##
## Issue #649: a live LAN game makes this menu the SHARED lobby —
## the host and every connected player (nicknames carried from the
## LAN menu through the LanSession autoload) sit in it together.
## The host drives the setup and every change broadcasts to the
## connected players; the per-team controller choice is now WHO
## drives the team — the computer, the host, or one of the
## connected players by nickname. A connected player may edit
## (name, color, members) exactly the teams the host assigned to
## them — the edit travels to the host and comes back inside the
## next broadcast. When the host STARTS, the lobby ends (the match
## runs on the host device; the synchronized shared match over the
## wire remains the next step).

## Issue #643: the stock levels the drop-down offers, in order. The
## two spectate duels ride the same list — START runs them directly
## (nothing to configure: no player team, the cast is baked in).
const STOCK_LEVELS: Array[Dictionary] = [
	{"label": "Level 1", "path": "res://scenes/levels/Level1.tscn"},
	{"label": "Level 2", "path": "res://scenes/levels/Level2.tscn"},
	{"label": "Level 3", "path": "res://scenes/levels/Level3.tscn"},
	{"label": "Level 4", "path": "res://scenes/levels/Level4.tscn"},
	{"label": "Level 5", "path": "res://scenes/levels/Level5.tscn"},
	{"label": "Duel (spectate)",
		"path": "res://scenes/levels/Level6.tscn", "spectate": true},
	{"label": "Duel 3v3 (spectate)",
		"path": "res://scenes/levels/Level7.tscn", "spectate": true},
]

## Issue #643: editor-saved levels (issue #464) live here as JSON —
## they join the drop-down after the stock maps, alphabetically.
const LEVELS_DIR := "user://levels"

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

## Issue #643: every available level behind the drop-down (stock +
## editor-saved) and the entry the player picked — the filter only
## narrows what the drop-down SHOWS, never the choice itself.
var _levels: Array = []
var _level_choice: Dictionary = {}

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

## Issue #649: a live LAN game makes this menu the shared lobby.
var _lan := false
## Issue #649: true on the hosting machine — the lobby's authority.
var _lan_host := false

@onready var _level_option: OptionButton = %LevelOption
@onready var _level_filter: LineEdit = %LevelFilter
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
	# Issue #649: the shared LAN lobby — a live LAN game (LanSession)
	# makes this menu shared between the host and the connected
	# players.
	_lan = LanSession.active
	_lan_host = LanSession.active and LanSession.is_host
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
	# Issue #643: the level pick lives in the menu's top line now — a
	# drop-down of every available level plus a filter field to its
	# right.
	_levels = _available_levels()
	_level_option.item_selected.connect(_on_level_selected)
	_level_filter.text_changed.connect(_on_level_filter_changed)
	_restore_level_choice()
	_rebuild_level_options()
	# Issue #521: the team set for the level — loaded here (once) and
	# edited directly in GameConfig.teams; Start persists it. Issue
	# #649: a connected player keeps the host's broadcast set (their
	# local team.cfg is irrelevant in the lobby); local teams only
	# backfill the rows until the first sync lands.
	if not (_lan and not _lan_host) or GameConfig.teams.is_empty():
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
	if _lan:
		LanSession.setup_changed.connect(_on_lan_setup_changed)
		LanSession.players_changed.connect(_on_lan_players_changed)
		LanSession.connection_lost.connect(_on_lan_connection_lost)
		if not _lan_host:
			# The host owns the match setup: everything but the edits of
			# the team assigned to this player is read-only here, and only
			# the host may START the match.
			_level_option.disabled = true
			_level_filter.editable = false
			_turn_time.editable = false
			_night_regime.disabled = true
			_spawn_regime.disabled = true
			_add_team_button.disabled = true
			_start_button.visible = false
			_apply_remote_setup()
		else:
			# Take the connected players into the lobby right away.
			LanSession.push_setup(_level_choice)
			_start_button.grab_focus()
	else:
		_start_button.grab_focus()


# ------------------------------------------- level pick (issue #643) --

## Every available level: the stock maps (spectate duels included)
## then every editor-saved level, alphabetically.
func _available_levels() -> Array:
	var list: Array = []
	for entry in STOCK_LEVELS:
		list.append(entry.duplicate())
	var stems: Array[String] = []
	if DirAccess.dir_exists_absolute(LEVELS_DIR):
		for fname in DirAccess.get_files_at(LEVELS_DIR):
			if fname.ends_with(".json"):
				stems.append(fname.get_basename())
	stems.sort()
	for stem in stems:
		list.append({
			"label": stem.replace("_", " "),
			"path": "res://scenes/levels/CustomLevel.tscn",
			"custom_stem": stem,
		})
	return list


## The choice on open: whatever GameConfig still holds (the level of
## the previous round), else Level 1 — then write it back so both
## sides agree even when the stored path points at a custom level
## that no longer exists on disk.
func _restore_level_choice() -> void:
	_level_choice = _levels[0]
	var wanted := GameConfig.level_path
	if wanted.is_empty():
		wanted = _levels[0]["path"]
	for entry in _levels:
		if entry["path"] != wanted:
			continue
		var stem := str(entry.get("custom_stem", ""))
		# Custom levels share one scene path — the stem is the pick.
		if not stem.is_empty() and stem != GameConfig.custom_level_name:
			continue
		_level_choice = entry
		break
	_apply_level_choice()


## Write the pick to GameConfig: stock maps take the path (and clear
## any stale custom pick); customs point at CustomLevel.tscn with the
## JSON stem the level is built from.
func _apply_level_choice() -> void:
	GameConfig.level_path = _level_choice["path"]
	GameConfig.custom_level_name = str(_level_choice.get("custom_stem", ""))


## Fill the drop-down with the entries the filter lets through; the
## picked level stays selected whenever it is visible. `select` emits
## nothing, so restoring the shown selection never re-writes the
## choice.
func _rebuild_level_options() -> void:
	_level_option.clear()
	var needle := _level_filter.text.strip_edges().to_lower()
	var selected := -1
	for entry in _levels:
		if not needle.is_empty() \
				and not str(entry["label"]).to_lower().contains(needle):
			continue
		_level_option.add_item(str(entry["label"]))
		_level_option.set_item_metadata(_level_option.item_count - 1, entry)
		if entry == _level_choice:
			selected = _level_option.item_count - 1
	_level_option.select(selected)


func _on_level_selected(index: int) -> void:
	if index < 0 or index >= _level_option.item_count:
		return
	_level_choice = _level_option.get_item_metadata(index)
	_apply_level_choice()
	# Issue #649: the host's level pick rides the next broadcast.
	if _lan_host:
		LanSession.push_setup(_level_choice)


## Typing in the filter field narrows the drop-down's list only —
## GameConfig keeps the last explicit pick; emptying the filter
## brings the selection back.
func _on_level_filter_changed(_text: String) -> void:
	_rebuild_level_options()


func _on_start_pressed() -> void:
	if _lan:
		# Issue #649: the shared lobby ends when the host starts — the
		# match runs on this device (the connected players are returned
		# to the main menu by the dropped connection; the synchronized
		# shared match over the wire remains the next step).
		LanSession.shutdown()
	# Issue #643: the spectate duels have nothing to configure — START
	# runs them directly, exactly like the old levels-menu buttons.
	if _level_choice.get("spectate", false):
		MusicManager.play_for_level(GameConfig.level_path)
		get_tree().change_scene_to_file(GameConfig.level_path)
		return
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
		controller.custom_minimum_size = Vector2(0, 40)
		controller.add_theme_font_size_override("font_size", 16)
		if _lan:
			# Issue #649: in the LAN lobby the per-team choice is WHO
			# drives the team — the computer, the host, or one of the
			# connected players — picked by nickname. The host picks;
			# the connected players see the pick.
			var parts := LanSession.participants()
			controller.add_item("Computer")
			for part in parts:
				controller.add_item(str(part["nick"]))
			controller.select(_lan_controller_index(i, parts))
			controller.disabled = not _lan_host
			if _lan_host:
				var lan_team_index := i
				controller.item_selected.connect(func(index: int) -> void:
					_on_lan_controller_selected(lan_team_index, index))
		else:
			controller.add_item("Computer")
			controller.add_item("Player")
			controller.select(1 if GameConfig.team_controller(i) == "player" else 0)
			var team_index := i
			controller.item_selected.connect(func(index: int) -> void:
				var choice := "player" if index == 1 else "computer"
				GameConfig.teams[team_index]["controller"] = choice)
		row.add_child(controller)
		var remove := Button.new()
		remove.text = "Remove"
		remove.custom_minimum_size = Vector2(0, 40)
		remove.add_theme_font_size_override("font_size", 16)
		# Issue #649: only the host may drop teams in the LAN lobby.
		remove.disabled = GameConfig.teams.size() <= 2 or (_lan and not _lan_host)
		remove.pressed.connect(func() -> void: _on_remove_team_pressed(i))
		row.add_child(remove)
		_teams_list.add_child(row)
	# Issue #649: only the host may add teams in the LAN lobby.
	_add_team_button.disabled = GameConfig.teams.size() >= GameConfig.MAX_TEAMS \
			or (_lan and not _lan_host)


## Issue #649: the LAN drop-down index of a team's current driver
## (0 = Computer, 1.. = the participants, the host first). A
## player-driven team whose driver is not in the roster yet shows as
## Computer until the roster syncs in.
func _lan_controller_index(team_index: int, parts: Array) -> int:
	if GameConfig.team_controller(team_index) != "player":
		return 0
	var peer := LanSession.team_peer(team_index)
	for i in parts.size():
		if int(parts[i]["peer"]) == peer:
			return 1 + i
	return 0


## Issue #649: the host assigns a team to the computer, themselves,
## or one of the connected players — the assignment rides the next
## setup broadcast.
func _on_lan_controller_selected(team_index: int, index: int) -> void:
	if not (_lan and _lan_host) or team_index >= GameConfig.teams.size():
		return
	if index <= 0:
		GameConfig.teams[team_index]["controller"] = "computer"
		LanSession.team_peers.erase(team_index)
	else:
		var parts := LanSession.participants()
		if index - 1 >= parts.size():
			return
		GameConfig.teams[team_index]["controller"] = "player"
		LanSession.team_peers[team_index] = int(parts[index - 1]["peer"])
	_after_local_edit()


## Issue #649: offline everyone edits every team; in the LAN lobby
## the host edits every team and a connected player exactly the teams
## the host assigned to them.
func _can_edit_team(team_index: int) -> bool:
	if not _lan or _lan_host:
		return true
	return LanSession.team_peer(team_index) == LanSession.my_peer_id()


## Issue #649: after any local edit — the host's edit broadcasts to
## the connected players, a connected player's edit travels to the
## host as a request; the rows rebuild on top either way.
func _after_local_edit(team_index := -1) -> void:
	if _lan and not _lan_host:
		if team_index >= 0 and team_index < GameConfig.teams.size():
			LanSession.submit_team_change(team_index,
					GameConfig.teams[team_index].duplicate(true))
		_rebuild_team_rows()
		return
	if _lan_host:
		LanSession.push_setup(_level_choice)
	_rebuild_team_rows()


## Issue #649 (client): adopt the host's last broadcast setup.
func _apply_remote_setup() -> void:
	if LanSession.setup_level.size() > 0:
		_level_choice = LanSession.setup_level
	_apply_level_choice()
	_rebuild_level_options()
	_rebuild_team_rows()


func _on_lan_setup_changed() -> void:
	_rename_team_index = -1
	if _lan_host:
		# A connected player's edit (or a player leaving) changed the
		# live set — the rows just follow it.
		_rebuild_team_rows()
		return
	_apply_remote_setup()


func _on_lan_players_changed() -> void:
	# The driver drop-downs list the participants by nickname —
	# rebuild when the roster changes.
	_rebuild_team_rows()


func _on_lan_connection_lost(_reason: String) -> void:
	# The host left (or the connection died): the lobby is over —
	# back to the main menu (the session already shut down).
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


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
	# Issue #649: only the team's driver (or the host, or everyone
	# offline) may recolor it.
	if not _can_edit_team(team_index):
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
		# Issue #649: a connected player's recolor travels to the host.
		_color_popup.popup_hide.connect(func() -> void:
			var edited := _color_team_index
			_color_team_index = -1
			_after_local_edit(edited))
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
	# Issue #649: only the team's driver (or the host, or everyone
	# offline) may rename it.
	if not _can_edit_team(team_index):
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
	# Issue #649: a connected player's rename travels to the host.
	_after_local_edit(team_index)


## Owner item 2: a filled square's click drops that teammate; one is
## the floor — a team always fields at least one figure.
func _remove_member(team_index: int, member_index: int) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	# Issue #649: only the team's driver (or the host, or everyone
	# offline) may resize it.
	if not _can_edit_team(team_index):
		return
	var names: Array = GameConfig.teams[team_index]["names"]
	if member_index < 0 or member_index >= names.size() or names.size() <= 1:
		return
	names.remove_at(member_index)
	_after_local_edit(team_index)


## Owner item 3: a free square's click appends a teammate, up to the
## 4x16 tier's 64.
func _add_member(team_index: int) -> void:
	if team_index < 0 or team_index >= GameConfig.teams.size():
		return
	# Issue #649: only the team's driver (or the host, or everyone
	# offline) may resize it.
	if not _can_edit_team(team_index):
		return
	var names: Array = GameConfig.teams[team_index]["names"]
	if names.size() >= GameConfig.MAX_LEVEL_TEAM_MEMBERS:
		return
	names.append("Member %d" % (names.size() + 1))
	_after_local_edit(team_index)


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
	_after_local_edit()


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
	# Issue #649: only the host may drop teams in the LAN lobby (the
	# button is disabled there; this guards the call path).
	if _lan and not _lan_host:
		return
	GameConfig.teams.remove_at(index)
	# Issue #537 rework v3: keep the original-identity list aligned with
	# the live set — the removed team's original leaves with it.
	if index >= 0 and index < _game_identity.size():
		_game_identity.remove_at(index)
	# Issue #649: the host's driver assignment of the dropped team
	# goes with it.
	if _lan_host:
		LanSession.team_peers.erase(index)
		var shifted: Dictionary = {}
		for team_index in LanSession.team_peers.keys():
			if int(team_index) > index:
				shifted[int(team_index) - 1] = LanSession.team_peers[team_index]
			else:
				shifted[int(team_index)] = LanSession.team_peers[team_index]
		LanSession.team_peers = shifted
	_rename_team_index = -1
	_after_local_edit()


## Issue #643: the levels menu is gone — Back returns to the MAIN
## menu (and Escape with it, see _unhandled_input below).
func _on_back_pressed() -> void:
	# Issue #649: leaving the setup menu ends the LAN session — no
	# peer outlives the game.
	if _lan:
		LanSession.shutdown()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the main menu (issue #643: the levels menu
## in between is gone).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
