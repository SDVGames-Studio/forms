extends Node
## Issue #476: the main menu's endless theme music.
##
## Checks: the generated menu track loads as AudioStreamWAV (16-bit,
## mono, 44.1 kHz) with data, is distinct from every level track
## (#463), and is mapped to the main-menu scene in MusicManager.TRACKS;
## play_for_level("res://Main.tscn") starts it and keeps it on repeated
## calls; the finished-restart wiring makes it endless; a level track
## takes over cleanly and the theme restores afterwards; a freshly
## instantiated Main.tscn starts the theme from its _ready(). Headless
## audio runs on the dummy driver — playback STATE is asserted, not
## audible output (documented limitation in the PR).
##
## Run headless: godot --headless res://tests/test_issue476.tscn
## Exit code 0 = pass; the printed ISSUE476 verdict is authoritative.

func _ready() -> void:
	# The driver must survive the nodes it frees, so it lives directly
	# under /root.
	var driver := MenuMusicDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class MenuMusicDriver extends Node:
	signal done(ok: bool)

	func run() -> void:
		var ok := true

		# --- Menu stream: AudioStreamWAV 16-bit mono 44.1 kHz, non-empty,
		# and mapped to the main-menu scene. ---
		var menu_stream: AudioStream = MusicManager.TRACKS.get("res://Main.tscn")
		var wav := menu_stream as AudioStreamWAV
		var fmt_ok: bool = wav != null \
			and wav.format == AudioStreamWAV.FORMAT_16_BITS \
			and not wav.stereo \
			and wav.mix_rate == 44100 \
			and wav.data.size() > 0
		print("ISSUE476 menu_stream_ok=", fmt_ok)
		ok = ok and fmt_ok

		# --- Distinct from every level track. ---
		var distinct := true
		if wav != null:
			var menu_hash := hash(wav.data)
			for path in MusicManager.LEVEL_PATHS:
				var level_wav := MusicManager.TRACKS[path] as AudioStreamWAV
				distinct = distinct and hash(level_wav.data) != menu_hash
		print("ISSUE476 distinct_from_levels=", distinct)
		ok = ok and distinct

		# --- MusicManager autoload: one player on the Music bus. ---
		var manager: Node = get_node_or_null("/root/MusicManager")
		var player: AudioStreamPlayer = \
			manager.get("_player") if manager != null else null
		var wired: bool = manager != null and player != null \
			and player.is_inside_tree() and player.bus == "Music"
		print("ISSUE476 manager_wired=", wired)
		ok = ok and wired

		# --- The main menu starts its theme; a repeated call keeps it
		# playing with the same stream (no restart). ---
		manager.play_for_level("res://Main.tscn")
		var plays: bool = player.playing \
			and player.stream == menu_stream \
			and manager.current_level() == "res://Main.tscn"
		manager.play_for_level("res://Main.tscn")
		var keeps: bool = player.playing and player.stream == menu_stream
		print("ISSUE476 plays=", plays, " keeps=", keeps)
		ok = ok and plays and keeps

		# --- Endless: end of track restarts the theme. ---
		player.finished.emit()
		var endless: bool = player.playing \
			and player.stream == menu_stream \
			and manager.current_level() == "res://Main.tscn"
		print("ISSUE476 endless=", endless)
		ok = ok and endless

		# --- Handover: a level track replaces the theme... ---
		manager.play_for_level("res://Level2.tscn")
		var level_plays: bool = player.playing \
			and player.stream == MusicManager.TRACKS["res://Level2.tscn"]
		# ...and returning to the main menu restores it.
		manager.play_for_level("res://Main.tscn")
		var restores: bool = player.playing and player.stream == menu_stream
		print("ISSUE476 level_handover=", level_plays,
			" restores=", restores)
		ok = ok and level_plays and restores

		# --- Main.tscn wiring: a fresh main menu starts the theme from
		# its _ready() (the autoload player is shared, so stop first). ---
		manager.stop()
		var main := (load("res://Main.tscn") as PackedScene).instantiate()
		add_child(main)
		await get_tree().process_frame
		var scene_starts: bool = player.playing \
			and player.stream == menu_stream
		print("ISSUE476 main_scene_starts_theme=", scene_starts)
		ok = ok and scene_starts
		main.queue_free()

		print("ISSUE476 ok=", ok)
		print("PASS" if ok else "FAIL")
		done.emit(ok)
