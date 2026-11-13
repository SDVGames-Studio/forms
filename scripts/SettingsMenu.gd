extends Control
## Settings menu (issue #175; docs/ui/main_menu.md §6).
##
## Hosts the settings categories; the team customisation ("My team")
## moved here from the main menu. Issue #180: the entry is renamed to
## "Teams Customization" — the team menu configures the player's team
## AND the computer team's AI behavior. Issue #294: the hotkeys screen
## is the CONTROLS category. Main-menu spec M2 (owner decision Q1,
## 2026-11-06): the Debug Mode and Gravity Field switches live under
## their own DEBUG category screen (DebugMenu) instead of on this root.
## Milestone M3 (2026-11-12): the GRAPHICS category (spec §6.3) opens
## GraphicsMenu — hidden on touch devices (owner decision Q2: display
## settings are not meaningful there). Issue #472: the AUDIO category
## opens AudioMenu (one volume slider per bus: Master/Music/SFX) —
## audio settings matter on EVERY device, so the button stays visible
## on touch devices too.
## Back returns to the main menu.
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
@onready var _graphics_button: Button = %GraphicsButton
@onready var _audio_button: Button = %AudioButton
@onready var _debug_button: Button = %DebugButton
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
	# Main-menu spec §6.3 (M3): the graphics screen. Owner decision Q2:
	# hidden on touch devices — display settings are not meaningful there
	# (the button stays for desktop; hiding, not disabling, per spec §6.3
	# "only expose settings that can actually be applied").
	if GameConfig.is_touch_device():
		_graphics_button.visible = false
	_graphics_button.pressed.connect(_on_graphics_pressed)
	# Issue #472: the audio screen — visible on every device (audio
	# settings are as meaningful on touch devices as on desktop).
	_audio_button.pressed.connect(_on_audio_pressed)
	# Owner decision Q1: the debug switches live under their own category.
	_debug_button.pressed.connect(_on_debug_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_team_button.grab_focus()


func _on_team_pressed() -> void:
	# Issue #304: inside the pause overlay the submenu opens on top of
	# this screen instead of replacing the scene (which would drop the
	# running level).
	if _open_submenu("res://scenes/menus/TeamMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://scenes/menus/TeamMenu.tscn")


## Issue #294: open the hotkeys settings screen.
func _on_hotkeys_pressed() -> void:
	if _open_submenu("res://scenes/menus/HotkeysMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://scenes/menus/HotkeysMenu.tscn")


## Main-menu spec §6.3 (M3): open the graphics settings screen.
func _on_graphics_pressed() -> void:
	if _open_submenu("res://scenes/menus/GraphicsMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://scenes/menus/GraphicsMenu.tscn")


## Issue #472: open the audio settings screen.
func _on_audio_pressed() -> void:
	if _open_submenu("res://scenes/menus/AudioMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://scenes/menus/AudioMenu.tscn")


## Owner decision Q1 (2026-11-06): open the debug settings screen — the
## Debug Mode and Gravity Field switches moved under this category.
func _on_debug_pressed() -> void:
	if _open_submenu("res://scenes/menus/DebugMenu.tscn"):
		return
	get_tree().change_scene_to_file("res://scenes/menus/DebugMenu.tscn")


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


func _on_back_pressed() -> void:
	# Issue #304: inside the pause overlay Back returns to the pause
	# panel (the overlay host frees this screen); the standalone screen
	# still leaves for the main menu.
	if in_game:
		back_requested.emit()
		return
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the main menu.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
