extends Control
## Audio settings screen (issue #472; docs/ui/main_menu.md §6.6).
##
## One volume slider per audio bus of the project's default bus layout —
## MASTER, MUSIC, SFX (MusicManager rides Music, the sound effects ride
## SFX). Every change applies immediately (AudioServer through
## GameConfig.apply_audio_settings) and persists at once (user://
## settings.cfg via GameConfig) — the spec §6.3 rules (only expose
## settings that can actually be applied; apply immediately where safe)
## carry over to audio. 0% is silence: linear 0 maps to the -80 dB
## floor, since linear_to_db(0) is -INF.
##
## Issue #304: the SAME screen runs inside the in-game pause overlay
## (in_game) — navigation stays in the overlay, the game stays visible
## behind the shared shadow dim. Issue #348: main-menu template
## (MenuBackground artwork + MenuTheme).

## Emitted instead of the scene change when Back/Esc is pressed while the
## screen runs inside the in-game pause overlay (issue #304).
signal back_requested

## True while this screen is instanced into the in-game pause overlay
## (issue #304); false when it runs as the standalone settings submenu.
var in_game := false

## The shadow the in-game overlay casts over the paused game — the
## same color/alpha the pause panel uses, so the dim is identical on
## every screen of the overlay (issue #304).
const SHADOW_COLOR := Color(0.05, 0.03, 0.1, 0.75)

@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _sfx_value: Label = %SfxValue
@onready var _back_button: Button = %BackButton
## Issue #348: the layout container is the toggleable content.
@onready var _layout: Control = %Layout
@onready var _background: Control = $Background
@onready var _shadow: ColorRect = $Shadow
@onready var _footer: Control = $Footer


func _ready() -> void:
	# Issue #304 (rework, #348 template): inside the pause overlay the
	# game stays visible behind the shared shadow dim while the
	# template's background artwork and footer are hidden.
	if in_game:
		_background.visible = false
		_shadow.color = SHADOW_COLOR
		_shadow.visible = true
		_footer.visible = false
	_back_button.pressed.connect(_on_back_pressed)

	_master_slider.value = GameConfig.master_volume
	_update_value_label(_master_value, GameConfig.master_volume)
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value = GameConfig.music_volume
	_update_value_label(_music_value, GameConfig.music_volume)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value = GameConfig.sfx_volume
	_update_value_label(_sfx_value, GameConfig.sfx_volume)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_master_slider.grab_focus()


## Volume changes apply immediately and persist at once — the same
## contract as the graphics screen (spec §6.3 rules).
func _on_master_changed(value: float) -> void:
	GameConfig.master_volume = value
	GameConfig.save_settings()
	GameConfig.apply_audio_settings()
	_update_value_label(_master_value, value)


func _on_music_changed(value: float) -> void:
	GameConfig.music_volume = value
	GameConfig.save_settings()
	GameConfig.apply_audio_settings()
	_update_value_label(_music_value, value)


func _on_sfx_changed(value: float) -> void:
	GameConfig.sfx_volume = value
	GameConfig.save_settings()
	GameConfig.apply_audio_settings()
	_update_value_label(_sfx_value, value)


## The slider's live readout — a plain percent (0% = silence).
func _update_value_label(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value * 100.0)


func _on_back_pressed() -> void:
	# Issue #304: inside the pause overlay Back returns to the settings
	# screen; the standalone screen leaves for the settings screen
	# (docs/ui/main_menu.md §6.4).
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
