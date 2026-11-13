extends Node
## Sound-effect checks (owner task 2026-11-11, godot-sound-work skill):
## the SFX bus exists in the default bus layout at 0 dB; both generated
## WAVs load as AudioStreamWAV (16-bit, mono, 44.1 kHz); the shot player
## is wired into the Weapon fire path (preloaded stream, SFX bus, random
## pitch 0.95–1.05, play() on the sound hook) and the explosion player
## into the Projectile blast path (plays from the real _explode() entry).
## Headless audio runs on the dummy driver — playback STATE is asserted,
## not audible output (documented limitation in the PR).
##
## Run headless: godot --headless res://tests/test_sound_effects.tscn
## Exit code 0 = pass; the printed SFX ok= verdict is authoritative.

func _ready() -> void:
	# The driver must survive the nodes it frees, so it lives directly
	# under /root.
	var driver := SoundEffectsDriver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class SoundEffectsDriver extends Node:
	signal done(ok: bool)

	func run() -> void:
		var ok := true

		# --- SFX bus present in the default bus layout, 0 dB. ---
		var bus_idx := AudioServer.get_bus_index("SFX")
		var bus_ok: bool = bus_idx != -1 and is_equal_approx(
			AudioServer.get_bus_volume_db(bus_idx), 0.0)
		print("SFX bus_ok=", bus_ok)
		ok = ok and bus_ok

		# --- Streams: AudioStreamWAV, 16-bit mono 44.1 kHz, non-empty. ---
		var shot := preload("res://assets/audio/weapons/shot.wav")
		var boom := preload("res://assets/audio/explosions/explosion.wav")
		var fmt_ok: bool = shot is AudioStreamWAV \
			and boom is AudioStreamWAV
		for stream in [shot, boom]:
			var wav := stream as AudioStreamWAV
			fmt_ok = fmt_ok and wav != null \
				and wav.format == AudioStreamWAV.FORMAT_16_BITS \
				and not wav.stereo \
				and wav.mix_rate == 44100 \
				and wav.data.size() > 0
		print("SFX streams_ok=", fmt_ok)
		ok = ok and fmt_ok

		# --- Weapon fire path: player child on the SFX bus with the
		# preloaded stream; the sound hook plays it with the skill's
		# random pitch (0.95–1.05). ---
		var weapon := preload("res://scripts/Weapon.gd").new()
		add_child(weapon)
		await get_tree().process_frame
		var w_player: AudioStreamPlayer = weapon.get("_shot_player")
		var wired: bool = w_player != null and w_player.is_inside_tree() \
			and w_player.bus == "SFX" \
			and w_player.stream == shot
		weapon._play_shot_sound()
		var plays: bool = w_player != null and w_player.playing
		var pitch_ok: bool = w_player != null \
			and w_player.pitch_scale >= 0.95 \
			and w_player.pitch_scale <= 1.05
		print("SFX weapon_wired=", wired, " plays=", plays,
			" pitch_ok=", pitch_ok)
		ok = ok and wired and plays and pitch_ok
		weapon.queue_free()

		# --- Projectile blast path: player child on the SFX bus with the
		# preloaded stream; _explode() is the REAL blast entry (ground
		# and damage lookups are group-based — empty outside a level, so
		# the call is safe headless) and must start playback. The check
		# happens synchronously: _explode() queue_free()s the projectile
		# and its player at the end. ---
		var proj: Projectile = Projectile.new()
		proj.setup(Projectile.Type.ROCKET, Vector2(400, 0), 30, 2.0,
			Vector2(12, 6), Color.WHITE, 40.0)
		add_child(proj)
		await get_tree().process_frame
		var p_player: AudioStreamPlayer = proj.get("_explosion_player")
		var p_wired: bool = p_player != null \
			and p_player.is_inside_tree() \
			and p_player.bus == "SFX" \
			and p_player.stream == boom
		proj._explode()
		var p_plays: bool = p_player != null and p_player.playing
		print("SFX projectile_wired=", p_wired, " plays_on_explode=",
			p_plays)
		ok = ok and p_wired and p_plays

		print("SFX ok=", ok)
		done.emit(ok)
