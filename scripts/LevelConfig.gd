extends Node2D
## Applies the level configuration chosen before the level (issue #137).
##
## Attached to the root of every playable level; see GameConfig.

## Issue #614: the scene loaded when the level's real finish hits
## (only one team left standing — TurnController._check_win). This
## REPLACES the removed Finish trigger area: the campaign chain keeps
## its authored target (Level -> Level2 -> Main), while levels without
## an authored chain fall back to the Main menu.
@export_file("*.tscn") var next_scene: String = ""


func _ready() -> void:
	GameConfig.apply(self)
	# Issue #367: the night regime is picked in the level
	# configuration menu and applied when the level starts.
	if GameConfig.night_regime:
		NightRegime.apply(self)
	# Issue #523: the spawn regime places the figures once the
	# configuration has trimmed and dressed them.
	SpawnRegime.apply(self)
