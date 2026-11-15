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
static var member_names: Array[String] = ["Player 1", "Player 2", "Player 3"]

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

## Issue #537: the default squad size of a fresh team — 3 characters
## fill the default 1x4 grid leaving one free "+" spot.
const DEFAULT_TEAM_MEMBERS := 3

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
## Issue #572: a third default team joins the set — RED STARS speaking
## Russian (the TeamMenu palette's red, so a hand-made red matches).
## Issue #571: a fourth default team joins the set — WHITE, almost
## transparent TRIANGLES speaking French (the alpha carries the
## transparency straight into the figure bodies).
static func default_teams() -> Array:
	var first_names: Array[String] = []
	for member_name in member_names:
		first_names.append(member_name)
	var second_names: Array[String] = []
	for i in range(1, DEFAULT_TEAM_MEMBERS + 1):
		second_names.append("Member %d" % i)
	var third_names: Array[String] = []
	for i in range(1, DEFAULT_TEAM_MEMBERS + 1):
		third_names.append("Member %d" % i)
	var fourth_names: Array[String] = []
	for i in range(1, DEFAULT_TEAM_MEMBERS + 1):
		fourth_names.append("Member %d" % i)
	return [
		{
			"label": "Team 1", "color": team_color,
			"shape": team_shape, "names": first_names,
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": DEFAULT_LANGUAGE,
			"controller": "player",
		},
		{
			"label": "Team 2", "color": Color(0.75, 0.2, 0.45, 1),
			"shape": "circle",
			"names": second_names,
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": DEFAULT_LANGUAGE,
			"controller": "computer",
		},
		{
			"label": "Team 3", "color": Color(0.9, 0.3, 0.3, 1),
			"shape": "star",
			"names": third_names,
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": "Russian",
			"controller": "computer",
		},
		{
			"label": "Team 4", "color": Color(1, 1, 1, 0.25),
			"shape": "triangle",
			"names": fourth_names,
			"skill": ai_skill, "friendly_fire": ai_friendly_fire,
			"language": "French",
			"controller": "computer",
		},
	]


## Issue #521: who plays a team — "player" (a human, hot-seat on this
## device) or "computer" (the AI). The stored set may predate the key
## (older team.cfg), so a missing value defaults by SLOT: the first team
## is the classic human hero team, every other team plays the computer.
static func team_controller(index: int) -> String:
	# Issue #521 rework: with NO team set at all (tests, a fresh boot
	# before the team menu or apply() ever loaded one) the CLASSIC
	# defaults hold — the hero team is human, every other slot computer.
	if teams.is_empty():
		return "player" if index == 0 else "computer"
	if index < 0 or index >= teams.size():
		return "computer"
	var controller := str(teams[index].get("controller", ""))
	if controller == "player" or controller == "computer":
		return controller
	return "player" if index == 0 else "computer"


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
static func load_teams() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) == OK and cfg.has_section_key("teams", "set"):
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
			controller = "player" if out.is_empty() else "computer"
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
	if menu_team_sizes and not teams.is_empty():
		hero_count = (teams[0]["names"] as Array).size()
	elif team_size <= 0 and not teams.is_empty():
		hero_count = (teams[0]["names"] as Array).size()
	var teammates: Array[String] = ["Teammate1", "Teammate2"]
	for i in teammates.size():
		if i + 1 >= hero_count:
			var member := level.get_node_or_null(NodePath(teammates[i]))
			if member != null:
				member.queue_free()
	# Issue #537 rework v4: the gate stays > 3 — beyond the classic trio
	# the configured count spawns extras; a team of at most three fields
	# only the staged cast (the #521 swap stays 1:1 with the staging).
	if hero_count > 3:
		_spawn_missing_player_figures(level, hero_count)
	# Trim the enemy team: the scenes place at most Npc..Npc3.
	var npcs: Array[String] = ["Npc", "Npc2", "Npc3"]
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
	# Issue #226: NPCs staged for the player side (duel levels,
	# team = "player") keep taking teams[0]'s looks.
	for i in npcs.size():
		var npc := level.get_node_or_null(NodePath(npcs[i]))
		if npc == null:
			continue
		if enemy_count > 0 and i >= enemy_count and not menu_team_sizes:
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
		var dealt_team := 1 + (_dealt % extra)
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
			if menu_team_sizes else member_names
	for member in live_members:
		if member.get("display_name") != null:
			var idx := live_members.find(member)
			member.set("display_name",
					str(hero_names[mini(idx, hero_names.size() - 1)]))
		if member.has_method("apply_team_setup"):
			member.call("apply_team_setup")
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
	# spawn beside the team's first figure.
	if menu_team_sizes:
		_reconcile_menu_team_sizes(level)


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
			anchor = any_figure.position
	var spawn_offset := 1
	while live.size() < wanted:
		var member_name := str(team["names"][live.size()])
		var at := anchor + Vector2(56.0 * spawn_offset, 0.0)
		spawn_offset += 1
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
	var hero := level.get_node_or_null(NodePath("Player"))
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
	figure.set("team_color", team["color"])
	figure.set("team_shape", str(team["shape"]))
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
## when the level was NOT started from the menu (tests, direct runs).
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
