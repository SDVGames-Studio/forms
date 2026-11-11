extends Node
## Training-build boot router (issue #465).
##
## Exported training builds must boot the training scene, but Godot export
## presets cannot override `application/run/main_scene` per preset. The
## "Training (Linux)" export preset packs `training_build.marker` (repo root)
## into the build via its include_filter — training exports are the only ones
## that carry it (raw non-resource files are excluded from every other
## preset). When an exported (non-editor) run finds the marker, this autoload
## swaps the boot scene to training_scene.tscn instead of the main menu.
##
## Every other build is untouched: the marker is absent, the autoload returns
## immediately, and the normal main scene (Main.tscn) boots exactly as before.

func _ready() -> void:
	var training_build := not OS.has_feature("editor") \
			and FileAccess.file_exists("res://training_build.marker")
	if not training_build:
		return
	# One frame up: change_scene_to_file can't run while the tree is still
	# busy adding the autoloads / main scene (busy-parent error).
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://training_scene.tscn")
