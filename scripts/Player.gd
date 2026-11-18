extends Character
## Playable figure for the simple level (issue #1).
##
## Issue #611: the controller-pattern refactor, slice 1 — every shared
## mechanic (physics tick, gravity frame, health/bar/shield, damage and
## death flow, controller API) moved into the unified Character base
## (scripts/Character.gd). This script is now the figure's PLAYER-side
## brain: it reads the input (the ONLY place Input is read for a human
## figure) and turns it into Character API calls (move/aim/jump). The
## scripted AI lives in Npc.gd, the RL policy reaches the same API
## through BotController.gd.
##
## Left/right movement plus jump, driven by the move_left/move_right/jump
## actions (WASD and arrow keys, Space); gravity is applied while airborne.
##
## Issue #33: the player controls their WHOLE team — every team member uses
## this script. Exactly one member is `controlled` (driven by input); the
## rest just stay in place (issue #40). TeamController (autoload) hands
## control between members — via the Switch tool (issue #170) or its N/P
## key shortcuts (issue #215). All members share the same shape and color
## and show a name above the health bar.

## Issue #521: which side this figure fights on. "player" (default) is
## the classic hero team; "enemy" stages a HUMAN-played figure among the
## enemy teams (one-device multiplayer: GameConfig.apply swaps a team's
## computer figures for Player figures when the team's controller is
## "player"). Only the group membership differs — the input, the weapon
## and the camera all follow TurnController's active team.
@export var team_side := "player"

## Issue #33: true for the member currently driven by player input.
var controlled := false

var _camera: Camera2D


func _ready() -> void:
	# One group for every member of the player's team; the NPC team AI
	# targets "player"/"team" so all members are valid opponents.
	# Issue #521: a human figure staged on the enemy side joins the enemy
	# groups instead, so TurnController treats it as its own team (by
	# color) while is_player_team() still lets input flow on its turns.
	add_to_group("enemy" if team_side == "enemy" else "player")
	add_to_group("team")
	add_to_group("enemy_team" if team_side == "enemy" else "player_team")
	# Issue #33: if no team member ended up controlled (fresh scene),
	# the first one takes control.
	if not controlled:
		call_deferred("_claim_control_if_none")
	# Issue #39 rework: characters collide with each other but never push —
	# a walking figure is simply BLOCKED by another figure (issue #144:
	# one character must not move or displace another during its move).
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	# Issue #155: a character must never be carried by another character —
	# only terrain (layer 1) acts as a platform, so a walking figure cannot
	# drag a rider standing on it (characters still block each other).
	platform_floor_layers = 1
	_apply_team_color()
	_apply_team_shape()
	_attach_animator()
	_build_health_bar()
	# Issue #252: debug-mode visuals — HP number, damage popup, arrow.
	_build_debug_visuals()
	set_controlled(controlled)


## Issue #169: apply color, shape and name customisation after the fact
## (called by GameConfig.apply once the level trimmed the team).
func apply_team_setup() -> void:
	# Issue #537 rework v3: figures trimmed moments ago sit in the group
	# until the frame ends — name by the LIVE index. With menu-driven
	# team sizes the FIRST team's names/color/shape come straight from
	# the menu set (the grids go to 64 members and carry the per-game
	# color/name overrides); the classic fields stay the source otherwise.
	var live: Array = []
	for figure in get_tree().get_nodes_in_group("player_team"):
		if not figure.is_queued_for_deletion():
			live.append(figure)
	var names: Array = GameConfig.member_names
	var menu_driven := GameConfig.menu_team_sizes \
			and not GameConfig.teams.is_empty()
	if menu_driven:
		names = GameConfig.teams[0]["names"]
	display_name = str(names[mini(maxi(live.find(self), 0),
			names.size() - 1)])
	if menu_driven:
		team_color = GameConfig.teams[0]["color"]
		team_shape = str(GameConfig.teams[0]["shape"])
	else:
		team_color = GameConfig.team_color
		team_shape = GameConfig.team_shape
	_apply_team_color()
	_apply_team_shape()
	_attach_animator()


## Issue #556: every team figure wears the modular expressive character
## (the issue #557 component) as its body — square teams included: the
## authored square ColorRect is hidden and replaced exactly like the
## other silhouettes replaced it before (issue #169). The look (team
## color + silhouette + the member's personality) is applied on every
## call, so GameConfig re-runs restyle the SAME node instead of leaving
## a stale first shape. Physics, collisions and gameplay untouched.
func _apply_team_shape() -> void:
	var member_index := get_index()
	for child in get_children():
		var rect := child as ColorRect
		# Issue #178: the health bar background must stay a bar — converting
		# it drew a second body shape over each figure. The Shield bubble
		# (issue #170) is a gameplay overlay, not a body — never hidden.
		if rect != null and rect.name != "HealthBarBackground" \
				and rect.name != "Shield":
			rect.visible = false
			var visual_name := String(rect.name) + "Shape"
			var visual: Control = get_node_or_null(NodePath(visual_name))
			if visual == null:
				visual = load("res://scripts/ModularCharacterVisual.gd").new()
				visual.name = visual_name
				for anchor in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom"]:
					visual.set(anchor, rect.get(anchor))
				visual.position = rect.position
				visual.size = rect.size
				add_child(visual)
			if visual.has_method("apply_team_look"):
				visual.call("apply_team_look", team_color, team_shape,
					member_index)
			else:
				visual.set_shape(team_shape)
				visual.set_shape_color(team_color)
	# Issue #282: the body visual was appended AFTER the Weapon node,
	# so the held weapon/tool drew BEHIND the figure — keep the Weapon the
	# last child; it draws in front of every body visual.
	_keep_weapon_in_front()


## Issue #558: point the procedural animator at whichever child
## currently depicts the body — the authored ColorRect (square teams) or
## the modular character (every silhouette). Re-run after every
## shape change (apply_team_setup); the animator itself is created once.
func _attach_animator() -> void:
	var visual: Control = null
	for child in get_children():
		var ctrl := child as Control
		# FigurePose.is_body_child picks the body visuals (and collision
		# shapes — excluded here by the Control cast, the animator only
		# ever bends a visual).
		if ctrl != null and ctrl.visible and FigurePose.is_body_child(ctrl):
			visual = ctrl
			break
	if visual == null:
		return
	if _animator == null:
		_animator = CharacterAnimator.new()
		_animator.name = "CharacterAnimator"
		add_child(_animator)
	_animator.setup(self, visual)


## Issue #33: if no team member ended up controlled (fresh scene), the
## first one takes control.
func _claim_control_if_none() -> void:
	# Issue #521: never self-claim control on the enemy side — control is
	# handed over turn by turn (hot-seat).
	if team_side == "enemy":
		return
	for member in get_tree().get_nodes_in_group("player_team"):
		if member.get("controlled") == true:
			return
	set_controlled(true)


## Issue #33: switch input control to/from this member.
## Issue #63: zoom belongs to the player's VIEW, not to a character — every
## member uses the ONE shared team camera (group "player_camera"): the
## scene-authored one if present, otherwise one created on demand. The
## camera itself follows the controlled member (see ZoomCamera.gd).
func set_controlled(value: bool) -> void:
	controlled = value
	if _camera == null:
		for camera in get_tree().get_nodes_in_group("player_camera"):
			_camera = camera
			break
	if _camera == null:
		_camera = get_node_or_null("Camera") as Camera2D
		if _camera == null:
			_camera = load("res://scripts/ZoomCamera.gd").new()
			_camera.name = "Camera"
			add_child(_camera)
		if not _camera.is_in_group("player_camera"):
			_camera.add_to_group("player_camera")
	# Issue #534 rework: the shared camera stays ENABLED through every
	# control change. The old host toggle (`_camera.enabled = value`)
	# disabled the camera exactly when its hosting figure dropped
	# control — which happens at the start of every computer turn
	# (TurnController._begin_turn clears controlled figures of other
	# teams) — and a disabled Camera2D stops driving the viewport: the
	# camera NODE kept following the acting NPC (issue #534's first fix)
	# while the PICTURE froze on the human's figure for the whole
	# computer turn (owner: "camera still blocks time to time, especially
	# on the first turns" — the first turns are when the original host
	# figure is still alive to drop control; deaths reparent the camera
	# away, which masked the bug later in the match). The camera is
	# per-VIEW, not per-figure (issue #63): always on — following the
	# controlled member, the acting figure of a computer turn (#534), or
	# nobody between turns (the free spectator camera, issue #126).
	_camera.enabled = true


## Issue #252: attach the debug visuals (HP number, damage popup,
## centre-to-top arrow) — a no-op with the debug mode off.
func _build_debug_visuals() -> void:
	DebugInfo.attach(self)
	DebugInfo.update_hp(self, health, MAX_HEALTH)


## Issue #187: a dying CONTROLLED member must not keep control — the
## camera would follow the shrinking corpse and, until the node is
## freed, switch/input logic would still see it as the active character.
## Hand control and the view to the first living teammate immediately.
func _on_dying() -> void:
	if controlled:
		controlled = false
		var successor: Node = null
		for member in get_tree().get_nodes_in_group("player_team"):
			if is_instance_valid(member) and member != self \
					and member.has_method("set_controlled") \
					and (member.get("health") is int) and member.get("health") > 0:
				successor = member
				break
		if successor != null:
				successor.set_controlled(true)


## Issue #611: the PLAYER-side brain — the only place a human figure
## reads Input. Every decision becomes a Character API call (jump/move/
## aim); the shared tick (gravity frame, fall, move_and_slide) runs in
## the base around this hook.
func _control(delta: float) -> void:
	# Issue #244: while the handover waits for effects (after a shot or
	# when the turn timer ran out) the character is BLOCKED — no moving,
	# jumping or aiming until the next turn begins.
	if controlled and TurnController.is_player_team(TurnController.active_team) \
				and not TurnController.is_input_frozen():
		if Input.is_action_just_pressed("jump") and is_on_floor():
			jump()

		var direction := Input.get_axis("move_left", "move_right")
		# Issue #104: any move or aim action locks character switching for
		# the rest of the turn (N/P) — the player is committed to this member.
		var view_axis := Input.get_axis("view_down", "view_up")
		if direction != 0.0 or view_axis != 0.0 \
				or (Input.is_action_just_pressed("jump") and is_on_floor()):
			TurnController.notify_member_action()
		# Issue #250 rework / #518 rework: the walk follows the gravity
		# frame's tangent (the character's LOCAL +x) — Character.move().
		move(direction)
		# Issue #67: raise/lower the view with W/S / Arrow Up/Down.
		aim(view_axis * VIEW_SPEED * delta)
		# Issue #359: charging the railgun SHAKES the sight — a small random
		# wobble piles onto the view angle every tick while the charge builds
		# (Weapon.sight_shake), so a full charge is harder to aim precisely.
		var weapon := get_node_or_null("Weapon")
		if weapon != null and weapon.has_method("sight_shake"):
			var shake := float(weapon.sight_shake())
			if shake != 0.0:
				aim(shake)
	else:
		# Issue #316: a DRILLING wielder is the one frozen-input exception —
		# the aim keys (W/S) still steer the running jackhammer (the drill
		# direction follows the live aim, see Weapon._tick_jackhammer), and
		# the drill's velocity must survive the stand clamp below: Weapon
		# owns it until the drill ends. There is no cancel — the drill runs
		# its full aimed time or stalls against indestructible ground.
		var drill := get_node_or_null("Weapon")
		if controlled and TurnController.is_player_team(TurnController.active_team) \
					and drill != null and drill.has_method("is_drilling") \
					and drill.is_drilling():
			var steer := Input.get_axis("view_down", "view_up")
			if steer != 0.0:
				aim(steer * VIEW_SPEED * delta)
		else:
			# Issue #40/#58: uncontrolled team member just stays put (no glide
			# along the surface — only the component along gravity survives,
			# which on flat levels is exactly the old velocity.y).
			move(0.0)


## Issue #359: charging the railgun slows the wielder to half speed
## (Weapon.move_speed_factor) while F is held and the charge builds —
## the base's walking speed hook.
func _move_speed() -> float:
	var weapon := get_node_or_null("Weapon")
	var speed := float(SPEED)
	if weapon != null and weapon.has_method("move_speed_factor"):
		speed *= float(weapon.move_speed_factor())
	return speed
