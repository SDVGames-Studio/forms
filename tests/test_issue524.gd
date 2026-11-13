extends Node
## Issue #524 regression: every team has a language, and its teammates'
## spoken lines depend on it.
##
## - GameConfig.LANGUAGES is exactly the ordered set from the issue
##   (English, Spanish, Russian, French, Arabic) with English default;
##   default and freshly added teams speak English.
## - team_language_for_color maps a figure's team color to its team's
##   language; unknown colors speak English (same fallback as the
##   controller map).
## - _sanitize_teams keeps a supported language and falls back to
##   English for missing/unsupported values (old team.cfg files).
## - CharacterLines carries all five line sets (damage/ally/boast/idle/
##   alone) for every language, all non-empty and actually translated
##   (each set differs from English); _pick_in samples within the right
##   language and falls back to English.
## - End to end: a victim whose team speaks Spanish shouts a SPANISH
##   damage line; the team menu shows a language picker per team that
##   reads and writes the team's language.
##
## Run headless: godot --headless res://tests/test_issue524.tscn
## Exit code 0 = pass; the printed ISSUE524 ok= verdict is authoritative.

const Lines := preload("res://scripts/CharacterLines.gd")
const Bubble := preload("res://scripts/SpeechBubble.gd")

const KINDS := ["damage", "ally", "boast", "idle", "alone"]


## Smallest figure stand-in: the properties CharacterLines reads.
class Figure extends Node2D:
	var display_name := "Tester"
	var health := 100
	var team_color := Color(1.0, 0.84, 0.2, 1.0)


func _ready() -> void:
	# Allow the autoload _ready to run first.
	await get_tree().process_frame
	var failures: Array[String] = []

	# --- The language set from the issue, English default. -----------
	if GameConfig.LANGUAGES != ["English", "Spanish", "Russian", "French", "Arabic"]:
		failures.append("LANGUAGES must be the issue's five, got %s" % str(GameConfig.LANGUAGES))
	if GameConfig.DEFAULT_LANGUAGE != "English":
		failures.append("default language must be English")

	# --- Default teams and every newly added one speak English. ------
	GameConfig.teams = GameConfig.default_teams()
	for i in GameConfig.teams.size():
		if str(GameConfig.teams[i].get("language", "")) != "English":
			failures.append("default team %d must speak English" % i)
	var fresh: Dictionary = GameConfig._sanitize_teams([
		{"label": "T", "color": Color(0.3, 0.8, 0.4), "shape": "circle",
				"names": ["A"], "skill": 5, "friendly_fire": 0}])[0]
	if str(fresh.get("language", "")) != "English":
		failures.append("a team without a language must default to English")

	# --- A figure's team color finds its team's language. ------------
	GameConfig.teams = [
		{"label": "A", "color": Color(1.0, 0.84, 0.2, 1.0), "shape": "square",
				"names": ["A1"], "skill": 5, "friendly_fire": 0,
				"language": "English", "controller": "player"},
		{"label": "B", "color": Color(0.75, 0.2, 0.45, 1.0), "shape": "circle",
				"names": ["B1"], "skill": 5, "friendly_fire": 0,
				"language": "Russian", "controller": "computer"},
	]
	if GameConfig.team_language_for_color(Color(0.75, 0.2, 0.45, 1.0)) != "Russian":
		failures.append("team color must resolve to its team's language")
	if GameConfig.team_language_for_color(Color(0.1, 0.1, 0.1, 1.0)) != "English":
		failures.append("unknown colors must fall back to English")

	# --- Sanitising: supported kept, garbage falls back to English. --
	var kept: Dictionary = GameConfig._sanitize_teams([
		{"label": "T", "color": Color(0.3, 0.8, 0.4), "shape": "circle",
				"names": ["A"], "skill": 5, "friendly_fire": 0,
				"language": "French"}])[0]
	if str(kept.get("language", "")) != "French":
		failures.append("a supported language must survive sanitising")
	var junk: Dictionary = GameConfig._sanitize_teams([
		{"label": "T", "color": Color(0.3, 0.8, 0.4), "shape": "circle",
				"names": ["A"], "skill": 5, "friendly_fire": 0,
				"language": "Klingon"}])[0]
	if str(junk.get("language", "")) != "English":
		failures.append("an unsupported language must fall back to English")

	# --- Every language carries all five non-empty line sets. -------
	var english: Dictionary = Lines.LINES["English"]
	for language in GameConfig.LANGUAGES:
		if not Lines.LINES.has(language):
			failures.append("no line set for language %s" % language)
			continue
		var table: Dictionary = Lines.LINES[language]
		for kind in KINDS:
			var lines: Array = table.get(kind, [])
			if lines.is_empty():
				failures.append("%s has no %s lines" % [language, kind])
			# Sampling stays inside the language's own set.
			for i in 12:
				if not lines.has(Lines._pick_in(language, kind)):
					failures.append("%s %s picked outside its own set" % [language, kind])
					break
			# Really translated, not an English copy (English itself is the base).
			if language != "English" and lines == english.get(kind, []):
				failures.append("%s %s lines equal the English set" % [language, kind])
	# Unknown language (and a figure without a color) speaks English.
	var mute := Node2D.new()
	if Lines._language(mute) != "English":
		failures.append("a figure without team color must default to English")
	var colored := Figure.new()
	colored.team_color = Color(0.75, 0.2, 0.45, 1.0)
	if Lines._language(colored) != "Russian":
		failures.append("a figure's color must resolve to the team's language")

	# --- End to end: a Spanish victim shouts a Spanish line. ---------
	GameConfig.teams[0]["language"] = "Spanish"
	var victim := Figure.new()
	victim.display_name = "Victim"
	add_child(victim)
	Lines.on_damage_taken(victim, 10, null)
	var balloon: SpeechBubble = victim.get_node_or_null(NodePath("SpeechBubble"))
	if balloon == null or balloon.kind != Bubble.Kind.SHOUT:
		failures.append("damage taken must pop a SHOUT balloon")
	elif not (Lines.LINES["Spanish"]["damage"] as Array).has(balloon._line):
		failures.append("victim must shout a Spanish damage line, got %s" % balloon._line)

	# --- The team menu edits the language per team. ------------------
	DirAccess.remove_absolute("user://team.cfg")  # start from defaults
	GameConfig.teams = []
	var menu: Control = load("res://TeamMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var language_select: OptionButton = menu.get_node("%LanguageSelect")
	if language_select == null:
		failures.append("team menu must have a language picker")
	else:
		if language_select.item_count != GameConfig.LANGUAGES.size():
			failures.append("language picker must list every language")
		elif language_selected_text(language_select) != "English":
			failures.append("default teams start on English in the picker")
		# Picking a language writes it into the edited team.
		language_select.select(GameConfig.LANGUAGES.find("French"))
		language_select.item_selected.emit(GameConfig.LANGUAGES.find("French"))
		if str(GameConfig.teams[0].get("language", "")) != "French":
			failures.append("picker choice must set the team's language")
		# Switching teams re-reads THEIR language.
		GameConfig.teams[1]["language"] = "Arabic"
		var team_select: OptionButton = menu.get_node("%TeamSelect")
		team_select.select(1)
		team_select.item_selected.emit(1)
		await get_tree().process_frame
		if language_selected_text(language_select) != "Arabic":
			failures.append("picker must show the edited team's language")
	menu.queue_free()

	# Restore defaults so the run leaves nothing behind.
	DirAccess.remove_absolute("user://team.cfg")
	GameConfig.teams = GameConfig.default_teams()

	if failures.is_empty():
		print("ISSUE524 ok=1")
		get_tree().quit(0)
	else:
		for why in failures:
			print("ISSUE524 ok=0 — %s" % why)
		get_tree().quit(1)


func language_selected_text(select: OptionButton) -> String:
	return select.get_item_text(maxi(0, select.selected))
