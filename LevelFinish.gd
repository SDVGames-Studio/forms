extends Area2D
## Level finish trigger (issue #8).
##
## When the player enters the area, the game advances to the next scene
## (exported path), e.g. from the first level to the second one.

@export_file("*.tscn") var next_scene: String = ""


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and next_scene != "":
		get_tree().change_scene_to_file(next_scene)
