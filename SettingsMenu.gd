extends Control
## Settings menu (issue #175).
##
## Hosts the settings entries; the team customisation ("My team") moved here
## from the main menu. Issue #180: the entry is renamed to "Teams" — the
## team menu configures the player's team AND the computer team's AI
## behavior. Issue #252: the DEBUG MODE switch (on by default) gates the
## OSD, the per-figure debug visuals and the action log. Back returns to
## the main menu.
## Issue #304: the SAME screen is reused inside the in-game pause overlay
## — with in_game set, navigation happens inside the overlay (the running
## level must survive) instead of changing the scene.

## Emitted instead of the scene change when Back/Esc is pressed while the
## menu runs inside the in-game overlay (issue #304).
signal back_requested

## True while this screen is instanced into the in-game pause overlay
## (issue #304); false when it runs as the standalone main-menu screen.
var in_game := false

## The submenu (Teams/Hotkeys) currently open on top of this screen,
## in overlay mode only.
var _submenu: Control = null

## The shadow the in-game overlay casts over the paused game — the
## same color/alpha the pause panel uses (InGameMenu), so the dim is
## identical on every screen of the overlay (issue #304).
const SHADOW_COLOR := Color(0.05, 0.03, 0.1, 0.75)

@onready var _team_button: Button = %TeamButton
@onready var _hotkeys_button: Button = %HotkeysButton
@onready var _debug_check: CheckButton = %DebugCheck
@onready var _gravity_field_check: CheckButton = %GravityFieldCheck
@onready var _back_button: Button = %BackButton
## Issue #348: the screen follows the main-menu template (MenuBackground
## artwork + MenuTheme); the layout container is the toggleable content.
@onready var _layout: Control = %Layout
@onready var _background: Control = $Background
## The dim shown INSTEAD of the background artwork while the game stays
## visible behind this screen in overlay mode (issue #304).
@onready var _shadow: ColorRect = $Shadow
@onready var _footer: Control = $Footer


func _ready() -> void:
	# Issue #304 (rework, #348 template): inside the pause overlay the game
	# stays visible behind the shared shadow dim while the template's
	# background artwork and footer are hidden.
	if in_game:
		_background.visible = false
		_shadow.color = SHADOW_COLOR
		_shadow.visible = true
		_footer.visible = false
	_team_button.pressed.connect(_on_team_pressed)
	# Issue #294: the hotkeys screen — rebindable, persisted key bindings.
	_hotkeys_button.pressed.connect(_on_hotkeys_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	# Issue #252: the check shows the persisted state; every flip is saved
	# at once so the choice survives a restart.
	_debug_check.button_pressed = GameConfig.debug_mode
	_debug_check.toggled.connect(_on_debug_toggled)
	# Issue #290: the gravity vector field switch, right below the debug
	# mode — same persist-on-flip behaviour.
	_gravity_field_check.button_pressed = GameConfig.debug_gravity_field
	_gravity_field_check.toggled.connect(_on_gravity_field_toggled)
	_team_button.grab_focus()


func _on_team_pressed() -> void:
	# Issue #304: inside the pause overlay the submenu opens on top of
	# this screen instead of replacing the scene (which would drop the
	# running level).
	if _open_submenu("res://TeamMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://TeamMenu.tscn")


## Issue #294: open the hotkeys settings screen.
func _on_hotkeys_pressed() -> void:
	if _open_submenu("res://HotkeysMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://HotkeysMenu.tscn")


## Issue #304: in overlay mode the submenu is instanced full-screen on
## top of this screen and reports back through back_requested; this
## screen stays alive underneath. Returns false when the caller should
## fall back to the standalone scene change.
func _open_submenu(path: String) -> bool:
	if not in_game:
		return false
	_submenu = (load(path) as PackedScene).instantiate()
	_submenu.in_game = true
	_submenu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_submenu.back_requested.connect(_on_submenu_closed)
	add_child(_submenu)
	_layout.visible = false
	# The submenu casts its own shadow over the game — hide this screen's
	# one so the dim is not doubled (issue #304).
	_shadow.visible = false
	return true


## The submenu was closed (Back/Esc) — drop it and show this screen again.
func _on_submenu_closed() -> void:
	if _submenu == null:
		return
	_submenu.queue_free()
	_submenu = null
	_layout.visible = true
	_shadow.visible = true
	_team_button.grab_focus()


## Issue #252: flip and persist the debug mode. Levels read the flag when
## they build their figures, so the change applies from the next level on
## (the settings menu sits in the main menu, never over a running game).
func _on_debug_toggled(pressed: bool) -> void:
	GameConfig.debug_mode = pressed
	GameConfig.save_settings()


## Issue #290: flip and persist the gravity vector field switch; the
## camera of the NEXT level reads it when it builds the overlay.
func _on_gravity_field_toggled(pressed: bool) -> void:
	GameConfig.debug_gravity_field = pressed
	GameConfig.save_settings()


func _on_back_pressed() -> void:
	# Issue #304: inside the pause overlay Back returns to the pause
	# panel (the overlay host frees this screen); the standalone screen
	# still leaves for the main menu.
	if in_game:
		back_requested.emit()
		return
	get_tree().change_scene_to_file("res://Main.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the main menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
