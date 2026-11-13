extends Node
## Exported-build boot router (issue #465; eval extension issue #508).
##
## Exported training builds must boot the training scene, but Godot export
## presets cannot override `application/run/main_scene` per preset. The
## "Training (Linux)" export preset packs `training_build.marker` (repo root)
## into the build via its include_filter — training exports are the only ones
## that carry it (raw non-resource files are excluded from every other
## preset). When an exported (non-editor) run finds the marker, this autoload
## swaps the boot scene to training_scene.tscn instead of the main menu.
##
## Issue #508 adds the eval twin: the "Eval (Linux)" preset packs
## `eval_build.marker` and boots eval_scene.tscn — the automated ncnn
## deployment evaluation (whole-match episodes inside the exported build,
## the file-packing / no-editor path #508 explicitly targets).
##
## Every other build is untouched: both markers are absent, the autoload
## returns immediately, and the normal main scene (Main.tscn) boots exactly
## as before. If both markers are ever packed together, training wins.

func _ready() -> void:
	var training_build := not OS.has_feature("editor") \
			and FileAccess.file_exists("res://training_build.marker")
	var eval_build := not OS.has_feature("editor") \
			and FileAccess.file_exists("res://eval_build.marker")
	if not training_build and not eval_build:
		return
	# One frame up: change_scene_to_file can't run while the tree is still
	# busy adding the autoloads / main scene (busy-parent error).
	await get_tree().process_frame
	if training_build:
		get_tree().change_scene_to_file("res://training_scene.tscn")
	else:
		get_tree().change_scene_to_file("res://eval_scene.tscn")
