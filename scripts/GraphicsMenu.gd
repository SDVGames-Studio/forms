extends Control
## Graphics settings screen (docs/ui/main_menu.md §6.3, milestone M3).
##
## Display mode (windowed/fullscreen), windowed-resolution presets and
## vsync — the display settings that reliably apply on the desktop
## platforms this project targets (spec §6.3: only expose settings that
## can actually be applied; report limitations instead of shipping
## nonfunctional controls — headless runs sit on the dummy renderer, so
## tests assert wiring and persistence, not pixels).
## Every change persists at once (user://settings.cfg via GameConfig)
## and applies immediately where safe (GameConfig.apply_display_settings).
## Resolution presets apply to WINDOWED mode; fullscreen uses the
## desktop resolution, so the resolution control disables while
## fullscreen (the UI stays usable in every state thanks to the
## canvas_items/expand stretch).
##
## Issue #304: the SAME screen runs inside the in-game pause overlay
## (in_game) — navigation stays in the overlay, the game stays visible
## behind the shared shadow dim. Issue #348: main-menu template
## (MenuBackground artwork + MenuTheme).

## Emitted instead of the scene change when Back/Esc is pressed while the
## screen runs inside the in-game overlay (issue #304).
signal back_requested

## True while this screen is instanced into the in-game pause overlay
## (issue #304); false when it runs as the standalone settings submenu.
var in_game := false

## The shadow the in-game overlay casts over the paused game — the
## same color/alpha the pause panel uses, so the dim is identical on
## every screen of the overlay (issue #304).
const SHADOW_COLOR := Color(0.05, 0.03, 0.1, 0.75)

## 16:9 windowed presets; index 0 is the project's base resolution.
## The display's usable size joins as a NATIVE entry at runtime.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## Resolution list entries built in _ready: presets, then NATIVE (when
## the display reports a usable size), then the persisted size itself if
## it matches none (so the UI always tells the truth).
var _resolution_entries: Array[Vector2i] = []
var _native_size := Vector2i.ZERO

@onready var _mode_option: OptionButton = %DisplayModeOption
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _vsync_check: CheckButton = %VSyncCheck
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

	_mode_option.add_item("WINDOWED")
	_mode_option.add_item("FULLSCREEN")
	_mode_option.selected = clampi(GameConfig.display_mode, 0, 1)
	_mode_option.item_selected.connect(_on_mode_selected)

	_fill_resolutions()
	_resolution_option.disabled = GameConfig.display_mode == 1
	_resolution_option.item_selected.connect(_on_resolution_selected)

	_vsync_check.button_pressed = GameConfig.vsync
	_vsync_check.toggled.connect(_on_vsync_toggled)
	_mode_option.grab_focus()


## Build the resolution list: presets + NATIVE (when reported) + the
## persisted size when it matches none of them; select the persisted.
func _fill_resolutions() -> void:
	_resolution_entries.clear()
	_resolution_option.clear()
	_native_size = Vector2i.ZERO
	var screen := DisplayServer.screen_get_usable_rect()
	if screen.size.x > RESOLUTIONS[0].x and screen.size.y > RESOLUTIONS[0].y:
		_native_size = screen.size
	for preset in RESOLUTIONS:
		_add_resolution(preset, "%d × %d" % [preset.x, preset.y])
	if _native_size != Vector2i.ZERO and not _has_resolution(_native_size):
		_add_resolution(_native_size, "NATIVE (%d × %d)"
			% [_native_size.x, _native_size.y])
	if not _has_resolution(GameConfig.window_size):
		_add_resolution(GameConfig.window_size, "%d × %d"
			% [GameConfig.window_size.x, GameConfig.window_size.y])
	var selected := _resolution_entries.find(GameConfig.window_size)
	_resolution_option.selected = selected if selected >= 0 else 0


func _add_resolution(size: Vector2i, label: String) -> void:
	_resolution_entries.append(size)
	_resolution_option.add_item(label)


func _has_resolution(size: Vector2i) -> bool:
	return _resolution_entries.has(size)


## Display mode flips apply immediately; windowed also re-applies the
## stored window size (fullscreen uses the desktop resolution).
func _on_mode_selected(index: int) -> void:
	GameConfig.display_mode = index
	GameConfig.save_settings()
	GameConfig.apply_display_settings()
	_resolution_option.disabled = index == 1


## Resolution presets apply to windowed mode only (disabled while
## fullscreen) and apply immediately where safe.
func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_entries.size():
		return
	GameConfig.window_size = _resolution_entries[index]
	GameConfig.save_settings()
	GameConfig.apply_display_settings()


func _on_vsync_toggled(pressed: bool) -> void:
	GameConfig.vsync = pressed
	GameConfig.save_settings()
	GameConfig.apply_display_settings()


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
