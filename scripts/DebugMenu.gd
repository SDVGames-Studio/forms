extends Control
## Debug settings screen (docs/ui/main_menu.md §6 + owner decision Q1,
## 2026-11-06): the Debug Mode and Gravity Field switches live under
## their own DEBUG category on the Settings screen instead of on the
## Settings root.
##
## Issue #252: the DEBUG MODE switch (on by default) gates the OSD, the
## per-figure debug visuals and the action log. Issue #290: the gravity
## vector field switch. Both persist on every flip (user://settings.cfg
## via GameConfig) so the choice survives a restart.
##
## Issue #304: the SAME screen is reused inside the in-game pause
## overlay — with in_game set, navigation happens inside the overlay
## (the running level must survive) instead of changing the scene.
## Issue #348: the screen follows the main-menu template
## (MenuBackground artwork + MenuTheme).

## Emitted instead of the scene change when Back/Esc is pressed while the
## menu runs inside the in-game overlay (issue #304).
signal back_requested

## True while this screen is instanced into the in-game pause overlay
## (issue #304); false when it runs as the standalone settings submenu.
var in_game := false

## The shadow the in-game overlay casts over the paused game — the
## same color/alpha the pause panel uses (InGameMenu), so the dim is
## identical on every screen of the overlay (issue #304).
const SHADOW_COLOR := Color(0.05, 0.03, 0.1, 0.75)

@onready var _debug_check: CheckButton = %DebugCheck
@onready var _gravity_field_check: CheckButton = %GravityFieldCheck
@onready var _back_button: Button = %BackButton
## Issue #348: the layout container is the toggleable content.
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
	_back_button.pressed.connect(_on_back_pressed)
	# Issue #252/#290: the checks show the persisted state; every flip is
	# saved at once so the choice survives a restart.
	_debug_check.button_pressed = GameConfig.debug_mode
	_debug_check.toggled.connect(_on_debug_toggled)
	_gravity_field_check.button_pressed = GameConfig.debug_gravity_field
	_gravity_field_check.toggled.connect(_on_gravity_field_toggled)
	_debug_check.grab_focus()


## Issue #252: flip and persist the debug mode. Levels read the flag when
## they build their figures, so the change applies from the next level on.
func _on_debug_toggled(pressed: bool) -> void:
	GameConfig.debug_mode = pressed
	GameConfig.save_settings()


## Issue #290: flip and persist the gravity vector field switch; the
## camera of the NEXT level reads it when it builds the overlay.
func _on_gravity_field_toggled(pressed: bool) -> void:
	GameConfig.debug_gravity_field = pressed
	GameConfig.save_settings()


func _on_back_pressed() -> void:
	# Issue #304: inside the pause overlay Back returns to the settings
	# screen (the overlay host frees this screen); the standalone screen
	# leaves for the settings screen (docs/ui/main_menu.md §6.4).
	if in_game:
		back_requested.emit()
		return
	get_tree().change_scene_to_file("res://scenes/menus/SettingsMenu.tscn")


## Issue #303: Escape is the cancel button in every menu — it acts as
## Back here, returning to the settings screen.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()
