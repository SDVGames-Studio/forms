extends NcnnAIController2D

## Training scaffold agent for training_scene.tscn (issue #341).
##
## Implements the minimal NcnnAIController2D contract (observation, reward,
## action space, action application) so the training scene can step against
## the Python trainer out of the box. Game-specific signals (sensors, real
## reward shaping, gameplay actions) are layered on in follow-up issues.

const MOVE_PER_STEP := 8.0
## Level.tscn playfield extents (ground rect 1152x448 centered at y=752).
const ARENA_W := 1152.0
const ARENA_H := 752.0

func get_obs() -> Dictionary:
	# Normalized own position in the instanced level (local space, so every
	# environment reports the same range regardless of its offset in the
	# training scene).
	return {"obs": [position.x / ARENA_W, position.y / ARENA_H]}

func get_reward() -> float:
	# Flat per-step cost: a non-degenerate signal until real reward shaping
	# lands. Episode-terminal rewards are added later.
	return -0.001

func get_action_space() -> Dictionary:
	return {"move": {"size": 3, "action_type": "discrete"}}

func set_action(action) -> void:
	# 0 = hold, 1 = right, 2 = left. Applied once per decision step; the
	# trainer's action_repeat controls how often that happens.
	var idx := int(action["move"])
	if idx == 1:
		position.x += MOVE_PER_STEP
	elif idx == 2:
		position.x -= MOVE_PER_STEP
