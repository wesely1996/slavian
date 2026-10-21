class_name UiTheme
extends RefCounted
## The game's look (docs/art-style.md, "Interface"): the map is the hero and
## the chrome sits at its edges, as dark wood (the top band) and unbleached
## flax (the sheets) with ink lettering, sentence case. Colour carries side:
## malachite is ours and the main action, madder the hordes and danger,
## wheat resources and levels. The one ornament is the embroidered band
## under the top band (Rushnyk). PT Sans for text, Old Standard for
## headings, Ruslan Display for the name of the game alone; all three cover
## Serbian Latin and Cyrillic. Vector styles, sharp at any scale; a panel or
## button drawn as art ("ui/panel", "ui/button"... in client/art/art.json)
## replaces its style. Merged into the project theme at start-up.

const WOOD := Color("#2b211b")
const WOOD_DEEP := Color("#1d1612")
const FLAX := Color("#e4dfd2")
const FLAX_DEEP := Color("#d5cdbb")
const PAGE := Color("#f1ede3")
const INK := Color("#2a221c")
const MUTED := Color("#6b5f52")
const MADDER := Color("#a8322b")
const MALACHITE := Color("#2f6e55")
const WHEAT := Color("#9a7424")
## Lettering on the wood.
const ON_WOOD := Color("#ece6d8")
const ON_WOOD_MUTED := Color("#b5a994")
## Older names, kept for the screens that use them.
const TEXT := INK
const GOLD := WHEAT
const DANGER := MADDER
const LINE := Color(0.165, 0.133, 0.11, 0.22)

const LOGO_FONT := "res://ui/fonts/RuslanDisplay-Regular.ttf"
const HEADING_FONT := "res://ui/fonts/OldStandard-Bold.ttf"
const TITLE_FONT := HEADING_FONT
const BODY_FONT := "res://ui/fonts/PTSans-Regular.ttf"
const MEDIUM_FONT := BODY_FONT
const STRONG_FONT := "res://ui/fonts/PTSans-Bold.ttf"

## Text size for accessibility (M5 15): small, normal or large. The scale
## multiplies every font size; set at start-up from Session.
static var text_scale := 1.0

const TEXT_SIZES := {"small": 0.85, "normal": 1.0, "large": 1.2}


static func set_text_size(size: String) -> void:
	text_scale = TEXT_SIZES.get(size, 1.0)


## Merges the look into the project theme (ui/theme.tres), which every
## control falls back to, under any CanvasLayer too.
static func apply() -> void:
	var project := ThemeDB.get_project_theme()
	if project != null:
		project.merge_with(build())


## The screen's design size, by orientation: phones are laid out on
## 720×1280, landscape screens on 1600×1100 (the same sizes then read about
## as large on a desktop as on a phone, instead of shrinking to 70%).
const PORTRAIT_SIZE := Vector2i(720, 1280)
const LANDSCAPE_SIZE := Vector2i(1600, 1100)


## Picks the design size for the window's shape; call on resize.
static func fit(window: Window) -> void:
	var landscape := window.size.x > window.size.y * 1.05
	var wanted := LANDSCAPE_SIZE if landscape else PORTRAIT_SIZE
	if window.content_scale_size != wanted:
		window.content_scale_size = wanted


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = _font(BODY_FONT)
	theme.default_font_size = int(round(28 * text_scale))
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	theme.set_type_variation("Heading", "Label")
	theme.set_font("font", "Heading", _font(HEADING_FONT))
	theme.set_color("font_color", "Heading", INK)

	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", _font(TITLE_FONT))
	theme.set_color("font_color", "Title", INK)

	theme.set_type_variation("Strong", "Label")
	theme.set_font("font", "Strong", _font(STRONG_FONT))

	# The name of the game, on the dark.
	theme.set_type_variation("Logo", "Label")
	theme.set_font("font", "Logo", _spaced(LOGO_FONT, 2))
	theme.set_color("font_color", "Logo", ON_WOOD)
	theme.set_color("font_shadow_color", "Logo", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_y", "Logo", 3)

	# Lettering on the wood of the top band.
	for type in ["OnWood", "OnWoodStrong", "OnWoodHeading"]:
		theme.set_type_variation(type, "Label")
		theme.set_color("font_color", type, ON_WOOD)
	theme.set_font("font", "OnWoodStrong", _font(STRONG_FONT))
	theme.set_font("font", "OnWoodHeading", _font(HEADING_FONT))
	theme.set_type_variation("OnWoodMuted", "Label")
	theme.set_color("font_color", "OnWoodMuted", ON_WOOD_MUTED)

	theme.set_stylebox("panel", "PanelContainer", frame("ui/panel", 96, 24, 22, sheet_style()))
	theme.set_type_variation("WoodPanel", "PanelContainer")
	theme.set_stylebox("panel", "WoodPanel", wood_style())
	theme.set_stylebox("panel", "PopupMenu", frame("ui/panel", 96, 24, 16, sheet_style(14)))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", INK)
	var hover_row := StyleBoxFlat.new()
	hover_row.bg_color = Color(MALACHITE, 0.16)
	theme.set_stylebox("hover", "PopupMenu", hover_row)
	var tip := wood_style(10)
	(tip as PlatedWood).plates = []
	(tip as PlatedWood).rivet_every = 0.0
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", ON_WOOD)
	theme.set_color("default_color", "RichTextLabel", INK)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MALACHITE
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(8)
	focus.set_expand_margin_all(3)
	for type in ["Button", "OptionButton"]:
		theme.set_font("font", type, _font(STRONG_FONT))
		theme.set_font_size("font_size", type, int(round(27 * text_scale)))
		theme.set_stylebox("normal", type, frame("ui/button", 64, 16, 14, _box(FLAX_DEEP, Color(INK, 0.28))))
		theme.set_stylebox("hover", type, frame("ui/button_hover", 64, 16, 14, _box(FLAX_DEEP.lightened(0.18), Color(INK, 0.55))))
		theme.set_stylebox("pressed", type, frame("ui/button_pressed", 64, 16, 14, _box(FLAX_DEEP.darkened(0.08), INK)))
		theme.set_stylebox("hover_pressed", type, frame("ui/button_pressed", 64, 16, 14, _box(FLAX_DEEP.darkened(0.08), INK)))
		theme.set_stylebox("disabled", type, frame("ui/button_disabled", 64, 16, 14, _box(Color(FLAX_DEEP, 0.35), Color(INK, 0.12))))
		theme.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			theme.set_color(state, type, INK)
		theme.set_color("font_disabled_color", type, Color(MUTED, 0.75))
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			theme.set_color(state, type, INK)
		theme.set_color("icon_disabled_color", type, Color(MUTED, 0.6))
		theme.set_constant("h_separation", type, 12)
		theme.set_constant("icon_max_width", type, 36)

	# The main action of a sheet: malachite, flax lettering.
	theme.set_type_variation("Primary", "Button")
	theme.set_stylebox("normal", "Primary", _box(MALACHITE, MALACHITE.darkened(0.25)))
	theme.set_stylebox("hover", "Primary", _box(MALACHITE.lightened(0.1), MALACHITE.darkened(0.25)))
	theme.set_stylebox("pressed", "Primary", _box(MALACHITE.darkened(0.15), MALACHITE.darkened(0.4)))
	theme.set_stylebox("hover_pressed", "Primary", _box(MALACHITE.darkened(0.15), MALACHITE.darkened(0.4)))
	theme.set_stylebox("disabled", "Primary", _box(Color(MALACHITE, 0.3), Color(0, 0, 0, 0)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Primary", PAGE)
	theme.set_color("font_disabled_color", "Primary", Color(PAGE, 0.7))
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		theme.set_color(state, "Primary", PAGE)

	# A row of tabs: quiet until open, then underlined in madder.
	theme.set_type_variation("TabButton", "Button")
	var tab := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	theme.set_stylebox("normal", "TabButton", tab)
	var tab_hover := _box(Color(INK, 0.05), Color(0, 0, 0, 0))
	theme.set_stylebox("hover", "TabButton", tab_hover)
	theme.set_stylebox("pressed", "TabButton", tab_hover)
	var open := _box(Color(INK, 0.04), MADDER)
	open.set_border_width_all(0)
	open.border_width_bottom = 4
	open.set_corner_radius_all(0)
	theme.set_stylebox("disabled", "TabButton", frame("ui/button_selected", 64, 16, 14, open))
	theme.set_color("font_color", "TabButton", MUTED)
	theme.set_color("font_hover_color", "TabButton", INK)
	theme.set_color("icon_normal_color", "TabButton", MUTED)
	theme.set_color("icon_hover_color", "TabButton", INK)
	theme.set_color("font_disabled_color", "TabButton", INK)
	theme.set_color("icon_disabled_color", "TabButton", INK)
	theme.set_constant("icon_max_width", "TabButton", 44)

	# Icon-only buttons on a sheet: no box until touched.
	theme.set_type_variation("IconButton", "Button")
	theme.set_stylebox("normal", "IconButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", "IconButton", _box(Color(INK, 0.06), Color(0, 0, 0, 0)))
	theme.set_stylebox("pressed", "IconButton", _box(Color(INK, 0.12), Color(0, 0, 0, 0)))

	# Buttons on the wood: plated wood with flax lettering; icon-only ones
	# stay bare until touched.
	for type in ["WoodButton", "WoodIconButton"]:
		theme.set_type_variation(type, "Button")
		if type == "WoodButton":
			theme.set_stylebox("normal", type, plated_button())
			theme.set_stylebox("hover", type, plated_button(0.08))
			theme.set_stylebox("pressed", type, plated_button(-0.25))
			theme.set_stylebox("hover_pressed", type, plated_button(-0.25))
		else:
			theme.set_stylebox("normal", type, _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
			theme.set_stylebox("hover", type, _box(Color(ON_WOOD, 0.08), Color(0, 0, 0, 0)))
			theme.set_stylebox("pressed", type, _box(Color(ON_WOOD, 0.16), Color(0, 0, 0, 0)))
			theme.set_stylebox("hover_pressed", type, _box(Color(ON_WOOD, 0.16), Color(0, 0, 0, 0)))
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			theme.set_color(state, type, ON_WOOD)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			theme.set_color(state, type, ON_WOOD)

	for type in ["LineEdit", "TextEdit"]:
		var field := _box(PAGE, Color(INK, 0.3))
		field.set_content_margin_all(16)
		theme.set_stylebox("normal", type, frame("ui/field", 48, 12, 16, field))
		var focused := field.duplicate()
		focused.border_color = MALACHITE
		focused.set_border_width_all(2)
		theme.set_stylebox("focus", type, focused)
		theme.set_color("font_color", type, INK)
		theme.set_color("font_placeholder_color", type, Color(MUTED, 0.75))
		theme.set_color("caret_color", type, MALACHITE)
		theme.set_color("selection_color", type, Color(MALACHITE, 0.3))
		theme.set_font("font", type, _font(BODY_FONT))

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(INK, 0.3)
	grabber.set_corner_radius_all(4)
	grabber.content_margin_left = 4
	grabber.content_margin_right = 4
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	var grabber_hot := grabber.duplicate()
	grabber_hot.bg_color = Color(INK, 0.55)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.06)
	track.set_corner_radius_all(4)
	track.content_margin_left = 4
	track.content_margin_right = 4
	theme.set_stylebox("scroll", "VScrollBar", track)

	# Volume sliders: a thin track, filled in malachite up to the handle.
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(INK, 0.15)
	rail.set_corner_radius_all(4)
	rail.content_margin_top = 4
	rail.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", rail)
	var filled := rail.duplicate()
	filled.bg_color = MALACHITE
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	return theme


## A sheet of flax: flat, square-cornered, an ink hairline round it.
static func sheet_style(padding := 22, alpha := 1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(FLAX, alpha)
	style.border_color = Color(INK, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(padding)
	style.anti_aliasing = true
	return style


## Walnut with gold plating (PlatedWood): a rail along the bottom with
## rivets and plates at the corners; the top band's look.
static func wood_style(padding := 14) -> StyleBox:
	var style := PlatedWood.new(padding)
	style.plates = [CORNER_BOTTOM_LEFT, CORNER_BOTTOM_RIGHT]
	return style


## A button of plated wood: a thin gold rim and small corner plates; `lift`
## lightens it under the finger and darkens it pressed.
static func plated_button(lift := 0.0) -> StyleBox:
	var style := PlatedWood.new(0)
	style.rails = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
	style.rail_width = 2.0
	style.rivet_every = 0.0
	style.plate_size = 12.0
	style.lift = lift
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


## Older name for the sheet.
static func panel_style(padding := 22, alpha := 1.0) -> StyleBoxFlat:
	return sheet_style(padding, alpha)


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
	style.set_corner_radius_all(6)
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


static func _spaced(path: String, spacing: int) -> Font:
	var variation := FontVariation.new()
	variation.base_font = _font(path)
	variation.spacing_glyph = spacing
	return variation
