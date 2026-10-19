class_name UiTheme
extends RefCounted
## The game's look, in the manner of modern grand strategy games: dark slate
## glass panels with a thin bronze trim and a soft shadow, flat buttons with
## a gold primary, underlined tabs, Cinzel for headings and Inter for text
## (docs/art-style.md). All vector styles, sharp at any scale; a panel or
## button drawn as art ("ui/panel", "ui/button"... in client/art/art.json)
## replaces its style. Merged into the project theme at start-up.

const TEXT := Color("#e9e4d8")
const MUTED := Color("#9aa3ad")
const GOLD := Color("#e3c27a")
const BRONZE := Color("#b8914f")
const INK := Color("#14110c")
const PANEL := Color("#141920")
const RAISED := Color("#1f2630")
const LINE := Color("#3a4552")
const DANGER := Color("#e07a62")
const HEADING_FONT := "res://ui/fonts/Cinzel-SemiBold.ttf"
const TITLE_FONT := "res://ui/fonts/Cinzel-Bold.ttf"
const BODY_FONT := "res://ui/fonts/Inter-Regular.otf"
const MEDIUM_FONT := "res://ui/fonts/Inter-Medium.otf"
const STRONG_FONT := "res://ui/fonts/Inter-SemiBold.otf"


## Merges the look into the project theme (ui/theme.tres), which every
## control falls back to, under any CanvasLayer too.
static func apply() -> void:
	var project := ThemeDB.get_project_theme()
	if project != null:
		project.merge_with(build())


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = _font(BODY_FONT)
	theme.default_font_size = 27
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_type_variation("Heading", "Label")
	theme.set_font("font", "Heading", _spaced(HEADING_FONT, 1))
	theme.set_color("font_color", "Heading", GOLD)
	theme.set_color("font_shadow_color", "Heading", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_y", "Heading", 2)

	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", _spaced(TITLE_FONT, 3))
	theme.set_color("font_color", "Title", GOLD)
	theme.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.7))
	theme.set_constant("shadow_offset_y", "Title", 3)

	theme.set_type_variation("Strong", "Label")
	theme.set_font("font", "Strong", _font(STRONG_FONT))

	theme.set_stylebox("panel", "PanelContainer", frame("ui/panel", 96, 24, 22, panel_style()))
	theme.set_stylebox("panel", "PopupMenu", frame("ui/panel", 96, 24, 16, panel_style(14)))
	theme.set_stylebox("panel", "TooltipPanel", panel_style(10))
	theme.set_color("font_color", "TooltipLabel", TEXT)

	for type in ["Button", "OptionButton"]:
		theme.set_font("font", type, _font(STRONG_FONT))
		theme.set_font_size("font_size", type, 26)
		theme.set_stylebox("normal", type, frame("ui/button", 64, 16, 14, _box(RAISED, LINE)))
		theme.set_stylebox("hover", type, frame("ui/button_hover", 64, 16, 14, _box(RAISED.lightened(0.08), BRONZE)))
		theme.set_stylebox("pressed", type, frame("ui/button_pressed", 64, 16, 14, _box(PANEL, GOLD)))
		theme.set_stylebox("hover_pressed", type, frame("ui/button_pressed", 64, 16, 14, _box(PANEL, GOLD)))
		theme.set_stylebox("disabled", type, frame("ui/button_disabled", 64, 16, 14, _box(Color(RAISED, 0.5), Color(LINE, 0.5))))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_focus_color"]:
			theme.set_color(state, type, TEXT)
		theme.set_color("font_pressed_color", type, GOLD)
		theme.set_color("font_hover_pressed_color", type, GOLD)
		theme.set_color("font_disabled_color", type, Color(MUTED, 0.7))
		theme.set_color("icon_normal_color", type, TEXT)
		theme.set_color("icon_hover_color", type, GOLD)
		theme.set_color("icon_pressed_color", type, GOLD)
		theme.set_color("icon_disabled_color", type, Color(MUTED, 0.5))
		theme.set_constant("h_separation", type, 12)
		theme.set_constant("icon_max_width", type, 36)

	# The main action of a panel: gold, dark lettering.
	theme.set_type_variation("Primary", "Button")
	theme.set_stylebox("normal", "Primary", _box(BRONZE, GOLD))
	theme.set_stylebox("hover", "Primary", _box(BRONZE.lightened(0.12), GOLD.lightened(0.2)))
	theme.set_stylebox("pressed", "Primary", _box(BRONZE.darkened(0.15), GOLD))
	theme.set_stylebox("hover_pressed", "Primary", _box(BRONZE.darkened(0.15), GOLD))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Primary", INK)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		theme.set_color(state, "Primary", INK)

	# A row of tabs: quiet until open, then underlined in gold.
	theme.set_type_variation("TabButton", "Button")
	var tab := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	theme.set_stylebox("normal", "TabButton", tab)
	var tab_hover := _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0))
	theme.set_stylebox("hover", "TabButton", tab_hover)
	theme.set_stylebox("pressed", "TabButton", tab_hover)
	var open := _box(Color(1, 1, 1, 0.06), GOLD)
	open.set_border_width_all(0)
	open.border_width_bottom = 3
	theme.set_stylebox("disabled", "TabButton", frame("ui/button_selected", 64, 16, 14, open))
	theme.set_color("font_color", "TabButton", MUTED)
	theme.set_color("icon_normal_color", "TabButton", MUTED)
	theme.set_color("font_disabled_color", "TabButton", GOLD)
	theme.set_color("icon_disabled_color", "TabButton", GOLD)
	theme.set_constant("icon_max_width", "TabButton", 44)

	# Icon-only buttons on the top bar: no box until touched.
	theme.set_type_variation("IconButton", "Button")
	theme.set_stylebox("normal", "IconButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", "IconButton", _box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0)))
	theme.set_stylebox("pressed", "IconButton", _box(Color(1, 1, 1, 0.1), GOLD))

	for type in ["LineEdit", "TextEdit"]:
		var field := _box(Color("#0e1217"), LINE)
		field.set_content_margin_all(16)
		theme.set_stylebox("normal", type, frame("ui/field", 48, 12, 16, field))
		var focused := field.duplicate()
		focused.border_color = BRONZE
		theme.set_stylebox("focus", type, focused)
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_placeholder_color", type, Color(MUTED, 0.7))
		theme.set_color("caret_color", type, GOLD)
		theme.set_font("font", type, _font(MEDIUM_FONT))

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = LINE
	grabber.set_corner_radius_all(4)
	grabber.content_margin_left = 4
	grabber.content_margin_right = 4
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	var grabber_hot := grabber.duplicate()
	grabber_hot.bg_color = BRONZE
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.2)
	track.set_corner_radius_all(4)
	track.content_margin_left = 4
	track.content_margin_right = 4
	theme.set_stylebox("scroll", "VScrollBar", track)
	return theme


## Dark slate glass with a bronze trim, brighter along the top, and a soft
## shadow under it.
static func panel_style(padding := 22, alpha := 0.94) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, alpha)
	style.border_color = Color(BRONZE, 0.55)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 4)
	style.set_content_margin_all(padding)
	style.anti_aliasing = true
	return style


## A frame from the art (FrameStyle) when there is one, else `flat`.
## `design` is the art's size, `margin` its corner size, `content` the
## padding.
static func frame(id: String, design: float, margin: float, content: float, flat: StyleBox) -> StyleBox:
	var texture := Art.texture(id)
	if texture != null:
		return FrameStyle.new(texture, Vector2(design, design), margin, content)
	return flat


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.anti_aliasing = true
	return style


## A font that falls back to Godot's own for the few signs it lacks.
static func _font(path: String) -> Font:
	var font := load(path) as FontFile
	if font == null:
		return ThemeDB.fallback_font
	font.fallbacks = [ThemeDB.fallback_font]
	return font


## Roman capitals read better a little apart.
static func _spaced(path: String, spacing: int) -> Font:
	var variation := FontVariation.new()
	variation.base_font = _font(path)
	variation.spacing_glyph = spacing
	return variation
