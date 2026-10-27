extends Node2D
## Applies the level configuration chosen before the level (issue #137).
##
## Attached to the root of every playable level; see GameConfig.

func _ready() -> void:
	GameConfig.apply(self)
