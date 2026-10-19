class_name UiTheme
extends RefCounted
## The game's look: Kurale for headings and buttons, Alegreya Sans for text,
## framed panels and wooden buttons from the art (ids "ui/..." in
## client/art/art.json; see docs/art-style.md). Without the art the plain
## flat styles stand in. Set on the root window at start-up.

const TEXT := Color("#f3e9d2")
const MUTED := Color("#b8ae9c")
const GOLD := Color("#f0cf7a")
const INK := Color("#2b2118")
const HEADING_FONT := "res://ui/fonts/Kurale-Regular.ttf"
const BODY_FONT := "res://ui/fonts/AlegreyaSans-Medium.ttf"
const BOLD_FONT := "res://ui/fonts/AlegreyaSans-Bold.ttf"


## Merges the look into the project theme (ui/theme.tres), which every
## control falls back to, under any CanvasLayer too.
static func apply() -> void:
	var project := ThemeDB.get_project_theme()
	if project != null:
		project.merge_with(build())


static func build() -> Theme:
	var theme := Theme.new()
	var body := _font(BODY_FONT)
	var heading := _font(HEADING_FONT)
	theme.default_font = body
	theme.default_font_size = 30
	theme.set_color("font_color", "Label", TEXT)

	theme.set_type_variation("Heading", "Label")
	theme.set_font("font", "Heading", heading)
	theme.set_color("font_color", "Heading", GOLD)
	theme.set_color("font_outline_color", "Heading", INK)
	theme.set_constant("outline_size", "Heading", 6)

	theme.set_type_variation("Strong", "Label")
	theme.set_font("font", "Strong", _font(BOLD_FONT))

	theme.set_stylebox("panel", "PanelContainer", frame("ui/panel", 96, 24, 22, Color(0.13, 0.11, 0.09, 0.92)))
	theme.set_stylebox("panel", "PopupMenu", frame("ui/panel", 96, 24, 16, Color(0.13, 0.11, 0.09)))

	for type in ["Button", "OptionButton"]:
		theme.set_font("font", type, heading)
		theme.set_stylebox("normal", type, frame("ui/button", 64, 16, 14, Color("#8b5a2b")))
		theme.set_stylebox("hover", type, frame("ui/button_hover", 64, 16, 14, Color("#a06a37")))
		theme.set_stylebox("pressed", type, frame("ui/button_pressed", 64, 16, 14, Color("#6f4622")))
		theme.set_stylebox("hover_pressed", type, frame("ui/button_pressed", 64, 16, 14, Color("#6f4622")))
		theme.set_stylebox("disabled", type, frame("ui/button_disabled", 64, 16, 14, Color("#5b5048")))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			theme.set_color(state, type, TEXT)
		theme.set_color("font_disabled_color", type, MUTED)
		theme.set_color("font_outline_color", type, INK)
		theme.set_constant("outline_size", type, 6)
		theme.set_constant("h_separation", type, 10)
		theme.set_constant("icon_max_width", type, 44)

	# The open tab of a row of tabs: a disabled button trimmed in gold.
	theme.set_type_variation("TabButton", "Button")
	theme.set_stylebox("disabled", "TabButton", frame("ui/button_selected", 64, 16, 14, Color("#2a221b")))
	theme.set_color("font_disabled_color", "TabButton", GOLD)
	theme.set_constant("icon_max_width", "TabButton", 52)

	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, frame("ui/field", 48, 12, 16, Color("#1d1712")))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_placeholder_color", type, MUTED)
		theme.set_color("caret_color", type, GOLD)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color("#8b5a2b")
	grabber.set_corner_radius_all(6)
	grabber.content_margin_left = 6
	grabber.content_margin_right = 6
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	var grabber_hot := grabber.duplicate()
	grabber_hot.bg_color = Color("#c9a13f")
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.25)
	track.set_corner_radius_all(6)
	track.content_margin_left = 6
	track.content_margin_right = 6
	theme.set_stylebox("scroll", "VScrollBar", track)
	return theme


## A font that falls back to Godot's own for the few signs it lacks (→).
static func _font(path: String) -> Font:
	var font := load(path) as FontFile
	if font == null:
		return ThemeDB.fallback_font
	font.fallbacks = [ThemeDB.fallback_font]
	return font


## A frame from the art, or a flat rounded box of `color` without it.
## `design` is the art's size, `margin` its corner size, `content` the padding.
static func frame(id: String, design: float, margin: float, content: float, color: Color) -> StyleBox:
	var texture := Art.texture(id)
	if texture != null:
		return FrameStyle.new(texture, Vector2(design, design), margin, content)
	var flat := StyleBoxFlat.new()
	flat.bg_color = color
	flat.set_corner_radius_all(12)
	flat.set_content_margin_all(content)
	return flat
