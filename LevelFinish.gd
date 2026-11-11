class_name LevelFinish
extends Area2D
## Level finish trigger (issue #8).
##
## When the player enters the area, a short celebration overlay plays
## (issue #194) and only then the game advances to the next scene
## (exported path), e.g. from the first level to the second one.

const CELEBRATION_SCRIPT := preload("res://scripts/Celebration.gd")

@export_file("*.tscn") var next_scene: String = ""

var _celebrating := false


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and next_scene != "" and not _celebrating:
		_celebrating = true
		var celebration: CanvasLayer = CELEBRATION_SCRIPT.new()
		add_child(celebration)
		await celebration.finished
		# Issue #463: the next scene's own track (or silence on menus —
		# play_for_level stops when the path has no track).
		MusicManager.play_for_level(next_scene)
		get_tree().change_scene_to_file(next_scene)
