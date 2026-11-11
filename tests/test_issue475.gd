extends Node
## Issue #475 sound-effect checks (godot-sound-work skill): the four new
## WAVs (grenade blast, mine blast, teleport hop, rock crumble) load as
## AudioStreamWAV (16-bit, mono, 44.1 kHz); the physics projectile
## (ProjectileBody) carries an SFX-bus blast player whose stream matches
## its kind and _explode() starts playback (the player is re-homed to
## the level so it survives the body's queue_free()); the teleport hop
## plays from the ToolInventory autoload (SFX bus, pitch 0.95–1.05) —
## the same call Npc's teleport-away shortcut makes.
## Headless audio runs on the dummy driver — playback STATE is asserted,
## not audible output (documented limitation in the PR).
##
## Run headless: godot --headless res://tests/test_issue475.tscn
## Exit code 0 = pass; the printed SFX475 ok= verdict is authoritative.

func _ready() -> void:
	# The driver must survive the nodes it frees, so it lives directly
	# under /root.
	var driver := Issue475Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue475Driver extends Node:
	signal done(ok: bool)

	func run() -> void:
		var ok := true

		# --- Streams: AudioStreamWAV, 16-bit mono 44.1 kHz, non-empty. ---
		var grenade := preload("res://assets/audio/explosions/grenade.wav")
		var mine := preload("res://assets/audio/explosions/mine.wav")
		var teleport := preload("res://assets/audio/tools/teleport.wav")
		var rock := preload("res://assets/audio/tools/rock_crumble.wav")
		var fmt_ok := true
		for stream in [grenade, mine, teleport, rock]:
			var wav := stream as AudioStreamWAV
			fmt_ok = fmt_ok and wav != null \
				and wav.format == AudioStreamWAV.FORMAT_16_BITS \
				and not wav.stereo \
				and wav.mix_rate == 44100 \
				and wav.data.size() > 0
		print("SFX475 streams_ok=", fmt_ok)
		ok = ok and fmt_ok

		# --- ProjectileBody wiring: one SFX-bus player per projectile
		# whose stream is picked by kind; _explode() is the REAL blast
		# entry (ground/damage lookups are group-based — empty outside a
		# level, so the call is safe headless) and must start playback.
		# The check happens synchronously after _explode(): the player
		# was re-homed to this driver, so it stays valid even though the
		# body queue_free()s at the end of the frame. ---
		var cases := {
			ProjectileBody.Kind.GRENADE: grenade,
			ProjectileBody.Kind.MINE: mine,
			ProjectileBody.Kind.ROCK: rock,
		}
		for kind in cases:
			var body: ProjectileBody = ProjectileBody.new()
			body.setup(kind, Vector2(200, 0), 30, 2.0,
				Vector2(14, 14), Color.WHITE, 100.0, 0.6)
			add_child(body)
			await get_tree().process_frame
			var player: AudioStreamPlayer = body.get("_blast_player")
			var wired: bool = player != null and player.is_inside_tree() \
				and player.bus == "SFX" \
				and player.stream == cases[kind]
			body._explode()
			var plays: bool = player != null and player.playing
			print("SFX475 kind=", kind, " wired=", wired,
				" plays_on_explode=", plays)
			ok = ok and wired and plays
			await get_tree().process_frame

		# --- Teleport hop: the ToolInventory autoload carries an SFX-bus
		# player with the preloaded stream; play_teleport_sound() starts
		# playback with the skill's random pitch (0.95–1.05). ---
		var t_player: AudioStreamPlayer = ToolInventory.get("_teleport_player")
		var t_wired: bool = t_player != null and t_player.is_inside_tree() \
			and t_player.bus == "SFX" \
			and t_player.stream == teleport
		ToolInventory.play_teleport_sound()
		var t_plays: bool = t_player != null and t_player.playing
		var t_pitch: bool = t_player != null \
			and t_player.pitch_scale >= 0.95 \
			and t_player.pitch_scale <= 1.05
		print("SFX475 teleport_wired=", t_wired, " plays=", t_plays,
			" pitch_ok=", t_pitch)
		ok = ok and t_wired and t_plays and t_pitch

		print("SFX475 ok=", ok)
		done.emit(ok)
