extends Node
## Issue #495 sound-effect checks (godot-sound-work skill): the three new
## WAVs (rocket warhead blast, mine timer beep, jackhammer drill loop)
## load as AudioStreamWAV (16-bit, mono, 44.1 kHz; the drill asset is
## duplicated per Weapon with the loop set in code — Godot 4.7's headless
## wav import ignores loop pins); the physics projectile (ProjectileBody)
## gives the ROCKET its blast stream and plays it on _explode(); the
## MINE's armed fuse starts the timer beep through the REAL arming path
## (the proximity trigger in _physics_process) and _explode() stops it;
## the Weapon skips the generic shot bang for the jackhammer (weapon 5)
## and instead runs the drill loop for the drill's whole life — while
## every OTHER weapon still bangs (shotgun contrast).
## Headless audio runs on the dummy driver — playback STATE is asserted,
## not audible output (documented limitation in the PR).
##
## Run headless: godot --headless res://tests/test_issue495.tscn
## Exit code 0 = pass; the printed SFX495 ok= verdict is authoritative.

const WeaponFire := preload("res://Weapon.gd")

## Stand-in wielder (test_issue307 pattern): provides the aim frame the
## Weapon reads (aim_dir/current_gravity) without a full figure scene.
const WielderScript := "
extends CharacterBody2D
var view_angle := 0.0
func aim_dir(f: float, d: float) -> Vector2:
	return Vector2(cos(view_angle) * f, -sin(view_angle) * d)
func current_gravity() -> Vector2:
	return Vector2.DOWN
"

func _ready() -> void:
	# The driver must survive the nodes it frees, so it lives directly
	# under /root.
	var driver := Issue495Driver.new()
	driver.done.connect(func(ok: bool) -> void:
		get_tree().quit(0 if ok else 1))
	get_tree().root.add_child.call_deferred(driver)
	await get_tree().process_frame
	await get_tree().process_frame
	driver.run()


class Issue495Driver extends Node:
	signal done(ok: bool)

	func run() -> void:
		var ok := true

		# --- Streams: AudioStreamWAV, 16-bit mono 44.1 kHz, non-empty;
		# the drill loop must be imported loop_mode=Forward. ---
		var rocket: AudioStreamWAV = preload("res://assets/audio/explosions/rocket.wav")
		var mine_timer: AudioStreamWAV = preload("res://assets/audio/explosions/mine_timer.wav")
		var jackhammer: AudioStreamWAV = preload("res://assets/audio/weapons/jackhammer.wav")
		var fmt_ok := true
		for stream in [rocket, mine_timer, jackhammer]:
			var wav := stream as AudioStreamWAV
			fmt_ok = fmt_ok and wav != null \
				and wav.format == AudioStreamWAV.FORMAT_16_BITS \
				and not wav.stereo \
				and wav.mix_rate == 44100 \
				and wav.data.size() > 0
		print("SFX495 streams_ok=", fmt_ok)
		ok = ok and fmt_ok

		# --- Rocket blast: wired by kind on the SFX bus, played by the
		# REAL _explode() entry (group lookups are empty outside a level,
		# so the call is safe headless — same as the issue #475 checks). ---
		var rocket_body: ProjectileBody = ProjectileBody.new()
		rocket_body.setup(ProjectileBody.Kind.ROCKET, Vector2(200, 0), 30, 2.0,
			Vector2(22, 8), Color.WHITE, 100.0, 1.0)
		add_child(rocket_body)
		await get_tree().process_frame
		var r_player: AudioStreamPlayer = rocket_body.get("_blast_player")
		var r_wired: bool = r_player != null and r_player.is_inside_tree() \
			and r_player.bus == "SFX" and r_player.stream == rocket
		rocket_body._explode()
		var r_plays: bool = r_player != null and r_player.playing
		print("SFX495 rocket wired=", r_wired, " plays_on_explode=", r_plays)
		ok = ok and r_wired and r_plays
		await get_tree().process_frame

		# --- Mine timer: the REAL arming path (a player-team figure steps
		# into the trigger radius in _physics_process) starts the beep;
		# _explode() stops it and plays the blast instead. ---
		var mine_body: ProjectileBody = ProjectileBody.new()
		mine_body.setup(ProjectileBody.Kind.MINE, Vector2.ZERO, 30, 4.0,
			Vector2(14, 14), Color.WHITE, 100.0, 0.6)
		add_child(mine_body)
		await get_tree().process_frame
		# Skip the settle-physics wait: force the dormant state, then put
		# a figure on top of the mine — the trigger arms the fuse.
		mine_body.set("_settled", true)
		var trigger := Node2D.new()
		trigger.add_to_group("player_team")
		add_child(trigger)
		for i in 4:
			await get_tree().process_frame
		var m_timer: AudioStreamPlayer = mine_body.get("_timer_player")
		var m_armed: bool = bool(mine_body.get("_armed"))
		var m_beeps: bool = m_timer != null and m_timer.is_inside_tree() \
			and m_timer.bus == "SFX" and m_timer.stream == mine_timer \
			and m_timer.playing
		mine_body._explode()
		var m_stopped: bool = m_timer != null and not m_timer.playing
		var m_blast: AudioStreamPlayer = mine_body.get("_blast_player")
		var m_booms: bool = m_blast != null and m_blast.playing
		print("SFX495 mine armed=", m_armed, " timer_beeps=", m_beeps,
			" stops_on_explode=", m_stopped, " blast_plays=", m_booms)
		ok = ok and m_armed and m_beeps and m_stopped and m_booms
		trigger.queue_free()
		await get_tree().process_frame

		# --- Weapon: the jackhammer (5) commits WITHOUT the shot bang and
		# WITH the drill loop; ending the drill stops the loop; the shotgun
		# (0) still bangs (the skip is jackhammer-specific). ---
		var wielder := CharacterBody2D.new()
		var script := GDScript.new()
		script.source_code = WielderScript
		script.reload()
		wielder.set_script(script)
		wielder.add_to_group("player_team")
		add_child(wielder)
		await get_tree().process_frame
		var weapon := WeaponFire.new()
		wielder.add_child(weapon)
		await get_tree().process_frame
		weapon.selected_weapon = 5
		weapon._fire(1.0)
		var d_player: AudioStreamPlayer = weapon.get("_drill_player")
		var s_player: AudioStreamPlayer = weapon.get("_shot_player")
		var d_stream := d_player.stream as AudioStreamWAV
		var drill_runs: bool = weapon.is_drilling() \
			and d_player != null and d_player.is_inside_tree() \
			and d_player.bus == "SFX" \
			and d_stream != null \
			and d_stream.format == AudioStreamWAV.FORMAT_16_BITS \
			and d_stream.data.size() == jackhammer.data.size() \
			and d_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD \
			and d_stream.loop_end == d_stream.data.size() / 2 \
			and d_player.playing
		var no_bang: bool = s_player != null and not s_player.playing
		print("SFX495 jackhammer drill_runs=", drill_runs,
			" shot_bang_skipped=", no_bang)
		ok = ok and drill_runs and no_bang
		weapon._end_jackhammer()
		var drill_stops: bool = not weapon.is_drilling() \
			and d_player != null and not d_player.playing
		print("SFX495 drill_stops=", drill_stops)
		ok = ok and drill_stops
		weapon.selected_weapon = 0
		weapon._fire(1.0)
		var still_bangs: bool = s_player != null and s_player.playing
		print("SFX495 shotgun_still_bangs=", still_bangs)
		ok = ok and still_bangs

		print("SFX495 ok=", ok)
		done.emit(ok)
