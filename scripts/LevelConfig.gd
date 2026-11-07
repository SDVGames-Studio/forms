extends Node2D
## Applies the level configuration chosen before the level (issue #137).
##
## Attached to the root of every playable level; see GameConfig.

func _ready() -> void:
	GameConfig.apply(self)
	# Issue #367: the night regime is picked in the level
	# configuration menu and applied when the level starts.
	if GameConfig.night_regime:
		NightRegime.apply(self)
