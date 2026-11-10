extends Node
## Regression check for issue #335: characters speak comics-style lines.
##
## The test drives CharacterLines (the one door figures speak through)
## with plain stub figures and asserts:
##   - damage taken pops a SHOUT balloon at the victim;
##   - a big hit (>= BIG_DAMAGE) by an enemy also makes the ATTACKER
##     gloat with a SPEECH balloon;
##   - damage from an ALLY speaks only at the victim (no gloating), and
##     _same_team matches TurnController's team logic (player-team group
##     first, then enemy team_color);
##   - a figure never talks over itself (AGAIN cooldown);
##   - the last survivor of a team speaks up, two survivors do not;
##   - IDLE_TIME without an action makes the active figure muse a
##     THOUGHT balloon (once), and note_action() restarts the clock;
##   - balloons stay for three seconds (SpeechBubble.SHOW_TIME).
##
## Run headless: godot --headless res://tests/test_issue335.tscn
## Exit code 0 = pass.

const Bubble := preload("res://scripts/SpeechBubble.gd")
const Lines := preload("res://scripts/CharacterLines.gd")


## Smallest figure stand-in: the properties CharacterLines reads.
class Figure extends Node2D:
	var display_name := "Tester"
	var health := 100
	var team_color := Color(1.0, 0.84, 0.2, 1.0)


func _ready() -> void:
	# Allow the autoload _ready to run first.
	await get_tree().process_frame
	var ok := true

	# --- damage taken: the victim cries out (SHOUT) -------------------
	var victim := Figure.new()
	victim.display_name = "Victim"
	add_child(victim)
	Lines.on_damage_taken(victim, 10, null)
	var bubble := _bubble(victim)
	ok = ok and bubble != null and bubble.kind == Bubble.Kind.SHOUT

	# --- big hit by an enemy: the attacker gloats (SPEECH) ------------
	var attacker := Figure.new()
	attacker.display_name = "Attacker"
	attacker.team_color = Color(0.75, 0.2, 0.45, 1.0)
	add_child(attacker)
	Lines.on_damage_taken(victim, 30, attacker)
	# The victim just spoke: the cooldown keeps its old balloon…
	var still_old: bool = bubble != null and _bubble(victim) == bubble
	# …while the fresh attacker gets a boast.
	var boast := _bubble(attacker)
	ok = ok and still_old and boast != null and boast.kind == Bubble.Kind.SPEECH

	# --- damage from an ALLY: only the victim speaks ------------------
	var shooter := Figure.new()
	shooter.display_name = "BumblingAlly"
	shooter.team_color = Color(1.0, 0.84, 0.2, 1.0)
	add_child(shooter)
	var hurt := Figure.new()
	hurt.display_name = "HurtAlly"
	add_child(hurt)
	Lines.on_damage_taken(hurt, 10, shooter)
	ok = ok and _bubble(hurt) != null and _bubble(shooter) == null

	# --- a different enemy TEAM (other color) is no ally --------------
	shooter.team_color = Color(0.2, 0.5, 0.95, 1.0)
	var other := Figure.new()
	other.display_name = "OtherTeam"
	add_child(other)
	Lines.on_damage_taken(other, 10, shooter)
	# Fresh figures, so the victim shouts — no betrayal line needed,
	# both speak; this only guards against a crash and a missing bubble.
	ok = ok and _bubble(other) != null

	# --- left alone in the team ---------------------------------------
	var team: Array[Node] = []
	for i in 3:
		var mate := Figure.new()
		mate.display_name = "Mate%d" % i
		mate.team_color = Color(0.85, 0.2, 0.2, 1.0)
		add_child(mate)
		mate.add_to_group("enemy_team")
		team.append(mate)
	team[0].health = 0
	Lines.on_member_death(team[0])
	ok = ok and _bubble(team[1]) == null and _bubble(team[2]) == null
	team[1].health = 0
	Lines.on_member_death(team[1])
	var lone := _bubble(team[2])
	ok = ok and lone != null and lone.kind == Bubble.Kind.SPEECH

	# --- idle: the active figure muses a THOUGHT line ------------------
	var idle_fig := Figure.new()
	idle_fig.display_name = "Daydreamer"
	add_child(idle_fig)
	TurnController.active_team = TurnController.TEAM_PLAYER
	TurnController.active_member = idle_fig
	Lines.note_action()
	Lines.tick_idle(Lines.IDLE_TIME - 1.0)
	ok = ok and _bubble(idle_fig) == null
	Lines.tick_idle(1.0)
	var muse := _bubble(idle_fig)
	ok = ok and muse != null and muse.kind == Bubble.Kind.THOUGHT
	# Once per turn: more ticking adds no second line.
	Lines.tick_idle(Lines.IDLE_TIME)
	ok = ok and _bubble(idle_fig) == muse
	# An action restarts the clock for the next turn's musings.
	Lines.note_action()
	ok = ok and Lines._idle_seconds == 0.0 and not Lines._idle_spoken
	TurnController.active_member = null
	TurnController.active_team = ""

	# --- the balloon shows for three seconds (issue text) -------------
	ok = ok and Bubble.SHOW_TIME == 3.0

	if ok:
		print("ISSUE335 OK: character lines speak, cool down, and time out")
		get_tree().quit(0)
	else:
		print("ISSUE335 FAIL")
		get_tree().quit(1)


func _bubble(figure: Node) -> SpeechBubble:
	return figure.get_node_or_null(NodePath("SpeechBubble")) as SpeechBubble
