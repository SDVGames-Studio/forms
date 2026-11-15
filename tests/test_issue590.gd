extends Node
## Regression check for issue #590: an Arabic-speaking team's lines
## rendered as tofu symbol boxes — the engine's default fallback font
## ships no Arabic glyphs. Character-line text (speech balloons, the OSD
## action log) now draws through TextFonts.text_font(): the default font
## with Noto Naskh Arabic appended as a glyph fallback.
##
## Run headless: godot --headless res://tests/test_issue590.tscn
## Exit code 0 = pass.

func _ready() -> void:
	var ok := true

	var arabic_font: Font = load("res://assets/fonts/NotoNaskhArabic-Regular.ttf")
	if arabic_font == null:
		print("ISSUE590 font_missing")
		get_tree().quit(1)
		return

	# --- Every Arabic LETTER the lines use has a real glyph in Naskh
	# (no .notdef tofu): a nonzero advance per codepoint. Combining
	# marks (tanween U+064B..U+065F, superscript alef U+0670) legitimately
	# carry zero advance — they combine onto the letter before them.
	for kind in CharacterLines.LINES["Arabic"]:
		for line in CharacterLines.LINES["Arabic"][kind]:
			for i in line.length():
				var cp: int = line.unicode_at(i)
				var is_mark := (cp >= 0x064B and cp <= 0x065F) or cp == 0x0670
				if cp >= 0x0621 and cp <= 0x064A and not is_mark:
					if arabic_font.get_char_size(cp, 13).x <= 0.0:
						ok = false
						print("ISSUE590 no_glyph U+%04X in %s" % [cp, line])

	# --- The speech font really routes Arabic through the fallback
	# chain: a PURE Arabic string shaped with it must be exactly as wide
	# as shaped with Naskh alone. Mixed strings also pick punctuation
	# from the base font (correct — diagnostic print only).
	var pure := "خائنٌ هل"
	var with_fallback := TextFonts.text_font().get_string_size(pure, 13).x
	var naskh := arabic_font.get_string_size(pure, 13).x
	var mixed := "خائن! هل أنت أعمى؟!"
	var mixed_width := -1.0
	if ThemeDB.fallback_font != null:
		mixed_width = TextFonts.text_font().get_string_size(mixed, 13).x
	print("ISSUE590 widths fallback=", with_fallback,
			" naskh=", naskh, " mixed_diag=", mixed_width)
	if absf(with_fallback - naskh) > 0.75:
		ok = false
		print("ISSUE590 fallback_not_used")

	# --- A balloon with an Arabic line sets up and measures sanely.
	var bubble := SpeechBubble.new()
	bubble.kind = SpeechBubble.Kind.SHOUT
	add_child(bubble)
	bubble._setup("نيران صديقة!")
	if bubble.size.x <= PADDING_WITNESS or bubble.size.y <= 0.0:
		ok = false
		print("ISSUE590 bubble_size_bad ", bubble.size)
	bubble.queue_free()

	print("ISSUE590 ok=", ok)
	get_tree().quit(0 if ok else 1)


## The balloon pads its box around the text (see SpeechBubble.PADDING);
## any real line must come out wider than one padding strip.
const PADDING_WITNESS := 24.0
