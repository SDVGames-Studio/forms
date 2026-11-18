class_name TextFonts
extends Object
## Issue #590: an Arabic-speaking team's lines rendered as tofu symbol
## boxes — the engine's default font ships no Arabic glyphs. This is the
## font character-line surfaces draw through: the engine default itself
## with Noto Naskh Arabic appended as a glyph fallback, so Latin text
## looks exactly as before while Arabic (and mixed) lines shape real
## glyphs through the fallback chain. Speech balloons size and draw
## their text with it, and the OSD action log label uses it too.

## The Arabic team-language font (bundled, SIL OFL — see the license
## file next to it). Naskh is the traditional Arabic body-text style
## and stays legible at the balloons' small font size.
const ARABIC := preload("res://assets/fonts/NotoNaskhArabic-Regular.ttf")

## Whether the default font's fallback was appended (done once).
static var _patched := false


## The font character lines are drawn with (see class comment). The
## default font is a FontFile in Godot 4.7 and carries `fallbacks`;
## appending a face only adds glyphs the default lacks, so existing
## Latin/Greek/Cyrillic rendering is untouched.
static func text_font() -> Font:
	if not _patched:
		var fallbacks: Array[Font] = [ARABIC]
		var default_font := ThemeDB.fallback_font as FontFile
		if default_font != null:
			default_font.fallbacks = fallbacks
		_patched = true
	return ThemeDB.fallback_font
