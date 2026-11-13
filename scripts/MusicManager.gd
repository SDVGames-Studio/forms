extends Node
## Endless background music (issues #463, #476).
##
## Autoloaded singleton: owns ONE AudioStreamPlayer on the Music bus and
## keeps playing across scene changes. Every playable level gets its own
## endless track via play_for_level(), and the main menu has its own
## theme (#476) started by Main.gd — the loops are baked into the WAV
## imports (loop_mode = forward), so playback repeats forever without
## retrigger clicks. Finishing a level switches to the next scene's
## track; scenes without a track (submenus, credits, unknown scenes)
## stop the music.

const TRACKS := {
	"res://Main.tscn": preload("res://assets/audio/music/menu.wav"),
	"res://Level.tscn": preload("res://assets/audio/music/level1.wav"),
	"res://Level2.tscn": preload("res://assets/audio/music/level2.wav"),
	"res://Level3.tscn": preload("res://assets/audio/music/level3.wav"),
	"res://Level4.tscn": preload("res://assets/audio/music/level4.wav"),
	"res://Level5.tscn": preload("res://assets/audio/music/level5.wav"),
	"res://LevelDuel.tscn": preload("res://assets/audio/music/duel.wav"),
	"res://LevelDuelBig.tscn": preload("res://assets/audio/music/duel_big.wav"),
}

## Level paths that have a track (tests cross-check the level list).
const LEVEL_PATHS: Array[String] = [
	"res://Level.tscn", "res://Level2.tscn", "res://Level3.tscn",
	"res://Level4.tscn", "res://Level5.tscn",
	"res://LevelDuel.tscn", "res://LevelDuelBig.tscn",
]

var _player: AudioStreamPlayer
var _current_path := ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.finished.connect(_on_player_finished)
	add_child(_player)


## Endless playback: when the track runs out, restart it. The loop is
## shaped at generation time (the tail crossfades into the head — see
## scripts/gen-music.js), so the restart continues the music without an
## audible seam. Headless WAV import ignores the loop hints, so the
## restart is the guaranteed mechanism (importer-independent).
func _on_player_finished() -> void:
	if _player.stream != null and _current_path != "":
		_player.play()


## Play (and keep looping) the track of the given scene: a level's own
## track, or the main-menu theme for the main menu (#476). A path
## without a track (submenus, credits, unknown scenes) stops the music —
## no music is better than the wrong music.
func play_for_level(level_path: String) -> void:
	var stream: AudioStream = TRACKS.get(level_path)
	if stream == null:
		stop()
		return
	if level_path == _current_path and _player.playing:
		return
	_current_path = level_path
	_player.stream = stream
	_player.play()


## Stop the music (returning to a menu, leaving the game).
func stop() -> void:
	_player.stop()
	_current_path = ""


## Currently looping scene path ("" when stopped) — for tests/OSD.
func current_level() -> String:
	return _current_path
