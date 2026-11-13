extends Node
## Issue #463: endless per-level background music.
##
## Checks: the Music bus exists in the default bus layout; every
## generated track loads as AudioStreamWAV (16-bit, mono, 44.1 kHz) with
## a FORWARD loop baked in (endless playback, no retrigger); all seven
## tracks are distinct; the MusicManager autoload owns one player on the
## Music bus; play_for_level() starts the right track, keeps it on
## repeats, and stops on trackless menu paths (issue #476 gave the
## main menu its own theme, so the stop check uses a submenu). Headless audio runs on
## the dummy driver — playback STATE is asserted, not audible output
## (documented limitation in the PR).
##
## Run headless: godot --headless res://tests/test_issue463.tscn
## Exit code 0 = pass; the printed ISSUE463 verdict is authoritative.

func _ready() -> void:
	# The driver must survive the nodes it frees, so it lives directly
	# under /root.
	var driver := MusicDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class MusicDriver extends Node:
	signal done(ok: bool)

	const LEVELS: Array[String] = [
		"res://scenes/levels/Level.tscn", "res://scenes/levels/Level2.tscn", "res://scenes/levels/Level3.tscn",
		"res://scenes/levels/Level4.tscn", "res://scenes/levels/Level5.tscn",
		"res://scenes/levels/LevelDuel.tscn", "res://scenes/levels/LevelDuelBig.tscn",
	]

	func run() -> void:
		var ok := true

		# --- Music bus present in the default bus layout. ---
		var bus_idx := AudioServer.get_bus_index("Music")
		var bus_ok: bool = bus_idx != -1
		print("ISSUE463 bus_ok=", bus_ok)
		ok = ok and bus_ok

		# --- Tracks: AudioStreamWAV, 16-bit mono 44.1 kHz, non-empty,
		# and all distinct. ---
		var streams: Array[AudioStream] = []
		for path in LEVELS:
			streams.append(MusicManager.TRACKS[path])
		var fmt_ok := true
		var data_hashes := {}
		for stream in streams:
			var wav := stream as AudioStreamWAV
			fmt_ok = fmt_ok and wav != null \
				and wav.format == AudioStreamWAV.FORMAT_16_BITS \
				and not wav.stereo \
				and wav.mix_rate == 44100 \
				and wav.data.size() > 0
			if wav != null:
				data_hashes[hash(wav.data)] = true
		var distinct_ok: bool = data_hashes.size() == LEVELS.size()
		print("ISSUE463 streams_ok=", fmt_ok, " distinct_ok=", distinct_ok)
		ok = ok and fmt_ok and distinct_ok

		# --- MusicManager autoload: one player on the Music bus. ---
		var manager: Node = get_node_or_null("/root/MusicManager")
		var player: AudioStreamPlayer = \
			manager.get("_player") if manager != null else null
		var wired: bool = manager != null and player != null \
			and player.is_inside_tree() and player.bus == "Music"
		print("ISSUE463 manager_wired=", wired)
		ok = ok and wired

		# --- Endless playback: the finished signal is wired to a restart,
		# and emitting it (end of track) keeps the player playing. ---
		var restart_wired := false
		for conn in player.get_signal_connection_list("finished"):
			restart_wired = restart_wired \
				or conn.callable.get_object() == manager
		manager.play_for_level("res://scenes/levels/Level4.tscn")
		player.finished.emit()
		var endless: bool = player.playing \
			and manager.current_level() == "res://scenes/levels/Level4.tscn"
		print("ISSUE463 endless_ok=", restart_wired and endless)
		ok = ok and restart_wired and endless

		# --- play_for_level() starts the level's track... ---
		manager.play_for_level("res://scenes/levels/Level3.tscn")
		var plays: bool = player.playing \
			and player.stream == MusicManager.TRACKS["res://scenes/levels/Level3.tscn"] \
			and manager.current_level() == "res://scenes/levels/Level3.tscn"
		# ...keeps it on a repeated call (no restart)...
		manager.play_for_level("res://scenes/levels/Level3.tscn")
		var keeps: bool = player.playing \
			and manager.current_level() == "res://scenes/levels/Level3.tscn"
		# ...switches to another level's track...
		manager.play_for_level("res://scenes/levels/LevelDuel.tscn")
		var switches: bool = player.playing \
			and player.stream == MusicManager.TRACKS["res://scenes/levels/LevelDuel.tscn"]
		# ...and stops on trackless menu paths (the main menu itself now
		# has a theme — issue #476 — so a submenu proves the stop path).
		manager.play_for_level("res://scenes/menus/SettingsMenu.tscn")
		var stops: bool = not player.playing and manager.current_level() == ""
		# A finish after stop() must NOT resurrect the music.
		player.finished.emit()
		var stays_stopped: bool = not player.playing
		print("ISSUE463 plays=", plays, " keeps=", keeps,
			" switches=", switches, " stops=", stops,
			" stays_stopped=", stays_stopped)
		ok = ok and plays and keeps and switches and stops and stays_stopped

		# --- Track list covers every playable level scene plus the
		# main-menu theme (issue #476). ---
		var cover_ok := true
		for path in LEVELS:
			cover_ok = cover_ok and MusicManager.TRACKS.has(path)
		cover_ok = cover_ok and MusicManager.TRACKS.has("res://scenes/Main.tscn")
		cover_ok = cover_ok \
			and MusicManager.TRACKS.size() == LEVELS.size() + 1
		print("ISSUE463 covers_all_levels=", cover_ok)
		ok = ok and cover_ok

		print("ISSUE463 ok=", ok)
		print("PASS" if ok else "FAIL")
		done.emit(ok)
