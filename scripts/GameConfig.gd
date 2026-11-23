extends Object
class_name GameConfig
## Level configuration chosen before a level begins (issue #137).
##
## The levels menu stores the picked level here, the level configuration
## menu fills the options in, and each playable level applies the settings
## in _ready (via LevelConfig.gd attached to the level root).

## Path of the level the player picked in the levels menu.
static var level_path := ""

## Issue #464 rework: stem of the editor-authored level (under
## user://levels/) the player picked in the levels menu — read by
## CustomLevel.gd to build the playable scene from the JSON.
static var custom_level_name := ""

## Members of the player team including the hero. 0 = NOT CHOSEN:
## the configured team set drives the count then (Issue #537 rework
## v4 — classic fields mirror the set, they no longer fight it).
static var team_size := 0

## Number of computer opponents staged by the levels (Npc..Npc3 plus
## the extra casts). 0 = NOT CHOSEN: the set's SECOND team count drives
## it (Issue #537 rework v4).
static var enemy_count := 0

## Issue #180: AI behavior parameters belong to the TEAM configuration
## (edited in the team menu), not to the level configuration.

## AI skill: 0..10. Mapped onto the NPC difficulty bands — 0..3 = easy,
## 4..7 = normal, 8..10 = hard (aim slew speed + pause between shots).
static var ai_skill := 5

## AI friendly-fire: 0 = the computer ALWAYS avoids friendly fire,
## 10 = it does not care at all (in between the avoidance checks are
## applied probabilistically per shot).
static var ai_friendly_fire := 0

## Issue #192: per-turn time limit in seconds, set in the level
## configuration menu and read by TurnController when a turn starts.
static var turn_time := 15.0

## Issue #367: night regime — chosen in the level configuration menu
## before the level starts. While on, the level plays in darkness:
## a mask layer hides everything beyond the player's figures' vision
## wedges (aimed along their live aim) and beyond every light source
## (muzzle flashes, projectiles, explosions — see
## scripts/NightRegime.gd).
static var night_regime := false

## Issue #523: spawn regime — chosen in the level configuration menu
## before the level starts. 0 = teams grouped together around one
## random team anchor, 1 = every figure spawns on its own random spot,
## 2 = spawn points defined in the level by the designer (Marker2D
## nodes in the "spawn_points" group; levels without markers keep the
## authored figure positions — today's behavior, and the default),
## 3 = issue #547 "choose after the start": the level runs, the game
## pauses, and the player clicks every hero-team figure onto a spot
## of their choosing (see scripts/SpawnChooser.gd).
## See scripts/SpawnRegime.gd.
static var spawn_regime := SpawnRegime.REGIME_DESIGNER

## Issue #169: player team customisation, edited in the team menu and
## persisted to user://team.cfg. Since issue #208 the menu edits the
## whole set of teams (see `teams` below); these single-team fields stay
## the runtime source every level applies.

## Team color of the player's figures (also used for the turn banner).
static var team_color := Color(1, 0.84, 0.2, 1)

## Shape of the player's figures: square, circle, triangle, star or ellipse.
static var team_shape := "square"

## Names of the team members (index 0 is the hero).
## Issue #617 rework v2 (owner 2026-11-17): two entries — the default
## any level fields is 3 teams × 2 mates.
static var member_names: Array[String] = ["Player 1", "Player 2"]

## Issue #252: debug mode — ON by default, switched in the settings
## menu. While on, the OSD (zoom/FPS/level/HP readout), the per-figure
## debug visuals (HP number, damage numbers, arrows) and the top-right
## action log are shown; while off the game plays exactly as before.
static var debug_mode := true

## Issue #290: debug gravity vector field — OFF by default, switched in
## the settings menu NEXT TO the debug mode. While on, the camera shows
## the level's gravity field as arrows on a world-space grid whose cell
## is two character widths wide: at every grid point an arrow points
## where gravity pulls a figure there (see scripts/GravityFieldDebug.gd).
static var debug_gravity_field := false

## Main-menu spec §6.3 (milestone M3, 2026-11-12): display settings —
## chosen in the graphics settings screen (GraphicsMenu), persisted in
## settings.cfg next to the debug switches and applied at boot plus on
## every change (GameConfig.apply_display_settings).
## display_mode: 0 = windowed, 1 = fullscreen. Defaults keep today's
## behavior: windowed, base resolution, vsync on.
static var display_mode := 0

## Windowed resolution preset (16:9 list; fullscreen uses the desktop
## resolution, so this only applies while windowed).
static var window_size := Vector2i(1152, 648)

## VSync on/off.
static var vsync := true

## Issue #472: audio settings — chosen in the audio settings screen
## (AudioMenu), persisted in settings.cfg next to the display settings
## and applied at boot plus on every change
## (GameConfig.apply_audio_settings). Linear 0..1 slider values mapped
## onto the audio buses' volume in dB. The defaults keep today's mix
## exactly: Master and SFX ride their authored 0 dB, Music its authored
## -6 dB (0.5 linear is -6.02 dB).
static var master_volume := 1.0

## Music bus volume (MusicManager rides the Music bus).
static var music_volume := 0.5

## SFX bus volume (the sound effects ride the SFX bus).
static var sfx_volume := 1.0

## Issue #472: push the persisted audio settings to the AudioServer —
## called at boot (Main, after load_settings) and on every change in
## AudioMenu. Linear 0..1 maps through linear_to_db(); 0 is floored to
## the -80 dB hard-mute threshold because linear_to_db(0) is -INF.
## Safe on the dummy audio driver (headless): wiring and persistence
## are asserted, not sound.
static func apply_audio_settings() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


## Issue #472: set one bus' linear volume on the AudioServer; unknown
## bus names (no matching bus in default_bus_layout.tres) are skipped.
static func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	var db := -80.0 if clamped <= 0.0001 else linear_to_db(clamped)
	AudioServer.set_bus_volume_db(index, db)


## Owner decision Q2 (2026-11-06): the graphics category is HIDDEN on
## touch devices — display mode/resolution/vsync are not meaningful
## there. Detected through OS features so it works before any scene.
static func is_touch_device() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") \
		or OS.has_feature("mobile")


## Main-menu spec §6.3: push the persisted display settings to the
## DisplayServer — called at boot (Main, after load_settings) and on
## every change in GraphicsMenu. Headless runs sit on the dummy
## renderer: the calls are safe no-ops there (tests assert wiring and
## persistence, not pixels).
static func apply_display_settings() -> void:
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if display_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)

## Issue #294: custom hotkeys — a PHYSICAL keycode per action name,
## persisted under [hotkeys] in settings.cfg and applied over the project
## defaults when the game starts (the hotkeys screen edits this map).
## Physical keycodes follow the key POSITION, so a rebind keeps working
## on any keyboard layout. An action missing here uses the project
## defaults (which may hold several keys, e.g. move_left = A or Left).
static var hotkeys: Dictionary = {}

## Issue #294: the project's authored bindings, snapshotted ONCE before
## any saved override is applied — "Reset to defaults" restores these
## (action name -> Array of InputEvent).
static var _hotkey_defaults: Dictionary = {}

## Issue #294: the actions the hotkeys screen offers, in display order.
const HOTKEY_ACTIONS: Array[String] = [
	"move_left", "move_right", "jump", "view_up", "view_down", "shoot",
	"camera_switch", "switch_next", "switch_prev",
	"weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5",
	"tool_1", "tool_2", "tool_3", "tool_4",
]

## Issue #252: the debug-mode switch persists in its own settings file,
## separate from the team customisation (team.cfg).
const SETTINGS_PATH := "user://settings.cfg"

const _SAVE_PATH := "user://team.cfg"

## Issue #208: the whole set of teams shown in the team menu — an ORDERED
## set with neutral names (owner rework: there is no "Player Team"/
## "Enemies" concept; in the game the player may choose ANY team and the
## computer plays any of the left ones). Persisted in the same team.cfg
## under the "teams" section; the single-team keys above stay in sync with
## it. Until in-game team choice lands, the levels still apply teams[0] to
## the player figures and teams[1]'s AI parameters to the computer team
## (slot-order compatibility, not a user-facing designation).
static var teams: Array = []

## Issue #208: the levels place at most three figures per team (hero +
## two teammates / Npc..Npc3) and the menu list must stay readable.
const MAX_TEAM_MEMBERS := 3
const MAX_TEAMS := 8

## Issue #537 rework: the level-config menu's member grid may grow a
## team across the 1x4 / 2x8 / 4x16 tiers up to 64 teammates. The cap
## the TEAM MENU and the staged levels use stays MAX_TEAM_MEMBERS
## above; this one bounds the grid and the persisted names the level
## menu may edit.
const MAX_LEVEL_TEAM_MEMBERS := 64

## Issue #537: the default squad size of a fresh team.
## Issue #617 rework v2 (owner 2026-11-17): TWO members — the default
## any level fields is 3 teams × 2 mates (the 1x4 grid keeps two free
## "+" spots).
const DEFAULT_TEAM_MEMBERS := 2

## Issue #524: the languages a team may speak — picked per team in the
## team menu; that team's teammates' spoken lines (CharacterLines)
## follow it.
const LANGUAGES: Array[String] = ["English", "Spanish", "Russian", "French", "Arabic"]
## Issue #524: the language every team speaks unless configured otherwise
## (also the fallback for a stored value that is no longer supported).
const DEFAULT_LANGUAGE := "English"


## Issue #226: the default set of teams = the teams that are in the
## levels, with NEUTRAL names (owner rework: no player/enemies concept
## in the team configuration) and DISTINCT body shapes per team.
## Issue #617 rework v2 (owner 2026-11-17): the default set is exactly
## THREE teams of TWO members each and EVERY team plays the computer —
## running any level without configuring anything fields 3 teams × 2
## computer-played mates. The player opts a team in through the level
## configuration menu.
static func default_teams() -> Array:
	var first_names: Array[String] = []
	for member_name in member_names:
		first_names.append(member_name)
	var member_names_for := func() -> Array[String]:
		var list: Array[String] = []
		for i in range(1, DEFAULT_TEAM_MEMBERS + 1):
			list.append("Member %d" % i)
		return list
	return [
		{
			"label": "Team 1", "color": team_color,
			"shape": team_shape, "names": first_names,
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": DEFAULT_LANGUAGE,
			"controller": "computer",
		},
		{
			"label": "Team 2", "color": Color(0.75, 0.2, 0.45, 1),
			"shape": "circle",
			"names": member_names_for.call(),
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": DEFAULT_LANGUAGE,
			"controller": "computer",
		},
		{
			"label": "Team 3", "color": Color(0.9, 0.3, 0.3, 1),
			"shape": "star",
			"names": member_names_for.call(),
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": "Russian",
			"controller": "computer",
		},
	]


## Issue #521: who plays a team — "player" (a human, hot-seat on this
## device) or "computer" (the AI). The stored set may predate the key
## (older team.cfg) — a missing value plays the COMPUTER on every slot
## (issue #617 rework v2: the player opts a team in through the level
## configuration menu; nothing is human until then).
static func team_controller(index: int) -> String:
	# Issue #617: with NO team set at all (tests, a fresh boot before
	# the team menu or apply() ever loaded one) every slot plays the
	# computer — running a level directly fields computers only.
	if teams.is_empty():
		return "computer"
	if index < 0 or index >= teams.size():
		return "computer"
	var controller := str(teams[index].get("controller", ""))
	if controller == "player" or controller == "computer":
		return controller
	# Issue #617 rework v2: every slot plays the computer unless the
	# stored set says otherwise explicitly.
	return "computer"


## Issue #521: the controller of the configured team that wears this
## COLOR (levels stage extra teams by color — TurnController gives each
## enemy color its own team id and asks this map whether that team is
## human). Unknown colors play the computer.
static func team_controller_for_color(color: Color) -> String:
	for i in teams.size():
		if teams[i].get("color") is Color and teams[i]["color"] == color:
			return team_controller(i)
	return "computer"


## Issue #524: the language of the configured team that wears this
## COLOR — figures carry their team's color on the field, and that is
## how their spoken lines (CharacterLines) find the team's language.
## Unknown colors speak the default (English).
static func team_language_for_color(color: Color) -> String:
	for team in teams:
		if team.get("color") is Color and team["color"] == color:
			return _valid_language(str(team.get("language", DEFAULT_LANGUAGE)))
	return DEFAULT_LANGUAGE


## Issue #524: clamp a stored language to the supported set — a
## missing or unsupported value falls back to the default.
static func _valid_language(language: String) -> String:
	return language if LANGUAGES.has(language) else DEFAULT_LANGUAGE


## Issue #208: load the saved set of teams (falling back to the default
## set from the levels), then keep the single-team fields in sync.
## Issue #617 rework v2 (owner 2026-11-17): only a set saved by the
## CURRENT team code is trusted — it is stamped `teams/set_version`.
## An older team.cfg was written by the pre-#617 defaults (four
## 3-member teams with a PLAYER first team), so it is replaced by the
## fresh defaults (3 teams × 2 members, all computer) exactly once;
## every save after that carries the stamp and round-trips normally.
static func load_teams() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) == OK and cfg.has_section_key("teams", "set") \
				and cfg.has_section_key("teams", "set_version"):
		teams = _sanitize_teams(cfg.get_value("teams", "set", []))
	else:
		teams = default_teams()
	_sync_from_teams()


## Issue #208: persist the whole set of teams and, from it, the classic
## single-team keys every level applies (kept in one file).
static func save_teams() -> void:
	_sync_from_teams()
	var cfg := ConfigFile.new()
	cfg.load(_SAVE_PATH)  # keep any other keys; missing file is fine
	cfg.set_value("teams", "set", teams)
	# Issue #617 rework v2: stamp the save so load_teams knows it was
	# written by the current team code (see the version gate there).
	cfg.set_value("teams", "set_version", 1)
	cfg.set_value("team", "color", team_color)
	cfg.set_value("team", "shape", team_shape)
	cfg.set_value("team", "names", member_names)
	cfg.set_value("ai", "skill", ai_skill)
	cfg.set_value("ai", "friendly_fire", ai_friendly_fire)
	cfg.save(_SAVE_PATH)


## Keep the single-team fields the levels apply in sync with the set.
## Compatibility with the current levels (they host two teams): teams[0]
## drives the figures the player controls, teams[1] (if present) drives
## the computer team's AI behavior — slot order only, no user-facing
## player/enemies designation (owner rework, issue #208).
static func _sync_from_teams() -> void:
	if teams.is_empty():
		return
	var player: Dictionary = teams[0]
	team_color = player["color"]
	team_shape = player["shape"]
	# Issue #537 rework v4 (owner: menu counts ignored in the level):
	# the classic fields MIRROR the configured set exactly. The old sync
	# capped member_names at its PREVIOUS size (a 4th teammate never
	# registered — the level kept fielding 3) and NEVER touched
	# enemy_count (stale default 2 — the level kept fielding two foes),
	# so any start outside the config menu ignored the menu's counts.
	var names: Array[String] = []
	for member_name in (player["names"] as Array).slice(
				0, MAX_LEVEL_TEAM_MEMBERS):
		names.append(str(member_name))
	if names.is_empty():
		names.append("Player 1")
	member_names = names
	team_size = maxi(1, member_names.size())
	if teams.size() > 1:
		enemy_count = maxi(1, mini((teams[1]["names"] as Array).size(),
				MAX_LEVEL_TEAM_MEMBERS))
	var ai_team: Dictionary = teams[1] if teams.size() > 1 else player
	ai_skill = clampi(int(ai_team["skill"]), 0, 10)
	ai_friendly_fire = clampi(int(ai_team["friendly_fire"]), 0, 10)


## The cfg file is user-editable, so validate every entry; anything
## broken falls back to sane defaults instead of crashing the menu.
static func _sanitize_teams(raw: Array) -> Array:
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var team: Dictionary = entry
		var names: Array[String] = []
		if team.get("names") is Array:
			# Issue #537: the level-config grid may persist up to the
			# 4x16 tier of names per team.
			for member_name in team["names"].slice(0, MAX_LEVEL_TEAM_MEMBERS):
				var text := str(member_name).strip_edges()
				names.append(text if not text.is_empty() else "Member %d" % (names.size() + 1))
		if names.is_empty():
			names.append("Member 1")
		var shape := str(team.get("shape", "square"))
		if not ["square", "circle", "triangle", "star", "ellipse"].has(shape):
			shape = "square"
		var controller := str(team.get("controller", ""))
		if controller != "player" and controller != "computer":
			# Issue #617 rework v2: a missing/unknown controller plays the
			# computer on EVERY slot (no slot-0 player fallback).
			controller = "computer"
		out.append({
			"label": str(team.get("label", "Team %d" % (out.size() + 1))),
			"color": team["color"] if typeof(team.get("color")) == TYPE_COLOR else Color(1, 1, 1),
			"shape": shape, "names": names,
			"skill": clampi(int(team.get("skill", 5)), 0, 10),
			"friendly_fire": clampi(int(team.get("friendly_fire", 0)), 0, 10),
			"language": _valid_language(str(team.get("language", DEFAULT_LANGUAGE))),
			"controller": controller,
		})
	return out.slice(0, MAX_TEAMS) if not out.is_empty() else default_teams()


## Issue #169: load the saved team customisation (if any) into these
## static fields; called by the team menu and before applying a level.
static func load_team() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return
	team_color = cfg.get_value("team", "color", team_color)
	team_shape = cfg.get_value("team", "shape", team_shape)
	var names: Array = cfg.get_value("team", "names", member_names)
	if names.size() == member_names.size():
		for i in names.size():
			member_names[i] = str(names[i])
	# Issue #180: AI behavior parameters persist with the team.
	ai_skill = clampi(int(cfg.get_value("ai", "skill", ai_skill)), 0, 10)
	ai_friendly_fire = clampi(int(cfg.get_value("ai", "friendly_fire", ai_friendly_fire)), 0, 10)


## Issue #169: persist the current team customisation.
static func save_team() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("team", "color", team_color)
	cfg.set_value("team", "shape", team_shape)
	cfg.set_value("team", "names", member_names)
	# Issue #180: AI behavior parameters persist with the team.
	cfg.set_value("ai", "skill", ai_skill)
	cfg.set_value("ai", "friendly_fire", ai_friendly_fire)
	cfg.save(_SAVE_PATH)


## Issue #252: load the persisted debug-mode setting (missing file keeps
## the default ON).
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# Issue #294: even without a settings file the authored hotkey
		# defaults must be snapshotted, so a later Reset can restore them.
		capture_hotkey_defaults()
		return
	debug_mode = cfg.get_value("settings", "debug_mode", true)
	debug_gravity_field = cfg.get_value("settings", "gravity_field", false)
	# Main-menu spec §6.3 (M3): display settings, same defaults as the
	# statics when the keys are missing (first boot, older settings.cfg).
	display_mode = cfg.get_value("settings", "display_mode", 0)
	window_size = cfg.get_value("settings", "window_size",
		Vector2i(1152, 648))
	vsync = cfg.get_value("settings", "vsync", true)
	# Issue #472: audio settings, same defaults as the statics when the
	# keys are missing (first boot, older settings.cfg).
	master_volume = cfg.get_value("settings", "master_volume", 1.0)
	music_volume = cfg.get_value("settings", "music_volume", 0.5)
	sfx_volume = cfg.get_value("settings", "sfx_volume", 1.0)
	# Issue #294: custom hotkeys — snapshot the authored defaults FIRST,
	# then apply whatever was saved over them.
	capture_hotkey_defaults()
	var saved: Dictionary = cfg.get_value("hotkeys", "bindings", {})
	for action in saved:
		if action is String and int(saved[action]) > 0:
			hotkeys[action] = int(saved[action])
	apply_hotkeys()

## Issue #252: persist the debug-mode setting.
static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep any other keys; missing file is fine
	cfg.set_value("settings", "debug_mode", debug_mode)
	cfg.set_value("settings", "gravity_field", debug_gravity_field)
	# Main-menu spec §6.3 (M3): display settings.
	cfg.set_value("settings", "display_mode", display_mode)
	cfg.set_value("settings", "window_size", window_size)
	cfg.set_value("settings", "vsync", vsync)
	# Issue #472: audio settings.
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.save(SETTINGS_PATH)


## Issue #294: snapshot the project's authored bindings once, before any
## saved override is applied (load_settings runs in the main menu, before
## any level can read input).
static func capture_hotkey_defaults() -> void:
	if not _hotkey_defaults.is_empty():
		return
	for action in HOTKEY_ACTIONS:
		if InputMap.has_action(action):
			var events: Array[InputEvent] = []
			for event in InputMap.action_get_events(action):
				events.append(event)
			_hotkey_defaults[action] = events


## Issue #294: apply the saved custom bindings — exactly ONE physical key
## per rebound action replaces every authored event (the hotkeys screen
## shows one key per action; the authored alternates such as A / Left come
## back with reset_hotkeys). Unknown actions or broken values are dropped.
static func apply_hotkeys() -> void:
	for action in hotkeys.keys():
		if not (action is String) or not InputMap.has_action(action) \
				or int(hotkeys[action]) <= 0:
			hotkeys.erase(action)
			continue
		var event := InputEventKey.new()
		event.physical_keycode = int(hotkeys[action]) as Key
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## Issue #294: rebind one action (from the hotkeys screen) and persist it
## at once, so the choice survives a restart.
static func set_hotkey(action: String, physical_keycode: int) -> void:
	hotkeys[action] = physical_keycode
	apply_hotkeys()
	save_hotkeys()


## Issue #294: restore the authored project bindings and forget every
## override.
static func reset_hotkeys() -> void:
	hotkeys = {}
	for action in _hotkey_defaults:
		InputMap.action_erase_events(action)
		for event in _hotkey_defaults[action]:
			InputMap.action_add_event(action, event)
	save_hotkeys()


## Issue #294: persist the custom hotkey bindings (own section in the
## settings file, next to the debug switches).
static func save_hotkeys() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep any other keys; missing file is fine
	cfg.set_value("hotkeys", "bindings", hotkeys)
	cfg.save(SETTINGS_PATH)


static func apply(level: Node) -> void:
	_dealt = 0
	_dealt_counts = {}
	_dealt_figures = {}
	# Issue #226: make sure the team set is loaded (fresh defaults give
	# every team its own shape) even if the player never opened the team
	# menu. Issue #537 rework v4: an EXPLICIT classic choice (tests,
	# tools) must survive the implicit load — the load's sync would
	# otherwise stomp team_size/enemy_count back to the set's counts
	# (the fresh-boot default is 0 = "follow the set").
	var chosen_heroes := team_size
	var chosen_foes := enemy_count
	if teams.is_empty():
		load_teams()
	if chosen_heroes > 0:
		team_size = chosen_heroes
	if chosen_foes > 0:
		enemy_count = chosen_foes
	# Issue #617 rework v2 (owner 2026-11-17): with no EXPLICIT classic
	# count (team_size unset — a direct run, a fresh boot, a chained
	# next level) the configured TEAM SET drives the level exactly like
	# the menu path: the defaults (3 teams × 2 mates, all computer) are
	# what "run any level" fields, regardless of the staged cast.
	var menu_driven := menu_team_sizes or chosen_heroes <= 0
	# Issue #613: the level scenes stage JUST CHARACTERS (plain
	# Character.gd bodies with no brain) — dress each with its
	# controller BEFORE the trim/deal passes run, so every later pass
	# sees the classic scripted cast it addresses by node name.
	_dress_just_characters(level)
	# Trim the player team: keep the hero plus team_size - 1 teammates.
	# Issue #537 rework v3 (owner item 2): when the level menu drove the
	# team set, the count comes straight from the menu's grid —
	# teams[0]["names"] — and figures beyond the staged three SPAWN
	# beside the hero, so the level fields exactly the chosen count.
	# Issue #537 rework v4: an UNSET team_size (0 — the boot default)
	# also follows the set, so levels started OUTSIDE the config menu
	# (duel buttons, editor preview, direct runs) field the configured
	# counts instead of stale 3/2 defaults.
	var hero_count: int = team_size
	if menu_driven and not teams.is_empty():
		hero_count = (teams[0]["names"] as Array).size()
	# Issue #617: trim the first team to the chosen count — the uniform
	# Team1mate* staging and the legacy Player/Teammate* pair (both are
	# member 2 and 3 of the first team).
	for entry in [["Teammate1", 2], ["Teammate2", 3],
			["Team1mate2", 2], ["Team1mate3", 3]]:
		if int(entry[1]) > hero_count:
			var member := level.get_node_or_null(NodePath(str(entry[0])))
			if member != null:
				member.queue_free()
	# Issue #537 rework v4: the gate stays > 3 — beyond the classic trio
	# the configured count spawns extras; a team of at most three fields
	# only the staged cast (the #521 swap stays 1:1 with the staging).
	if hero_count > 3:
		_spawn_missing_player_figures(level, hero_count)
	# Trim the enemy team: the scenes place at most Npc..Npc3, and the
	# uniform #617 staging names every enemy figure Team<N>mate<M>
	# (N >= 2) — sorted so the trim/deal passes walk teams in order.
	# Issue #617 fix: the list must hold only slots that EXIST — the
	# legacy Npc* placeholders consumed deal indices on uniform levels
	# (the first staged enemy sat at i=3 and the enemy_count trim freed
	# it — a direct duel run lost its whole enemy side).
	var npcs: Array[String] = []
	for legacy in ["Npc", "Npc2", "Npc3"]:
		if level.get_node_or_null(NodePath(legacy)) != null:
			npcs.append(legacy)
	for child in level.get_children():
		var staged_enemy := _staged_team_slot(str(child.name))
		if staged_enemy.size() == 2 and staged_enemy[0] >= 2:
			npcs.append(str(child.name))
	npcs.sort_custom(func(a, b):
		return _staged_team_slot(a) < _staged_team_slot(b))
	# Issue #180: AI behavior parameters come from the team configuration:
	# skill maps onto the difficulty bands, friendly-fire passes through.
	var ai_difficulty := 0 if ai_skill <= 3 else (1 if ai_skill <= 7 else 2)
	# Issue #521: the configured teams BEYOND the first are dealt
	# round-robin onto the kept enemy figures — every configured team gets
	# its own color/shape/names, so TurnController._scan_teams discovers
	# one distinct team per configured team (as long as enough enemy
	# figures are staged — the "enemy count" field above). A team marked
	# "player" (hot-seat) replaces its computer figures with human
	# Player.gd figures staged on the enemy side (team_side = "enemy").
	var extra := maxi(1, teams.size() - 1)
	# Issue #617: with the uniform staging the chosen enemy count caps
	# EACH staged team's roster (Team2's three mates), not the level's
	# whole enemy side — a level may stage several teams (Level4 stages
	# three) and they must survive the trim as teams.
	var staged_kept := {}
	# Issue #226: NPCs staged for the player side (duel levels,
	# team = "player") keep taking teams[0]'s looks.
	for i in npcs.size():
		var npc := level.get_node_or_null(NodePath(npcs[i]))
		if npc == null:
			continue
		if enemy_count > 0 and not menu_driven:
			var slot := _staged_team_slot(str(npc.name))
			if slot.size() == 2:
				var kept: int = staged_kept.get(int(slot[0]), 0)
				if kept >= enemy_count:
					npc.queue_free()
					continue
				staged_kept[int(slot[0])] = kept + 1
			elif i >= enemy_count:
				npc.queue_free()
				continue
		if str(npc.get("team")) == "player":
			if npc.get("difficulty") != null:
				npc.set("difficulty", ai_difficulty)
			if npc.get("ai_friendly_fire") != null:
				npc.set("ai_friendly_fire", ai_friendly_fire)
			if npc.has_method("set_team_shape"):
				npc.call("set_team_shape", team_shape)
			continue
		var staged_deal := _staged_team_slot(str(npc.name))
		# Issue #617: a staged Team<N> (N >= 2) maps onto ONE configured
		# team — figures staged together stay one team. The legacy Npc*
		# staging keeps the round-robin deal.
		var dealt_team := 1 + ((int(staged_deal[0]) - 2) % extra) \
				if staged_deal.size() == 2 else 1 + (_dealt % extra)
		_record_dealt_figure(dealt_team, _apply_extra_team(level, npc, dealt_team))
		_dealt += 1
	# Issue #226 rework: shape EVERY enemy figure, not only Npc..Npc3 —
	# Level4 stages Npc4..Npc9, which the name list above never reached.
	# Issue #521: those extras join the same round-robin deal.
	for npc_node in level.get_tree().get_nodes_in_group("enemy_team"):
		if npc_node == null or npc_node.is_queued_for_deletion():
			continue
		if npc_node.get_parent() != level or npcs.has(str(npc_node.name)):
			continue
		if not npc_node.has_method("_shoot"):
			# Issue #521: a human figure staged in the deal above is
			# already fully dressed — only staged COMPUTER figures
			# (Level4's Npc4..Npc9, the duel levels' figures) join here.
			continue
		if str(npc_node.get("team")) == "player":
			if npc_node.has_method("set_team_shape"):
				npc_node.call("set_team_shape", team_shape)
			continue
		_apply_extra_team_staged(level, npc_node)
	# Issue #169: apply the customised team color, shape and names.
	# Issue #537 rework v3: figures trimmed moments ago still sit in the
	# group until the frame ends — name by the LIVE index, and with
	# menu-driven sizes read the first team's names straight from the
	# menu set (the grids go to 64, the classic fields cap at three).
	var live_members: Array = []
	for staged in level.get_tree().get_nodes_in_group("player_team"):
		if not staged.is_queued_for_deletion():
			live_members.append(staged)
	var hero_names: Array = (teams[0]["names"] as Array) \
			if menu_driven else member_names
	for member in live_members:
		if member.get("display_name") != null:
			var idx := live_members.find(member)
			member.set("display_name",
					str(hero_names[mini(idx, hero_names.size() - 1)]))
		if member.has_method("apply_team_setup"):
			member.call("apply_team_setup")
		elif member.get("team_color") != null:
			# Issue #617: the hero side now plays COMPUTER figures (Npc.gd
			# has no apply_team_setup) — the team's configured looks must
			# still land on them, exactly like on human figures: the menu
			# set when it drove the sizes, the CLASSIC customisation fields
			# otherwise (issue #169).
			if menu_driven:
				member.set("team_color", teams[0]["color"])
				member.set("team_shape", str(teams[0]["shape"]))
			else:
				member.set("team_color", team_color)
				member.set("team_shape", team_shape)
			if member.has_method("_apply_team_color"):
				member.call("_apply_team_color")
			if member.has_method("set_team_shape"):
				member.call("set_team_shape", str(member.get("team_shape")))
	# Issue #521 rework (owner: "the level totally depends on the level
	# settings"): when the FIRST configured team is played by the COMPUTER,
	# its human Player figures must not stay on the field answerable to
	# the keys — swap each for a computer Npc figure (team = "player", the
	# engine's spectate staging from issue #121) dressed with the team's
	# own setup, so the side plays itself exactly like an enemy team.
	if team_controller(0) == "computer":
		_swap_hero_team_for_computer(level)
	# Issue #537 rework v3 (owner item 2): the level fields EXACTLY the
	# configured count per team — surplus dealt figures go, missing ones
	# spawn beside the team's first figure. Issue #617 rework v2: this
	# runs on EVERY set-driven start (the menu AND the direct defaults).
	if menu_driven:
		_reconcile_menu_team_sizes(level)
	# Issue #617 rework v2: the classic counts are ONE-SHOT level-start
	# parameters — consume them so the next level (a chained next_scene
	# in the same session) falls back to the configured defaults instead
	# of replaying a stale count.
	team_size = 0
	enemy_count = 0
	# Issue #688: runtime BotController injection — every computer-played
	# figure receives its RL policy controller for native ncnn inference
	# (the production deploy path; authored training/eval scenes manage
	# their own agents and are skipped).
	_inject_rl_bots(level)


## Issue #688: paths of the deployed ncnn policy — retrained on this
## controller's 54-float observation, heads emitted alphabetically with
## the argmax baked into the graph (see ActionDecode's compact layout) —
## plus its VecNormalize sidecar: without the stats the net would read
## raw, unnormalized floats.
const RL_MODEL_PARAM := "res://models/policy.ncnn.param"
const RL_MODEL_BIN := "res://models/policy.ncnn.bin"
const RL_OBS_NORM_STATS := "res://models/vecnormalize_stats.json"


## Issue #688: give every computer-played figure of the level its RL
## brain — a BotController created in code (the editor's Inspector is
## bypassed for dynamically spawned characters), pinned to the figure
## and configured for native ncnn inference, plus ONE NcnnSync in
## NCNN_INFERENCE mode to step the agents without any Python server.
## Human-played teams keep their input brain and get no controller.
static func _inject_rl_bots(level: Node) -> void:
	# Authored RL scenes (training, eval, the inference demo) instance
	# their levels UNDER an NcnnSync and manage the agent set themselves
	# — injecting here would change the training handshake's agent count
	# and fight the authored controllers. Any level under a sync is left
	# alone.
	var ancestor := level.get_parent()
	while ancestor != null:
		if ancestor is NcnnSync:
			return
		ancestor = ancestor.get_parent()
	var tree := level.get_tree()
	if tree == null:
		return
	var injected := 0
	for group in ["player_team", "enemy_team"]:
		for figure in tree.get_nodes_in_group(group):
			if figure == null or not (figure is Node2D) \
					or figure.is_queued_for_deletion() \
					or not level.is_ancestor_of(figure):
				continue
			# Only computer-played SCRIPTED figures (Npc.gd brains) are
			# policy candidates — a human figure keeps its input brain.
			if not figure.has_method("_shoot"):
				continue
			var controller := "computer"
			if figure.is_in_group("player_team"):
				controller = team_controller(0)
			elif figure.get("team_color") is Color:
				controller = team_controller_for_color(
						figure.get("team_color"))
			if controller != "computer":
				continue
			if _attach_rl_bot(figure):
				injected += 1
	if injected == 0:
		return
	# One sync drives every injected controller: NCNN_INFERENCE steps
	# the agents natively each action_repeat physics frames. Added AFTER
	# the bots so its deferred AGENT-group scan finds them all.
	var sync: NcnnSync = load("res://addons/godot_native_rl/sync.gd").new()
	sync.name = "NcnnSync"
	sync.control_mode = NcnnSync.ControlModes.NCNN_INFERENCE
	level.add_child(sync)
	DebugInfo.log("RL policy drives %d figures (ncnn inference)" % injected)


## Issue #688: attach one BotController to a computer figure and pin it
## there. The deploy properties are set BEFORE the controller enters the
## tree — its _ready loads the ncnn runner from these paths; the figure
## link is the controller's own relative path to its parent figure.
## Returns false when the deployed policy failed to load — the figure
## then keeps its scripted AI (a level must stay playable without the
## net, e.g. a broken or missing models/ pair).
static func _attach_rl_bot(figure: Node) -> bool:
	var bot = load("res://scripts/BotController.gd").new()
	bot.name = "RLBot"
	bot.control_mode = bot.ControlModes.NCNN_INFERENCE
	bot.model_param_path = RL_MODEL_PARAM
	bot.model_bin_path = RL_MODEL_BIN
	bot.obs_norm_stats_path = RL_OBS_NORM_STATS
	# A production match ENDS on its win — no framework auto reset may
	# revive the field or replay the level (BotController.auto_reset).
	bot.auto_reset = false
	figure.add_child(bot)
	var runner = bot.get("_ncnn_runner")
	if runner == null or not runner.is_model_loaded():
		# The policy did not load (missing files, an unloadable graph) —
		# drop the controller and keep the scripted brain: an RL controller
		# without a net would only idle every turn away.
		bot.queue_free()
		return false
	bot.figure_path = bot.get_path_to(figure)
	figure.set("rl_controlled", true)
	# The controller must never outlive its figure: once the figure is
	# freed, the controller's fallback resolution would latch onto (and
	# double-drive) a neighbour's figure.
	figure.tree_exited.connect(bot.queue_free)
	return true


## Issue #613 ("rework all levels"): the campaign scenes no longer
## author the player/computer split — every staged figure is a PLAIN
## Character.gd body ("just a character": a staging name, a position,
## a display name, maybe looks) and THIS pass gives it a brain from
## the team configuration, because each team may be played by the
## player or by the computer:
##   - a first-team slot (Player/Teammate*) becomes a human Player.gd
##     figure while the first team's controller is "player", and a
##     computer Npc.gd figure fighting on the player side otherwise
##     (issue #121's spectate staging — the level plays itself);
##   - an Npc* slot becomes a computer Npc.gd figure (a configured
##     team dealt onto it later may still be swapped for human
##     figures — the hot-seat flow of issue #521).
## The replacement keeps the staging NAME (the trim/deal passes and
## the tests address figures by name), the position, the display name
## and the authored team looks; the hero's shared camera follows its
## figure into a human brain, or is rescued onto the level for the
## computer to spectate (the same handover a hero swap does).
static func _dress_just_characters(level: Node) -> void:
	var staged: Array = level.get_children()
	for figure in staged:
		var brain: Script = figure.get_script()
		if brain == null \
				or brain.resource_path != "res://scripts/Character.gd":
			continue
		var slot := str(figure.name)
		# Issue #617: the uniform staging name Team<N>mate<M> decides the
		# side — Team1 stages the first team, Team2 and beyond stage the
		# enemy side. The legacy Player/Teammate*/Npc* staging keeps its
		# old split.
		var staged_slot := _staged_team_slot(slot)
		var enemy_side := (staged_slot.size() == 2 and int(staged_slot[0]) >= 2) \
				or slot.begins_with("Npc")
		var human := not enemy_side and team_controller(0) == "player"
		var dressed := CharacterBody2D.new()
		dressed.name = slot
		dressed.position = (figure as Node2D).position
		dressed.set_script(load("res://scripts/Player.gd") if human \
				else load("res://scripts/Npc.gd"))
		dressed.set("display_name", str(figure.get("display_name")))
		dressed.set("team_color", figure.get("team_color"))
		dressed.set("team_shape", str(figure.get("team_shape")))
		if human:
			_build_figure_body(dressed)
			_carry_camera(figure, dressed)
		else:
			if not enemy_side:
				dressed.set("team", "player")
			_carry_camera(figure, null)
		# Swap in place: the staging order (TurnController scans figures
		# in stable scene order) and the staging name both survive.
		var index: int = figure.get_index()
		level.remove_child(figure)
		figure.queue_free()
		level.add_child(dressed)
		level.move_child(dressed, index)
	# Issue #617: the levels no longer author a camera under a figure —
	# the default view is the level's shared camera — so make sure
	# exactly one exists, hosted by the first live figure.
	_ensure_shared_camera(level)


## Issue #617: parse the uniform staging name Team<N>mate<M>. Returns
## [team_index, member_index] (both 1-based), or an empty array when the
## name is not in the uniform format.
static func _staged_team_slot(slot: String) -> Array:
	if not slot.begins_with("Team"):
		return []
	var mate := slot.find("mate")
	if mate < 0:
		return []
	var team := slot.substr(4, mate - 4).to_int()
	var member := slot.substr(mate + 4).to_int()
	if team < 1 or member < 1:
		return []
	return [team, member]


## Issue #617: the uniform levels stage characters ONLY — no authored
## camera — and every level's default view is the shared camera. Create
## it once when none exists, hosted by the first live FIGURE: a figure
## host keeps the #280 rescue semantics (the camera survives its host's
## death by reparenting onto the level) while the GLOBAL default mode
## (#617) keeps it following nobody.
static func _ensure_shared_camera(level: Node) -> void:
	var tree := level.get_tree()
	if tree == null:
		return
	# Issue #617 rework v2: only a camera INSIDE THIS LEVEL counts — a
	# dying previous level's camera (freed with queue_free, still alive
	# in the group until the frame ends — e.g. a chained next_scene
	# transition) must not suppress the new level's own shared camera.
	for camera in tree.get_nodes_in_group("player_camera"):
		if is_instance_valid(camera) \
				and not (camera as Node).is_queued_for_deletion() \
				and level.is_ancestor_of(camera):
			return
	var host: Node2D = null
	for group in ["player_team", "enemy_team"]:
		for figure in tree.get_nodes_in_group(group):
			# Same scope as above: a figure of a DYING previous level must
			# not host the new level's camera (it — and the camera — are
			# freed at the end of the frame).
			if figure is Node2D and not figure.is_queued_for_deletion() \
					and level.is_ancestor_of(figure):
				host = figure
				break
		if host != null:
			break
	if host == null:
		return
	var camera: Camera2D = load("res://scripts/ZoomCamera.gd").new()
	camera.name = "Camera"
	camera.zoom = Vector2(0.5, 0.5)
	camera.position = host.position
	host.add_child(camera)


## Issue #613: the runtime body of a human figure — the same children
## the levels used to author (capsule body, team-tinted visual, and the
## weapon LAST so it draws in front of the body — issue #282).
static func _build_figure_body(figure: Node) -> void:
	var capsule := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 24.0
	shape.height = 57.6
	capsule.shape = shape
	capsule.name = "BodyShape"
	figure.add_child(capsule)
	var visual := ColorRect.new()
	visual.name = "BodyVisual"
	visual.offset_left = -32.0
	visual.offset_top = -32.0
	visual.offset_right = 32.0
	visual.offset_bottom = 32.0
	figure.add_child(visual)
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.set_script(load("res://scripts/Weapon.gd"))
	figure.add_child(weapon)


## Issue #613: move a camera authored under a staged body to its
## replacement. `into == null` rescues it onto the level instead — the
## computer plays the hero, so the camera must survive its body and
## keep spectating (issue #534: it stays enabled and follows the
## acting figure; reparenting drops transient groups, so the
## player_camera membership is restored by hand).
static func _carry_camera(from: Node, into: Node) -> void:
	for child in from.get_children():
		if child is Camera2D:
			if into != null:
				from.remove_child(child)
				into.add_child(child)
			else:
				child.reparent(from.get_parent())
				child.enabled = true
				child.add_to_group("player_camera")
			return


## Issue #537 rework v3: record one dealt (possibly swapped) figure for
## its configured team — the reconciliation map the size pass reads.
static func _record_dealt_figure(team_index: int, figure: Node) -> void:
	if figure == null:
		return
	if not _dealt_figures.has(team_index):
		_dealt_figures[team_index] = []
	(_dealt_figures[team_index] as Array).append(figure)


## Issue #537 rework v3: the second staged-enemy pass (Level4's
## Npc4..Npc9 and the duel levels' figures) — same deal as Npc..Npc3.
static func _apply_extra_team_staged(level: Node, npc_node: Node) -> void:
	var extra := maxi(1, teams.size() - 1)
	var dealt_team := 1 + (_dealt % extra)
	_record_dealt_figure(dealt_team, _apply_extra_team(level, npc_node, dealt_team))
	_dealt += 1


## Issue #537 rework v3 (owner item 2): trim or grow every configured
## team beyond the first to the menu's member count. Figures already
## dealt are matched through _dealt_figures (never by color — a
## per-game recolor may duplicate one); missing figures spawn beside
## the team's first live figure (any teammate when the team got none).
static func _reconcile_menu_team_sizes(level: Node) -> void:
	# The FIRST team's live set is the player-side group itself (the
	# authored hero + teammates, the spawned extras, the computer
	# figures a swap may have replaced them with); every other team's
	# set is its dealt figures.
	_reconcile_team(level, 0, _live_player_figures(level))
	for team_index in range(1, teams.size()):
		_reconcile_team(level, team_index, _tracked_figures(team_index))


## The live figures dealt to one configured team (beyond the first).
static func _tracked_figures(team_index: int) -> Array:
	var live: Array = []
	for figure in _dealt_figures.get(team_index, []):
		if figure != null and is_instance_valid(figure) \
				and not (figure as Node).is_queued_for_deletion():
			live.append(figure)
	return live


## The player side's live figures — the first team's set.
static func _live_player_figures(level: Node) -> Array:
	var live: Array = []
	for figure in level.get_tree().get_nodes_in_group("player_team"):
		if figure is Node2D and not figure.is_queued_for_deletion():
			live.append(figure)
	return live


## Trim or grow ONE team to its configured count: surplus figures go
## (the last dealt first), missing ones spawn beside the team's first
## live figure (any figure when the team got none at all).
## Issue #617 rework v2: a team that got NO staged figures spawns its
## row where nobody stands — the old anchor (the first live figure)
## dropped the new team ON TOP of another team's formation, and the
## overlapping bodies shoved each other apart mid-fight.
static func _reconcile_team(level: Node, team_index: int, live: Array) -> void:
	var team: Dictionary = teams[team_index]
	var wanted: int = (team["names"] as Array).size()
	while live.size() > wanted:
		(live.pop_back() as Node).queue_free()
	if live.size() >= wanted:
		return
	var anchor := Vector2(240.0, 0.0)
	if not live.is_empty() and live[0] is Node2D:
		anchor = (live[0] as Node2D).position
	else:
		var any_figure := _first_live_figure(level)
		if any_figure != null:
			anchor = _free_spawn_spot(level, any_figure.position)
	var row_base := anchor + Vector2(56.0, 0.0) if not live.is_empty() \
			else _free_spawn_spot(level, anchor + Vector2(56.0, 0.0))
	var index := 0
	while live.size() < wanted:
		var member_name := str(team["names"][live.size()])
		var at := row_base + Vector2(56.0 * index, 0.0)
		index += 1
		if team_index == 0:
			if team_controller(0) == "player":
				live.append(_spawn_player_figure(level, at, team, member_name))
			else:
				_spawn_computer_figure(level, at, team, member_name)
				live.append(_live_player_figures(level).back())
		elif team_controller(team_index) == "player":
			live.append(_spawn_human_figure(level, at, team, member_name))
		else:
			live.append(_spawn_enemy_figure(level, at, team, member_name))


## Issue #617 rework v2: the first FULLY CLEAR spot at or right of
## `at` — at least ~70 px away in BOTH axes from every live figure of
## the level (a capsule body is 48 px wide; 70 keeps formations from
## interpenetrating). The scan is bounded so a crowded level simply
## takes the last candidate.
static func _free_spawn_spot(level: Node, at: Vector2) -> Vector2:
	var figures: Array = []
	for group in ["player_team", "enemy_team"]:
		for figure in level.get_tree().get_nodes_in_group(group):
			if figure is Node2D and not figure.is_queued_for_deletion() \
					and level.is_ancestor_of(figure):
				figures.append(figure)
	var spot := at
	for _i in 40:
		var clear := true
		for figure in figures:
			var other: Vector2 = (figure as Node2D).global_position
			if absf(other.x - spot.x) < 70.0 \
					and absf(other.y - spot.y) < 70.0:
				clear = false
				break
		if clear:
			return spot
		spot += Vector2(56.0, 0.0)
	return spot


## Any live figure of the level (player side first) — the spawn anchor
## fallback for a team the staged cast could not host at all.
static func _first_live_figure(level: Node) -> Node2D:
	for group in ["player_team", "enemy_team"]:
		for figure in level.get_tree().get_nodes_in_group(group):
			if figure is Node2D and not figure.is_queued_for_deletion():
				return figure
	return null


## Issue #537 rework v3 (owner item 2): the menu grids go to 64
## teammates while the staged levels host three player figures — the
## rest spawn beside the hero in a spaced row (the random spawn
## regimes scatter them afterwards; the designer regime keeps the row).
static func _spawn_missing_player_figures(level: Node, hero_count: int) -> void:
	var team: Dictionary = teams[0]
	var names: Array = team["names"]
	var hero := level.get_node_or_null(NodePath("Team1mate1"))
	if hero == null:
		hero = level.get_node_or_null(NodePath("Player"))
	var anchor: Vector2 = hero.position if hero is Node2D else Vector2(200.0, 0.0)
	# From the LIVE staged count (re-applying to a dressed level must not
	# duplicate the extras — the reconciliation owns the surplus).
	var staged := _live_player_figures(level).size()
	# Issue #537 rework v4: from the ACTUAL staged count — the old
	# maxi(3, staged) skipped members on levels staging fewer than
	# three player figures (the duel casts), fielding one short. A
	# classic team_size beyond the configured name list can only field
	# as many figures as the set names.
	var target := mini(hero_count, names.size())
	for i in range(staged, target):
		_spawn_player_figure(level, anchor + Vector2(56.0 * (i - staged + 1), 0.0),
				team, str(names[i]))


## Issue #537 rework v3: build a human-controlled figure fighting on
## the PLAYER side — the same staged body _spawn_human_figure builds,
## keeping the classic player side (team_side "player").
static func _spawn_player_figure(level: Node, at: Vector2,
		team: Dictionary, member_name: String) -> Node:
	var figure := CharacterBody2D.new()
	figure.set_script(load("res://scripts/Player.gd"))
	figure.position = at
	figure.set("team_color", team["color"])
	figure.set("team_shape", str(team["shape"]))
	figure.set("display_name", member_name)
	var capsule := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 24.0
	shape.height = 57.6
	capsule.shape = shape
	capsule.name = "BodyShape"
	figure.add_child(capsule)
	var visual := ColorRect.new()
	visual.name = "BodyVisual"
	visual.offset_left = -32.0
	visual.offset_top = -32.0
	visual.offset_right = 32.0
	visual.offset_bottom = 32.0
	figure.add_child(visual)
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.set_script(load("res://scripts/Weapon.gd"))
	figure.add_child(weapon)
	level.add_child(figure)
	return figure


## Issue #537 rework v3: build a COMPUTER-played enemy figure (Npc.gd,
## team "enemy" by default) — the mirror of _spawn_computer_figure.
static func _spawn_enemy_figure(level: Node, at: Vector2,
		team: Dictionary, member_name: String) -> Node:
	var figure := CharacterBody2D.new()
	figure.set_script(load("res://scripts/Npc.gd"))
	figure.position = at
	figure.set("team_color", team["color"])
	figure.set("team_shape", str(team["shape"]))
	figure.set("display_name", member_name)
	var skill := clampi(int(team["skill"]), 0, 10)
	figure.set("difficulty", 0 if skill <= 3 else (1 if skill <= 7 else 2))
	figure.set("ai_friendly_fire", clampi(int(team["friendly_fire"]), 0, 10))
	level.add_child(figure)
	return figure


## Issue #521 rework: the level must follow the team settings TOTALLY —
## a computer-played FIRST team (the classic hero side) is swapped figure
## by figure for computer figures. The swap runs AFTER the customise pass
## above, so each replacement carries over the name the pass assigned;
## the shared camera a figure hosts (the hero usually hosts it) is
## rescued to the level first — the view must survive its host's swap.
static func _swap_hero_team_for_computer(level: Node) -> void:
	var team: Dictionary = teams[0]
	for figure in level.get_tree().get_nodes_in_group("player_team"):
		if figure == null or figure.is_queued_for_deletion():
			continue
		# Only HUMAN figures (Player.gd) are swapped — a duel level may
		# already stage computer figures (Npc.gd, issue #121) on the player
		# side; they keep fighting exactly as authored.
		if not figure.has_method("set_controlled"):
			continue
		var at: Vector2 = figure.position if figure is Node2D else Vector2.ZERO
		for child in figure.get_children():
			if child is Camera2D and child.is_in_group("player_camera"):
				child.reparent(level)
				child.enabled = true
				# reparent() = remove + add: exiting the tree drops the
				# transient group, so the shared-camera group membership
				# must be restored — Player.set_controlled and the
				# game-over camera sweep both find cameras by this group.
				child.add_to_group("player_camera")
				break
		var member_name := str(figure.get("display_name"))
		_spawn_computer_figure(level, at, team, member_name)
		figure.queue_free()


## Issue #521 rework: build a COMPUTER-played figure (Npc.gd) fighting on
## the PLAYER side (team = "player") — the mirror of
## _spawn_human_figure. The AI parameters come from the team
## configuration, exactly like an enemy-side figure.
static func _spawn_computer_figure(level: Node, at: Vector2,
		team: Dictionary, member_name: String) -> void:
	var figure := CharacterBody2D.new()
	figure.set_script(load("res://scripts/Npc.gd"))
	figure.position = at
	figure.set("team", "player")
	# Issue #169/#617: the looks the swap must carry — the team menu set
	# when it drove the sizes, the classic customisation fields the human
	# figure wore otherwise (this swap replaces apply_team_setup figures).
	if menu_team_sizes:
		figure.set("team_color", team["color"])
		figure.set("team_shape", str(team["shape"]))
	else:
		figure.set("team_color", team_color)
		figure.set("team_shape", team_shape)
	figure.set("display_name", member_name)
	var skill := clampi(int(team["skill"]), 0, 10)
	figure.set("difficulty", 0 if skill <= 3 else (1 if skill <= 7 else 2))
	figure.set("ai_friendly_fire", clampi(int(team["friendly_fire"]), 0, 10))
	level.add_child(figure)


## Issue #521: dress (or replace) one enemy FIGURE for configured team
## `team_index` — its color/shape/names/AI parameters — and, when that
## team is played by a human, swap the Npc figure for an identical
## Player.gd figure staged on the enemy side, so the human drives it
## with the usual controls during the team's turns (hot-seat).
static var _dealt := 0
## Issue #521: figures already dealt to each configured team (index ->
## count) — name assignment uses the DEAL ORDER, never the colors on the
## field (a not-yet-recolorized figure still wears its default pink).
static var _dealt_counts := {}
## Issue #537 rework v3 (owner item 2): the live figures dealt to each
## configured team (index -> Array of nodes) — the size reconciliation
## trims or grows each team to the menu's count through this map, never
## through colors (two teams may share a color after a per-game recolor).
static var _dealt_figures := {}

## Issue #537 rework v3 (owner item 2): the level menu's per-team member
## grids drive the level — true from the moment the menu starts one.
## apply() then takes every team's SIZE from `teams` (the grids go to
## 64), spawns figures beyond the staged cast and frees the surplus;
## the classic capped fields (team_size/enemy_count) stay the source
## when the level was started with an EXPLICIT classic count (tests,
## tools). Issue #617 rework v2: a start with NO classic count (direct
## runs) is set-driven too — the defaults field 3 teams × 2 mates.
static var menu_team_sizes := false


static func _apply_extra_team(level: Node, npc: Node, team_index: int) -> Node:
	var team: Dictionary = teams[team_index]
	var member_names: Array = team["names"]
	var member_index := int(_dealt_counts.get(team_index, 0))
	_dealt_counts[team_index] = member_index + 1
	if team_controller(team_index) == "player" and npc.has_method("_shoot"):
		# Human team: replace the computer figure with a Player figure at
		# the same spot. The freed Npc leaves the tree at the end of the
		# frame, so the swap cannot wedge anything mid-apply. Issue #537
		# rework v3: the swap RETURNS the live figure so the size
		# reconciliation can track it.
		var at: Vector2 = npc.get("position") if npc is Node2D else Vector2.ZERO
		var swapped := _spawn_human_figure(level, at, team,
			str(member_names[mini(member_index, member_names.size() - 1)]))
		npc.queue_free()
		return swapped
	if npc.get("difficulty") != null:
		var skill := clampi(int(team["skill"]), 0, 10)
		npc.set("difficulty", 0 if skill <= 3 else (1 if skill <= 7 else 2))
	if npc.get("ai_friendly_fire") != null:
		npc.set("ai_friendly_fire", clampi(int(team["friendly_fire"]), 0, 10))
	if npc.get("team_color") != null:
		npc.set("team_color", team["color"])
	if npc.has_method("_apply_team_color"):
		npc.call("_apply_team_color")
	if npc.get("display_name") != null:
		npc.set("display_name",
			str(member_names[mini(member_index, member_names.size() - 1)]))
	if npc.has_method("set_display_name"):
		npc.call("set_display_name",
			str(member_names[mini(member_index, member_names.size() - 1)]))
	if npc.has_method("set_team_shape"):
		npc.call("set_team_shape", str(team["shape"]))
	return npc


## Issue #521: build a human-controlled figure (Player.gd) fighting on
## the ENEMY side — the body visual, collision capsule and Weapon node
## the level scenes author by hand, created in code so apply() can
## stage it where the computer figure stood.
static func _spawn_human_figure(level: Node, at: Vector2,
		team: Dictionary, member_name: String) -> Node:
	var figure := CharacterBody2D.new()
	figure.set_script(load("res://scripts/Player.gd"))
	figure.position = at
	figure.set("team_color", team["color"])
	figure.set("team_shape", str(team["shape"]))
	figure.set("display_name", member_name)
	figure.set("team_side", "enemy")
	var capsule := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 24.0
	shape.height = 57.6
	capsule.shape = shape
	capsule.name = "BodyShape"
	figure.add_child(capsule)
	var visual := ColorRect.new()
	visual.name = "BodyVisual"
	visual.offset_left = -32.0
	visual.offset_top = -32.0
	visual.offset_right = 32.0
	visual.offset_bottom = 32.0
	figure.add_child(visual)
	var weapon := Node2D.new()
	weapon.name = "Weapon"
	weapon.set_script(load("res://scripts/Weapon.gd"))
	figure.add_child(weapon)
	level.add_child(figure)
	return figure
