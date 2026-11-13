extends Node
## Issue #504 checks: the pnnx conversion artifacts live in the Godot project
## AND are covered by the addon's export auto-packing, so an exported game can
## never hit "cannot read model files" at runtime.
##
## 1. models/policy.ncnn.param + models/policy.ncnn.bin exist in the project
##    and are readable (Definition of Done, #504).
## 2. Their bytes match the pair produced by the documented conversion
##    (DEPLOYMENT.md §3: pnnx 20261020 on models/policy-logits.onnx,
##    inputshape=[1,2], pass_ncnn exits 0) — re-running that command on the
##    shipped .onnx reproduces BOTH files byte-identically (verified
##    2026-11-13, sha256 pinned below). A mismatch means the pair was
##    regenerated without re-running the documented pipeline.
## 3. The .param is a structurally valid ncnn graph file: magic 7767517,
##    layer/blob counts parse, and the pnnx blob convention in0/out0 is
##    present (the NcnnRunner input_blob_name/output_blob_name defaults).
## 4. ModelFileScan.find_model_files() with the plugin's effective skip
##    roots — the EXACT scan ModelExportPlugin._export_begin runs during
##    every game export — returns BOTH files under res://, i.e. they are
##    force-packed by the addon's EditorExportPlugin (raw .param/.bin are
##    otherwise skipped by Godot: they are not Resource dependencies).
##
## Run headless: godot --headless res://tests/test_issue504.tscn
## Exit code 0 = pass; the printed ISS504 ok= verdict is authoritative.

const ModelFileScan := preload("res://addons/godot_native_rl/export/model_file_scan.gd")

const PARAM_PATH := "res://models/policy.ncnn.param"
const BIN_PATH := "res://models/policy.ncnn.bin"

## sha256 of the pnnx 20261020 output converted from the shipped
## models/policy-logits.onnx (reproduced byte-identically from the documented
## command; keep in sync when the model is legitimately re-exported).
const PINNED_PARAM_SHA := "c11a3ba7a33d868cd5583235530347e8f542957c84fe0ea077bdccb6b9af20f7"
const PINNED_BIN_SHA := "510dfad8b70aa486f3a9e1bedf872bad0d48442418e6c66e9dde7c84816de64a"

const NCNN_MAGIC := "7767517"

func _ready() -> void:
	var ok := true

	# --- 1. Both artifacts exist in the project and are readable. ---
	var param_text := FileAccess.get_file_as_string(PARAM_PATH)
	var bin_bytes := FileAccess.get_file_as_bytes(BIN_PATH)
	var files_ok: bool = not param_text.is_empty() and not bin_bytes.is_empty()
	print("ISS504 model_files_readable=", files_ok)
	ok = ok and files_ok

	# --- 2. Bytes pinned to the documented, reproducible pnnx conversion. ---
	var param_sha := _sha256_file(PARAM_PATH) if files_ok else ""
	var bin_sha := _sha256_file(BIN_PATH) if files_ok else ""
	var sha_ok: bool = param_sha == PINNED_PARAM_SHA and bin_sha == PINNED_BIN_SHA
	print("ISS504 sha256_matches_pnnx_output=", sha_ok, " (param ", param_sha.substr(0, 12),
		"…, bin ", bin_sha.substr(0, 12), "…)")
	ok = ok and sha_ok

	# --- 3. The .param parses as an ncnn graph with the in0/out0 blobs. ---
	var lines := param_text.split("\n")
	var counts: PackedStringArray = lines[1].split(" ") if lines.size() > 1 else PackedStringArray()
	var magic: String = lines[0] if lines.size() > 0 else "?"
	var layer_count: String = counts[0] if counts.size() >= 1 else "?"
	var blob_count: String = counts[1] if counts.size() >= 2 else "?"
	var param_ok: bool = lines.size() > 2 and lines[0] == NCNN_MAGIC \
		and counts.size() == 2 and counts[0].to_int() > 0 and counts[1].to_int() > 0 \
		and param_text.contains("in0") and param_text.contains("out0")
	print("ISS504 param_valid=", param_ok, " (magic ", magic,
		", layers ", layer_count, ", blobs ", blob_count, ")")
	ok = ok and param_ok

	# --- 4. The export-plugin scan force-packs BOTH files into exports. ---
	var pruned := PackedStringArray()
	var skip_roots := ModelFileScan.effective_skip_roots()
	var scanned: PackedStringArray = ModelFileScan.find_model_files("res://", skip_roots, pruned)
	var packs_param: bool = PARAM_PATH in scanned
	var packs_bin: bool = BIN_PATH in scanned
	var not_pruned: bool = not (PARAM_PATH in pruned) and not (BIN_PATH in pruned)
	var export_ok: bool = packs_param and packs_bin and not_pruned
	print("ISS504 export_scan_packs=", export_ok, " (param ", packs_param, ", bin ", packs_bin,
		", skip_roots ", skip_roots, ")")
	ok = ok and export_ok

	print("ISS504 ok=", ok)
	get_tree().quit(0 if ok else 1)

func _sha256_file(path: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var chunk := f.get_buffer(65536)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	f.close()
	return ctx.finish().hex_encode()
