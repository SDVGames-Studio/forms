extends Node2D
## Training-scene convenience knobs (issue #608).
##
## training_scene.tscn boots in the exported training build (the
## TrainingBoot autoload routes here via training_build.marker) and in
## editor test runs — nobody drives the human side in either. The
## scene-level convenience mirrors the eval twin (eval_match.gd): the
## idle turn time is compressed, because every figure whose turn nobody
## acts on burns the full menu turn_time (15 s default) standing still,
## and most of every training episode would be dead time waiting for
## those timers. TurnController honors GameConfig.turn_time per turn;
## 3.0 s is the same value eval_match.gd uses for its unattended runs.
##
## The second convenience is authored directly in the scene file: each
## environment's Bot pins BotController.figure_path at its level's
## Player figure, so the controller plays ONE named figure for the whole
## episode instead of re-resolving the NEAREST alive figure every
## decision step (BotController._resolve_alive_figure) — an unpinned
## selection silently jumps between figures as they move and die, and
## reset() then restores whatever stand-in was resolved last.

## Seconds an un-acted figure's turn may burn in the training build.
## <= 0 keeps whatever GameConfig carries (no override).
@export var idle_turn_time := 3.0

func _init() -> void:
	# Issue #659: the hero team must be HUMAN-brained in the training
	# scene — the RL controller (BotController's turn executor) is the
	# only brain the player side may carry. This runs when the scene is
	# INSTANTIATED, before any instanced environment child enters the
	# tree (a child's _ready runs after the root's _init), so the
	# GameConfig.apply dressing pass — which gives the staged figures
	# their brains per the configured controllers — still sees the
	# override. Without it the all-computer default dresses the hero as
	# Npc.gd and the scripted AI, not the policy, would act for the
	# player side (while the pending order sat unconsumed).
	if GameConfig.teams.is_empty():
		GameConfig.load_teams()
	GameConfig.teams[0]["controller"] = "player"

func _ready() -> void:
	if idle_turn_time > 0.0:
		GameConfig.turn_time = idle_turn_time
