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

## Discrete action space for the turn-based team deathmatch (issue #382).
## A dictionary of discrete action heads in the godot_rl_agents contract:
## each key is an independent decision dimension and the Python training
## handshake builds one spaces.Discrete(size) object per head. Grounded in
## the game's own controls — movement set, aim keys, and the inventory's
## four weapon slots (keys 1-4):
##   "move":   0 hold | 1 walk right | 2 walk left | 3 jump | 4 backflip | 5 skip turn
##   "aim":    0 hold | 1 aim up | 2 aim down
##   "attack": 0 hold fire | 1-4 select+fire weapon slot 1-4
func get_action_space() -> Dictionary:
	return {
		"move": {"size": 6, "action_type": "discrete"},
		"aim": {"size": 3, "action_type": "discrete"},
		"attack": {"size": 5, "action_type": "discrete"},
	}

func set_action(action) -> void:
	# Applied once per decision step; the trainer's action_repeat controls how
	# often that happens. The scaffold actuates the walk deltas for now —
	# jump/backflip/skip, aim and weapon actuation are the gameplay follow-ups
	# layered on top of this contract (see the file header).
	var move_idx := int(action["move"])
	if move_idx == 1:
		position.x += MOVE_PER_STEP
	elif move_idx == 2:
		position.x -= MOVE_PER_STEP
