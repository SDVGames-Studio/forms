extends Node
## Issue #503 checks: the VecNormalize observation-statistics sidecar
## (models/vecnormalize_stats.json, written by export_vecnormalize_stats.py)
## loads and validates, and ObsNormalize.normalize() — the exact replay the
## ncnn wrapper runs pre-inference — reproduces the normalized observations
## SB3 fed to the policy during training. Expected vectors below are
## training-truth numbers produced by stable_baselines3 VecNormalize.
## normalize_obs on the issue471_check run's stats (computed Python-side,
## hardcoded so the GDScript path is checked against SB3, not against
## itself). Also covers the norm_obs ACTIVE flag (#503): false → raw
## passthrough, missing (legacy policy.norm.json sidecars) → active.
##
## Run headless: godot --headless res://tests/test_issue503.tscn
## Exit code 0 = pass; the printed ISS503 ok= verdict is authoritative.

const ObsNormalize := preload("res://addons/godot_native_rl/controllers/obs_normalize.gd")

const STATS_PATH := "res://models/vecnormalize_stats.json"

# SB3 VecNormalize.normalize_obs output for raw [1.0, -2.5] (dim 1 clips to
# -clip_obs) and for the extreme [500.0, -500.0] (both dims clip).
const RAW_A := [1.0, -2.5]
const EXPECT_A := [4.5320820808410645, -10.0]
const RAW_B := [500.0, -500.0]
const EXPECT_B := [10.0, -10.0]

func _ready() -> void:
	var ok := true

	# --- Sidecar artifact: exists, parses, validates, typed-active. ---
	var f := FileAccess.open(STATS_PATH, FileAccess.READ)
	var sidecar_ok: bool = f != null
	var parsed: Dictionary = {}
	if sidecar_ok:
		var text := f.get_as_text()
		f.close()
		parsed = JSON.parse_string(text)
		sidecar_ok = parsed is Dictionary and ObsNormalize.validate(parsed)
	print("ISS503 sidecar_valid=", sidecar_ok)
	ok = ok and sidecar_ok
	if not sidecar_ok:
		print("ISS503 ok=", false)
		get_tree().quit(1)
		return
	var typed := ObsNormalize.to_typed(parsed)
	var active: bool = not typed.is_empty() and typed.get("norm_obs", false)
	print("ISS503 norm_obs_active=", active)
	ok = ok and active

	# --- Known answers (training-truth, see header). ---
	if active:
		var got_a := ObsNormalize.normalize(PackedFloat32Array(RAW_A),
			typed["mean"], typed["var"], typed["epsilon"], typed["clip_obs"])
		var got_b := ObsNormalize.normalize(PackedFloat32Array(RAW_B),
			typed["mean"], typed["var"], typed["epsilon"], typed["clip_obs"])
		var match_a: bool = got_a.size() == 2 \
			and absf(got_a[0] - EXPECT_A[0]) < 1e-5 and absf(got_a[1] - EXPECT_A[1]) < 1e-5
		var match_b: bool = got_b.size() == 2 \
			and absf(got_b[0] - EXPECT_B[0]) < 1e-5 and absf(got_b[1] - EXPECT_B[1]) < 1e-5
		print("ISS503 known_answer_a=", match_a, " (got ", got_a, ")")
		print("ISS503 known_answer_b=", match_b, " (got ", got_b, ")")
		ok = ok and match_a and match_b

	# --- Active flag semantics: false honored, missing = legacy active,
	# non-bool rejected by validate(). ---
	var inactive := parsed.duplicate(true)
	inactive["norm_obs"] = false
	var inactive_ok: bool = ObsNormalize.validate(inactive) \
		and not ObsNormalize.to_typed(inactive)["norm_obs"]
	var legacy := parsed.duplicate(true)
	legacy.erase("norm_obs")
	var legacy_ok: bool = ObsNormalize.validate(legacy) \
		and ObsNormalize.to_typed(legacy).get("norm_obs", false)
	var bad_flag := parsed.duplicate(true)
	bad_flag["norm_obs"] = "yes"
	var bad_ok: bool = not ObsNormalize.validate(bad_flag)
	print("ISS503 flag_false_honored=", inactive_ok, " legacy_defaults_active=", legacy_ok,
		" nonbool_rejected=", bad_ok)
	ok = ok and inactive_ok and legacy_ok and bad_ok

	print("ISS503 ok=", ok)
	get_tree().quit(0 if ok else 1)
