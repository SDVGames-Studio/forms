extends Control
## Settings menu (issue #175).
##
## Hosts the settings entries; the team customisation ("My team") moved here
## from the main menu. Issue #180: the entry is renamed to "Teams" — the
## team menu configures the player's team AND the computer team's AI
## behavior. Issue #252: the DEBUG MODE switch (on by default) gates the
## OSD, the per-figure debug visuals and the action log. Back returns to
## the main menu.

@onready var _team_button: Button = %TeamButton
@onready var _hotkeys_button: Button = %HotkeysButton
@onready var _debug_check: CheckButton = %DebugCheck
@onready var _gravity_field_check: CheckButton = %GravityFieldCheck
@onready var _back_button: Button = %BackButton


func _ready() -> void:
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
	get_tree().change_scene_to_file("res://TeamMenu.tscn")


## Issue #294: open the hotkeys settings screen.
func _on_hotkeys_pressed() -> void:
	get_tree().change_scene_to_file("res://HotkeysMenu.tscn")


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
	get_tree().change_scene_to_file("res://Main.tscn")
