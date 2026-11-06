class_name CharacterLines
extends Object
## Issue #335: characters speak comics-style lines near themselves.
##
## Every figure event that should make a character talk goes through
## here (both Player.gd and Npc.gd call in from the same spots, keeping
## the no-player/NPC-difference rule of issue #108):
##   - took damage .................. on_damage_taken — the victim cries
##                                      out (SHOUT balloon),
##   - took damage from an ally ..... on_damage_taken — the victim calls
##                                      out the betrayal (SHOUT),
##   - caused sufficient damage ..... on_damage_taken — a big hit makes
##                                      the ATTACKER gloat (SPEECH),
##   - left alone in the team ....... on_member_death — the last figure
##                                      standing speaks up (SPEECH),
##   - idle a long time ............. tick_idle — the active figure
##                                      muses to itself (THOUGHT).
## Every spoken line is also written to the action log (issue #335:
## "log has information of characters lines") and shown for three
## seconds near the figure (SpeechBubble.SHOW_TIME).

const Bubble := preload("res://scripts/SpeechBubble.gd")

## A hit this big makes the attacker gloat ("sufficient damage").
const BIG_DAMAGE := 25
## Seconds the active figure may do nothing before it muses a line.
const IDLE_TIME := 6.0
## Minimum pause between two lines of the SAME figure — a shotgun's
## pellets each call take_damage, and nobody talks over themselves.
const AGAIN := 1.2

const LINES_DAMAGE := [
	"Ouch!", "That hurts!", "Hey, watch it!", "Oof!",
	"Right in the corners!", "I felt that one...",
]
const LINES_ALLY := [
	"Traitor!", "Friendly fire!", "We're on the SAME team!",
	"Are you blind?!", "Whose side are you on?!",
]
const LINES_BOAST := [
	"Bullseye!", "Gotcha!", "Too easy!", "Right on target!",
	"That's gonna leave a mark!", "Nailed it!",
]
const LINES_IDLE := [
	"Boring...", "Any day now...", "What's the plan?",
	"Zzz...", "I could wait forever.", "Nice weather today.",
]
const LINES_ALONE := [
	"So it's just me now...", "For the team!",
	"You picked the wrong figure!", "I'll carry this.",
]

## figure -> engine seconds of its last line (AGAIN cooldown).
static var _last_line_at := {}
## Issue #335 idle tracking (tick_idle, driven by TurnController._process).
static var _idle_member: Node = null
static var _idle_seconds := 0.0
static var _idle_spoken := false


## Say `line` near `figure` in the given balloon kind, and log it.
static func say(figure: Node, line: String, bubble_kind: int) -> void:
	if figure == null or not is_instance_valid(figure):
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if _last_line_at.has(figure) and now - float(_last_line_at[figure]) < AGAIN:
		return
	_last_line_at[figure] = now
	Bubble.speak(figure, line, bubble_kind)
	DebugInfo.log("%s: \"%s\"" % [str(figure.get("display_name")), line])


## A figure took `amount` damage; `attacker` may be null (old callers)
## or the figure whose projectile exploded (Projectile/ProjectileBody
## pass their shooter). The victim reacts — betrayed by an ALLY or plain
## hurt — and a big enough hit by an ENEMY makes the attacker gloat.
static func on_damage_taken(victim: Node, amount: int, attacker: Node) -> void:
	if victim == null or not is_instance_valid(victim) or amount <= 0:
		return
	var from_ally := attacker != null and is_instance_valid(attacker) \
			and attacker != victim and _same_team(victim, attacker)
	var alive: bool = (victim.get("health") is int) and victim.get("health") > 0
	if alive:
		if from_ally:
			say(victim, LINES_ALLY.pick_random(), Bubble.Kind.SHOUT)
		else:
			say(victim, LINES_DAMAGE.pick_random(), Bubble.Kind.SHOUT)
	if attacker != null and is_instance_valid(attacker) \
			and attacker != victim and not from_ally and amount >= BIG_DAMAGE:
		say(attacker, LINES_BOAST.pick_random(), Bubble.Kind.SPEECH)


## A figure died — if it leaves exactly ONE teammate alive, that
## survivor is "left alone in the team" and speaks up.
static func on_member_death(dead: Node) -> void:
	if dead == null or not is_instance_valid(dead):
		return
	var survivors: Array = []
	for group in ["player_team", "enemy_team"]:
		for node in dead.get_tree().get_nodes_in_group(group):
			if node == dead or not is_instance_valid(node):
				continue
			var hp = node.get("health")
			if hp is int and hp > 0 and _same_team(dead, node):
				survivors.append(node)
	if survivors.size() == 1:
		say(survivors[0], LINES_ALONE.pick_random(), Bubble.Kind.SPEECH)


## Called every frame from TurnController._process: the figure whose
## turn it is accumulates idle time; standing around IDLE_TIME seconds
## without any action makes it muse a THOUGHT line (once per turn).
static func tick_idle(delta: float) -> void:
	var member: Node = TurnController.active_member
	if member == null or not is_instance_valid(member) \
			or TurnController.game_over or TurnController.is_input_frozen() \
			or TurnController.active_team == "":
		_idle_member = null
		_idle_seconds = 0.0
		_idle_spoken = false
		return
	if member != _idle_member:
		_idle_member = member
		_idle_seconds = 0.0
		_idle_spoken = false
	var hp = member.get("health")
	if not (hp is int) or hp <= 0 or _idle_spoken:
		return
	_idle_seconds += delta
	if _idle_seconds >= IDLE_TIME:
		_idle_spoken = true
		say(member, LINES_IDLE.pick_random(), Bubble.Kind.THOUGHT)


## The active figure moved, aimed or shot — its idle musings restart.
## Called from TurnController.notify_member_action/notify_shot.
static func note_action() -> void:
	_idle_seconds = 0.0
	_idle_spoken = false


## Same team: the player-team group, or (for AI teams) the same
## team_color — exactly how TurnController tells teams apart (#191).
static func _same_team(a: Node, b: Node) -> bool:
	var pa := a.is_in_group("player_team")
	var pb := b.is_in_group("player_team")
	if pa != pb:
		return false
	if pa:
		return true
	var ca = a.get("team_color")
	var cb = b.get("team_color")
	return ca is Color and cb is Color and ca == cb
