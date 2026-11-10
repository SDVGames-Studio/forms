extends Control
## Hotkeys settings screen (issue #294).
##
## One row per gameplay action: a label and a button showing the key the
## action answers to. Pressing a row's button starts a rebind ("Press a
## key…"): the NEXT key press becomes that action's only binding — Esc
## cancels. Bindings are physical key positions (layout-independent) and
## are persisted at once via GameConfig, so they survive a restart. The
## authored project defaults may list alternates (move_left = A or Left);
## a rebind replaces them with the single chosen key, and "Reset to
## Defaults" brings the authored set back. Back returns to the settings
## menu.

## Human-readable label per action (GameConfig.HOTKEY_ACTIONS is the
## display order; every action there must have a label here).
const ACTION_LABELS: Dictionary = {
	"move_left": "Move Left",
	"move_right": "Move Right",
	"jump": "Jump",
	"view_up": "Aim Up",
	"view_down": "Aim Down",
	"shoot": "Shoot",
	"camera_switch": "Camera Type",
	"switch_next": "Next Figure",
	"switch_prev": "Previous Figure",
	"weapon_1": "Weapon 1",
	"weapon_2": "Weapon 2",
	"weapon_3": "Weapon 3",
	"weapon_4": "Weapon 4",
	"weapon_5": "Weapon 5",
	"tool_1": "Tool 1",
	"tool_2": "Tool 2",
	"tool_3": "Tool 3",
	"tool_4": "Tool 4",
}

const LISTEN_TEXT := "Press a key…"
const NO_KEY := "—"

## Emitted instead of the scene change when Back/Esc is pressed while
## the menu runs inside the in-game settings overlay (issue #304).
signal back_requested

## True while this menu is instanced into the in-game settings overlay
## (issue #304); Back then returns to that overlay instead of changing
## the scene, which would drop the running level.
var in_game := false

## The action whose button is waiting for the next key press ("" = none).
var _listening := ""
## action name -> its key Button (so every row can be refreshed).
var _key_buttons: Dictionary = {}

@onready var _rows: VBoxContainer = %Rows
@onready var _reset_button: Button = %ResetButton
@onready var _back_button: Button = %BackButton
## Issue #348: the screen follows the main-menu template (MenuBackground
## artwork + MenuTheme); in overlay mode the artwork and footer hide and
## the shared shadow dim shows the paused game through instead.
@onready var _background: Control = $Background
@onready var _shadow: ColorRect = $Shadow
@onready var _footer: Control = $Footer


func _ready() -> void:
	# Issue #304 (rework, #348 template): when opened on top of the in-game
	# settings overlay the game stays visible behind the shared shadow dim
	# — the same dim the pause panel casts — instead of the standalone
	# background artwork.
	if in_game:
		_background.visible = false
		_shadow.visible = true
		_footer.visible = false
	# The main menu snapshots the authored defaults at startup; do it here
	# too, so the screen also works when it is the first thing that runs
	# (e.g. in a test). It is a no-op once the snapshot exists.
	GameConfig.capture_hotkey_defaults()
	for action in GameConfig.HOTKEY_ACTIONS:
		_build_row(action, str(ACTION_LABELS.get(action, action)))
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.grab_focus()


func _build_row(action: String, label: String) -> void:
	var row := HBoxContainer.new()
	row.name = StringName(label.replace(" ", ""))
	row.add_theme_constant_override("separation", 16)
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	var key_button := Button.new()
	key_button.name = "Key"
	key_button.text = action_key(action)
	key_button.custom_minimum_size = Vector2(180, 48)
	key_button.add_theme_font_size_override("font_size", 24)
	# Issue #294: start the rebind. The lambda captures this action's name.
	key_button.pressed.connect(_start_listen.bind(action))
	_key_buttons[action] = key_button
	row.add_child(name_label)
	row.add_child(key_button)
	_rows.add_child(row)


## The key an action currently answers to: the saved override first, then
## the first authored InputMap event (the menu shows ONE key per action).
func action_key(action: String) -> String:
	if GameConfig.hotkeys.has(action):
		return key_name(int(GameConfig.hotkeys[action]))
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				var code := key.physical_keycode \
						if key.physical_keycode != 0 else key.keycode
				if code != 0:
					return key_name(code)
	return NO_KEY


## Physical keycode -> display string ("A", "Space", "Left", …).
static func key_name(code: int) -> String:
	var text := OS.get_keycode_string(code as Key)
	return text if not text.is_empty() else "Key %d" % code


func _start_listen(action: String) -> void:
	_stop_listen()
	_listening = action
	(_key_buttons[action] as Button).text = LISTEN_TEXT


func _stop_listen() -> void:
	if _listening != "" and _key_buttons.has(_listening):
		(_key_buttons[_listening] as Button).text = action_key(_listening)
	_listening = ""


func _refresh_all() -> void:
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = action_key(action)


## While a rebind is pending, the next key press (any key but Esc) is the
## new binding. _input runs BEFORE the UI, and the event is marked
## handled, so the pressed key never leaks into the focused button (a
## Space press must rebind, not activate the GUI).
func _input(event: InputEvent) -> void:
	# Issue #303: Escape is always the cancel button — while a rebinding
	# listen is running it aborts the listen; otherwise it acts as Back.
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _listening != "":
				_stop_listen()
			else:
				_on_back_pressed()
			return
	if _listening == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		get_viewport().set_input_as_handled()
		if key.physical_keycode != KEY_NONE:
			GameConfig.set_hotkey(_listening, key.physical_keycode)
			_stop_listen()


func _on_reset_pressed() -> void:
	_listening = ""
	GameConfig.reset_hotkeys()
	_refresh_all()


func _on_back_pressed() -> void:
	# Issue #304: in overlay mode the host settings screen listens and
	# frees this menu; standalone still changes the scene.
	if in_game:
		back_requested.emit()
		return
	get_tree().change_scene_to_file("res://SettingsMenu.tscn")
