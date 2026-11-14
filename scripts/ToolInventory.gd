extends Node
## Issue #170: TOOLS — inventory items that are not weapons: they do not
## deal damage but perform other tasks. Three tools exist, each usable
## ONCE PER TURN (per character):
##  1 Switch   — hand control to another team member. Issue #306
##     rework: the tool must be CHOSEN first (slot/key 5 ARMS it) —
##     only then do the N/P keys change the character, and the use is
##     spent when the change is COMMITTED by an action: another switch,
##     a move, an aim or a shot (the free #215 N/P shortcut is gone).
##  2 Teleport — the next left click in the level moves the member there
##  3 Shield   — the member blocks ONE attack (the block consumes the
##     shield, issue #255) until its next turn begins
##  4 Rock     — issue #227: lob a rock like a grenade; instead of
##     exploding it crumbles into destructible ground around where it
##     rests, clearing every figure and never covering indestructible
##     ground. Issue #234 rework: activating the tool no longer throws
##     instantly — the character TAKES THE ROCK IN HAND (held visual,
##     Weapon.gd) and throws it with the grenade's full aiming mechanics
##     (view aiming + hold-F charge); the quota is spent only when the
##     rock actually leaves the hand (rock_thrown).
##
## Issue #179: tools and weapons share ONE HUD panel — the slots are
## rendered by the WeaponInventory autoload (weapons in keys 1-4, tools
## in keys 5-8). This autoload keeps only the tool LOGIC and STATE:
## once-per-turn quota, teleport arming, shield application. Reset once
## per player turn by TurnController.

const TOOL_SWITCH := 0
const TOOL_TELEPORT := 1
const TOOL_SHIELD := 2
const TOOL_ROCK := 3
const TOOLS := ["Switch", "Teleport", "Shield", "Rock"]

## Issue #475 (godot-sound-work skill): the teleport hop sound —
## preloaded once, never loaded per teleport at runtime.
const TELEPORT_SOUND := preload("res://assets/audio/tools/teleport.wav")

## Tool armed for the next click (teleport) or for the N/P character
## change (switch, issue #306); the rock waits for the charged throw.
var armed_tool := -1

## Issue #475: teleport SFX player on the SFX bus. This autoload owns
## it — one player per sound category; teleports are sparse, so a
## single global player never overlaps itself.
var _teleport_player: AudioStreamPlayer

var _used: Dictionary = {}

func _ready() -> void:
	# Issue #475: build the teleport player once — the autoload persists
	# for the whole session, so the player does too.
	_teleport_player = AudioStreamPlayer.new()
	_teleport_player.stream = TELEPORT_SOUND
	_teleport_player.bus = "SFX"
	add_child(_teleport_player)


## Issue #475 (godot-sound-work skill): play the teleport hop. Public —
## Npc's teleport-away shortcut (issue #221) calls the same sound so
## every teleport in the game is audible. Random pitch 0.95–1.05:
## repeated hops in a row must not sound like a metronome.
func play_teleport_sound() -> void:
	if _teleport_player == null:
		return
	_teleport_player.pitch_scale = randf_range(0.95, 1.05)
	_teleport_player.play()

## Issue #306: one character change made with the armed Switch tool that
## has not been PAID yet — the use is spent by the first subsequent
## action (another switch, a move, an aim or a shot). _pending_from is
## the member that handed control away: IT spent its turn-action on the
## switch, so it pays the use and loses its own weapon right (#207) —
## the newly controlled member may still act.
var _pending_switch := false
var _pending_from: Node = null


## TurnController, start of a fresh player turn: full tool quota back.
func reset_turn() -> void:
	_used.clear()
	armed_tool = -1
	_pending_switch = false
	_pending_from = null
	refresh_slots()


func _can_use(character: Node, tool: int) -> bool:
	if character == null or _used.get(character, []).has(tool):
		return false
	# Issue #305: the TEAM's budget for this tool must have a use left.
	return WeaponInventory.can_spend_tool(TurnController.team_id_of(character), tool)


func _mark_used(character: Node, tool: int) -> void:
	if not _used.has(character):
		_used[character] = []
	_used[character].append(tool)
	# Issue #305: every successful tool use (switch, teleport, shield,
	# thrown rock) also spends one use of the TEAM's tool budget.
	WeaponInventory.spend_tool(TurnController.team_id_of(character), tool)


func is_switch_locked_by_move() -> bool:
	return TurnController.is_switch_locked()


## Issue #207: true when this character already spent a tool this turn —
## it may not fire a weapon either (tool OR weapon per character per
## turn, never both).
func has_used_tool(character: Node) -> bool:
	return character != null and not _used.get(character, []).is_empty()


## Use a tool with the currently controlled member. Returns true on success.
## Issue #306: TOOL_SWITCH no longer switches at once — it ARMS the
## tool (toggle); the character change happens with the N/P keys while
## armed and is paid when the change is committed (see _switch_member).
func use_tool(tool: int, direction := 1) -> bool:
	if not _is_in_level():
		return false
	if not TurnController.is_player_team(TurnController.active_team) or _switching_or_over():
		refresh_slots()
		return false
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		return false
	# Issue #207: this character already FIRED this turn — its tools are
	# locked for the rest of the turn (tool or weapon, never both).
	if WeaponInventory.is_locked_for(member):
		refresh_slots()
		return false
	if not _can_use(member, tool):
		refresh_slots()
		return false
	var done := false
	match tool:
		TOOL_SWITCH:
			# Issue #306: choosing the Switch tool ARMS it, like the teleport
			# or the rock — the change itself happens with the N/P keys while
			# armed, and the use is spent only when the change is committed
			# (another switch, a move, an aim or a shot).
			armed_tool = TOOL_SWITCH if armed_tool != TOOL_SWITCH else -1
			done = true
		TOOL_TELEPORT:
			# Arm the teleport: the next left click picks the destination.
			armed_tool = TOOL_TELEPORT if armed_tool != TOOL_TELEPORT else -1
			done = true
		TOOL_SHIELD:
			if member.has_method("set_shielded"):
				member.set_shielded(true)
				done = true
		TOOL_ROCK:
			# Issue #234: the rock is TAKEN IN HAND, not thrown instantly —
			# arm it like the teleport; the member aims (view keys) and
			# throws with the grenade's charged F mechanic (Weapon.gd).
			# The quota is spent in rock_thrown, when the rock leaves the
			# hand. Pressing the slot/key again puts the rock back.
			armed_tool = TOOL_ROCK if armed_tool != TOOL_ROCK else -1
			done = true
	if done and tool != TOOL_TELEPORT and tool != TOOL_ROCK \
			and tool != TOOL_SWITCH:
		_mark_used(member, tool)
		armed_tool = -1
	refresh_slots()
	return done


## Issue #234: called by Weapon once an armed rock was actually thrown —
## spends the thrower's rock quota and clears the armed state.
func rock_thrown(character: Node) -> void:
	if character != null:
		_mark_used(character, TOOL_ROCK)
	if armed_tool == TOOL_ROCK:
		armed_tool = -1
	refresh_slots()


## Issue #306: change the character with the armed Switch tool — the
## N/P handler below routes here. The guards mirror the old instant
## switch (#170/#215): only on the player turn, never after a move/aim
## action (#104), never after this member fired (#207), once per
## character per turn, within the team budget (#305).
func _switch_member(direction: int) -> void:
	if not _is_in_level():
		return
	if not TurnController.is_player_team(TurnController.active_team) \
			or _switching_or_over():
		refresh_slots()
		return
	if TurnController.is_switch_locked():
		refresh_slots()
		return
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		return
	if WeaponInventory.is_locked_for(member) \
			or not _can_use(member, TOOL_SWITCH):
		refresh_slots()
		return
	# Issue #306: a previous character change is committed by THIS
	# switch — its use is paid before the new change becomes pending
	# (the armed tool stays on for the change that follows).
	if _pending_switch:
		_commit_pending(true)
	# Issue #234: control moves to another member — an armed rock goes
	# back (quota unspent, nobody holds it anymore).
	if armed_tool == TOOL_ROCK:
		armed_tool = -1
	if direction < 0:
		TeamController.switch_prev()
	else:
		TeamController.switch_next()
	_pending_switch = true
	_pending_from = member
	refresh_slots()


## Issue #306: pay for one committed character change. keep_armed is
## true only inside the switch chain, where the next change follows at
## once and the tool must stay armed.
func _commit_pending(keep_armed := false) -> void:
	if not _pending_switch:
		return
	_pending_switch = false
	var from: Node = _pending_from
	_pending_from = null
	if not keep_armed and armed_tool == TOOL_SWITCH:
		armed_tool = -1
	if from != null and is_instance_valid(from):
		_mark_used(from, TOOL_SWITCH)


## Issue #306: the player acted — moved, aimed or shot — so a pending
## character change from the armed Switch tool is committed now and its
## use is spent ("if the player has changed the character then switch
## tool is decreased by one"). Called by TurnController.
func commit_switch() -> void:
	_commit_pending()
	refresh_slots()


func _switching_or_over() -> bool:
	return TurnController.game_over or TurnController.get("_switching") == true


func _is_in_level() -> bool:
	return get_tree().get_first_node_in_group("level") != null


## Issue #179: let the WeaponInventory panel ask whether tool use is
## currently possible (used to gray out the shared tool slots).
func can_use_now(tool: int) -> bool:
	if not _is_in_level():
		return false
	if not TurnController.is_player_team(TurnController.active_team) or _switching_or_over():
		return false
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member):
		return false
	# Issue #207: a character that fired this turn cannot use tools.
	if WeaponInventory.is_locked_for(member):
		return false
	return _can_use(member, tool)


func _unhandled_input(event: InputEvent) -> void:
	# Issue #306 rework: the N/P keys change the character only while the
	# Switch tool is CHOSEN (armed via slot/key 5) — without the tool
	# the keys do nothing; with it, the guards and economy of
	# _switch_member apply.
	if event.is_action_pressed("switch_next") \
			or event.is_action_pressed("switch_prev"):
		get_viewport().set_input_as_handled()
		if armed_tool == TOOL_SWITCH:
			_switch_member(-1 if event.is_action_pressed("switch_prev") else 1)
		return
	for i in TOOLS.size():
		if event.is_action_pressed("tool_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			use_tool(i)
			return
	# Armed teleport: the next left click inside a level is the destination.
	if armed_tool == TOOL_TELEPORT and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var member: Node = TurnController.active_member
		if member != null and is_instance_valid(member) and member is Node2D:
			# Issue #207: no teleporting away after firing — a character that
			# used its weapon this turn can't use a tool too. Disarm instead.
			if WeaponInventory.is_locked_for(member):
				armed_tool = -1
				refresh_slots()
				get_viewport().set_input_as_handled()
				return
			# Issue #305: the click re-checks the team's teleport budget.
			if not WeaponInventory.can_spend_tool(
					TurnController.team_id_of(member), TOOL_TELEPORT):
				armed_tool = -1
				refresh_slots()
				get_viewport().set_input_as_handled()
				return
			var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
			# Issue #328: a destination buried in the ground never happens
			# blindly — the click is resolved against the solid terrain: a
			# point in the open is used as-is, a point NEAR open space (less
			# than two character widths) snaps there, anything deeper is
			# IGNORED (no move, no spent use; the tool stays armed so the
			# player can simply click somewhere else).
			var teleporter := member as Node2D
			var destination: Variant = _resolve_teleport_destination(teleporter, world)
			if destination == null:
				refresh_slots()
				get_viewport().set_input_as_handled()
				return
			teleporter.global_position = destination
			member.velocity = Vector2.ZERO
			# Issue #518: a teleport is a DISCRETE jump, not a walk — the
			# destination must not inherit the old position's walking/aiming
			# frame (a figure leaving the bottom-right corner arc of Level4
			# kept a 180°-mirrored tangent under the floor: D walked LEFT).
			# Re-anchor the frame to the destination's gravity, screen-right.
			if member.has_method("reanchor_gravity_frame"):
				member.reanchor_gravity_frame()
			play_teleport_sound()
			_mark_used(member, TOOL_TELEPORT)
			armed_tool = -1
			refresh_slots()
			get_viewport().set_input_as_handled()


## Issue #179: ask the unified panel to redraw tool slot states.
func refresh_slots() -> void:
	if WeaponInventory != null and WeaponInventory.has_method("refresh_tools"):
		WeaponInventory.refresh_tools()


## Issue #328: resolve a clicked teleport destination against the solid
## terrain: the point itself when it is in the open, otherwise the NEAREST
## open spot within two character widths of the click ("near the open
## space then target should move there"), otherwise null — the click is
## buried too deep and the teleport is ignored.
func _resolve_teleport_destination(member: Node2D, target: Vector2) -> Variant:
	var space := member.get_world_2d().direct_space_state
	if _teleport_spot_free(space, target):
		return target
	# Ring search around the buried click: rings of 12 px out to two
	# character widths, samples spaced ~12 px apart on each ring — the
	# first free sample is the nearest open space to the clicked point.
	var max_snap := _character_width(member) * 2.0
	const RING_STEP := 12.0
	var ring := RING_STEP
	while ring <= max_snap:
		var samples := int(maxf(8.0, ceil(TAU * ring / RING_STEP)))
		for i in samples:
			var candidate := target \
					+ Vector2.from_angle(TAU * i / samples) * ring
			if _teleport_spot_free(space, candidate):
				return candidate
		ring += RING_STEP
	return null


## Issue #328: true when the point is clear of solid terrain (layer 1 =
## indestructible + destructible ground, IndestructibleGround.gd /
## DestructibleGround.gd). Characters are NOT probed — a teleport onto
## a figure is legal, the physics body slides out of the overlap (the
## same tolerance the NPC teleport uses, Npc.gd #221).
func _teleport_spot_free(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_point(query, 1).is_empty()


## Issue #328: the character's body width — how far a click buried in
## the ground may slide to reach open space ("less than two character's
## widths"). Read from the body's own collision shape when it has one,
## else the standard figure capsule (radius 24, Level*.tscn) → 48 px.
func _character_width(member: Node2D) -> float:
	for child in member.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var shape: Shape2D = shape_node.shape
		if shape is CapsuleShape2D:
			return (shape as CapsuleShape2D).radius * 2.0
		if shape is CircleShape2D:
			return (shape as CircleShape2D).radius * 2.0
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size.x
	return 48.0
