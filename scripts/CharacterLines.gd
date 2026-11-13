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
##
## Issue #524: every team speaks its own LANGUAGE — the team menu picks
## it per team (English, Spanish, Russian, French, Arabic), and a
## figure's language is resolved through its TEAM COLOR, exactly like
## TurnController tells teams apart. Each language carries the same
## five line sets; an unknown language or color falls back to English.

const Bubble := preload("res://scripts/SpeechBubble.gd")

## A hit this big makes the attacker gloat ("sufficient damage").
const BIG_DAMAGE := 25
## Seconds the active figure may do nothing before it muses a line.
const IDLE_TIME := 6.0
## Minimum pause between two lines of the SAME figure — a shotgun's
## pellets each call take_damage, and nobody talks over themselves.
const AGAIN := 1.2

const LINES := {
	"English": {
		"damage": [
			"Ouch!", "That hurts!", "Hey, watch it!", "Oof!",
			"Right in the corners!", "I felt that one...",
		],
		"ally": [
			"Traitor!", "Friendly fire!", "We're on the SAME team!",
			"Are you blind?!", "Whose side are you on?!",
		],
		"boast": [
			"Bullseye!", "Gotcha!", "Too easy!", "Right on target!",
			"That's gonna leave a mark!", "Nailed it!",
		],
		"idle": [
			"Boring...", "Any day now...", "What's the plan?",
			"Zzz...", "I could wait forever.", "Nice weather today.",
		],
		"alone": [
			"So it's just me now...", "For the team!",
			"You picked the wrong figure!", "I'll carry this.",
		],
	},
	"Spanish": {
		"damage": [
			"¡Ay!", "¡Eso duele!", "¡Oye, cuidado!", "¡Uf!",
			"¡Justo en las esquinas!", "¡Eso lo he sentido...",
		],
		"ally": [
			"¡Traidor!", "¡Fuego amigo!", "¡Estamos en el MISMO equipo!",
			"¿Estás ciego?!", "¡¿De qué lado estás?!",
		],
		"boast": [
			"¡En el blanco!", "¡Te pillé!", "¡Demasiado fácil!",
			"¡Justo en el objetivo!", "¡Eso va a dejar marca!", "¡Clavado!",
		],
		"idle": [
			"Qué aburrimiento...", "¿Nos vamos ya?", "¿Cuál es el plan?",
			"Zzz...", "Puedo esperar para siempre.", "Hace buen tiempo hoy.",
		],
		"alone": [
			"Así que solo quedo yo...", "¡Por el equipo!",
			"¡Elegiste a la figura equivocada!", "Yo cargo con esto.",
		],
	},
	"Russian": {
		"damage": [
			"Ай!", "Больно!", "Эй, аккуратнее!", "Уф!",
			"Прямо по углам!", "Это я почувствовал...",
		],
		"ally": [
			"Предатель!", "По своим бьёшь!", "Мы в ОДНОЙ команде!",
			"Ты слепой?!", "Ты вообще за кого?!",
		],
		"boast": [
			"В яблочко!", "Попался!", "Слишком легко!",
			"Точно в цель!", "Это ещё аукнется!", "В десятку!",
		],
		"idle": [
			"Скучно...", "Ну и сколько ждать?", "Какой план?",
			"Zzz...", "Могу ждать вечно.", "Погода сегодня хорошая.",
		],
		"alone": [
			"Значит, остался только я...", "За команду!",
			"Ты выбрал не ту фигуру!", "Я вытяну этот бой.",
		],
	},
	"French": {
		"damage": [
			"Aïe !", "Ça fait mal !", "Hé, fais attention !", "Ouf !",
			"En plein dans les coins !", "Celle-là, je l'ai sentie...",
		],
		"ally": [
			"Traître !", "Tir allié !", "On est dans la MÊME équipe !",
			"Tu es aveugle ?!", "Tu joues pour qui ?!",
		],
		"boast": [
			"En plein dans le mille !", "Je t'ai eu !", "Trop facile !",
			"Pile sur la cible !", "Ça va laisser une marque !", "Touché coulé !",
		],
		"idle": [
			"Quelle barbe...", "On y va quand tu veux...", "C'est quoi le plan ?",
			"Zzz...", "Je peux attendre éternellement.", "Beau temps aujourd'hui.",
		],
		"alone": [
			"Donc il ne reste que moi...", "Pour l'équipe !",
			"Tu as choisi la mauvaise figure !", "Je vais porter l'équipe.",
		],
	},
	"Arabic": {
		"damage": [
			"آي!", "هذا مؤلم!", "مهلاً، انتبه!", "أوف!",
			"في الزوايا تماماً!", "شعرت بهذه...",
		],
		"ally": [
			"خائن!", "نيران صديقة!", "نحن في الفريق نفسه!",
			"هل أنت أعمى؟!", "مع من أنت أصلاً؟!",
		],
		"boast": [
			"في الهدف تماماً!", "أمسكت بك!", "سهلة جداً!",
			"مباشرة في الهدف!", "هذه ستترك أثراً!", "إصابة قاتلة!",
		],
		"idle": [
			"ممل...", "متى نبدأ؟", "ما الخطة؟",
			"ززز...", "بإمكاني الانتظار للأبد.", "الجو جميل اليوم.",
		],
		"alone": [
			"إذن بقيت أنا وحدي...", "من أجل الفريق!",
			"اخترت الجندي الخطأ!", "سأحمل الفريق على كتفي.",
		],
	},
}

## The five line sets a language carries (see LINES): what a figure
## says per event — hurt, betrayed by an ally, gloating over a big hit,
## musing while idle, left alone in the team.
const KIND_DAMAGE := "damage"
const KIND_ALLY := "ally"
const KIND_BOAST := "boast"
const KIND_IDLE := "idle"
const KIND_ALONE := "alone"

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
			say(victim, _pick(victim, KIND_ALLY), Bubble.Kind.SHOUT)
		else:
			say(victim, _pick(victim, KIND_DAMAGE), Bubble.Kind.SHOUT)
	if attacker != null and is_instance_valid(attacker) \
			and attacker != victim and not from_ally and amount >= BIG_DAMAGE:
		say(attacker, _pick(attacker, KIND_BOAST), Bubble.Kind.SPEECH)


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
		say(survivors[0], _pick(survivors[0], KIND_ALONE), Bubble.Kind.SPEECH)


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
		say(member, _pick(member, KIND_IDLE), Bubble.Kind.THOUGHT)


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


## Issue #524: the language `figure` speaks — its team color's language
## (GameConfig maps colors to the configured teams, the same map
## TurnController uses). A figure without a team color speaks English.
static func _language(figure: Node) -> String:
	var color = figure.get("team_color")
	if color is Color:
		return GameConfig.team_language_for_color(color)
	return GameConfig.DEFAULT_LANGUAGE


## Issue #524: a random line of `kind` in `figure`'s team language.
static func _pick(figure: Node, kind: String) -> String:
	return _pick_in(_language(figure), kind)


## Issue #524: a random line of `kind` in `language`; an unknown
## language (or a language missing the kind) falls back to English.
static func _pick_in(language: String, kind: String) -> String:
	if not LINES.has(language) or not LINES[language].has(kind):
		language = GameConfig.DEFAULT_LANGUAGE
	return (LINES[language][kind] as Array).pick_random()
