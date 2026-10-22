class_name UI
extends RefCounted
## Small builders for code-constructed screens, sized for phones.

const TITLE_SIZE := 56
const HEADING_SIZE := 34
const SMALL_SIZE := 22
const BUTTON_HEIGHT := 76.0
const MUTED := UiTheme.MUTED
const ERROR := UiTheme.MADDER
## Ours and done (malachite); resources and levels (wheat).
const GOOD := UiTheme.MALACHITE
const ACCENT := UiTheme.WHEAT


## Scales a size by the accessibility text size (M5 15).
static func scaled(size: float) -> int:
	return int(round(size * UiTheme.text_scale))


## The current language's version of `text` (English source text; see
## tools/i18n/extract.py). In nodes, tr() does the same.
static func t(text: String) -> String:
	return TranslationServer.translate(text)


## `one` or `many` by `count`, in the current language's plural forms.
static func tn(one: String, many: String, count: int) -> String:
	return TranslationServer.translate_plural(one, many, count)


static func label(text := "", font_size := 0, color := Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_size > 0:
		node.add_theme_font_size_override("font_size", scaled(font_size))
	if font_size >= TITLE_SIZE:
		node.theme_type_variation = "Title"
	elif font_size >= HEADING_SIZE:
		node.theme_type_variation = "Heading"
	if color != Color.WHITE:
		node.add_theme_color_override("font_color", color)
	return node


static func button(text: String, on_pressed: Callable, icon_id := "") -> Button:
	var node := Button.new()
	node.text = text
	if icon_id != "":
		node.icon = Art.texture(icon_id)
		node.expand_icon = false
	node.custom_minimum_size.y = BUTTON_HEIGHT * UiTheme.text_scale
	node.custom_minimum_size.x = 96.0
	node.pressed.connect(on_pressed)
	return node


## The main action of a sheet, in malachite.
static func primary(text: String, on_pressed: Callable, icon_id := "") -> Button:
	var node := button(text, on_pressed, icon_id)
	node.theme_type_variation = "Primary"
	return node


static func line_edit(placeholder: String, text := "") -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.text = text
	node.custom_minimum_size.y = BUTTON_HEIGHT * UiTheme.text_scale
	return node


static func options(items: Array, selected := 0) -> OptionButton:
	var node := OptionButton.new()
	for item in items:
		node.add_item(str(item))
	node.select(selected)
	node.custom_minimum_size.y = BUTTON_HEIGHT * UiTheme.text_scale
	return node


static func vbox(separation := 16) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation := 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	node.child_entered_tree.connect(_fit_wrapping)
	return node


## A wrapping label in a row takes the room left over; left to its minimum
## width it would wrap after every letter and stand on end.
static func _fit_wrapping(child: Node) -> void:
	if child is Label and child.autowrap_mode != TextServer.AUTOWRAP_OFF and child.size_flags_horizontal == Control.SIZE_FILL:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## A sheet of flax (or ui/panel from the art), `alpha` see-through.
static func panel(alpha := 1.0, padding := 20) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", UiTheme.frame("ui/panel", 96, 24, padding + 6, UiTheme.sheet_style(padding + 6, alpha)))
	return node


## A band of dark wood, for the top of the screen.
static func wood(padding := 14) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", UiTheme.wood_style(padding))
	return node


## A row of tabs: `tabs` is [[key, text, icon id], ...]; the open one is
## underlined in madder.
static func tabs(tabs_: Array, open: String, on_pick: Callable) -> HBoxContainer:
	var row := hbox(8)
	for tab in tabs_:
		var key: String = tab[0]
		var node := button(tab[1], func() -> void: on_pick.call(key), tab[2] if tab.size() > 2 else "")
		node.theme_type_variation = "TabButton"
		node.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		node.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.add_theme_font_size_override("font_size", scaled(SMALL_SIZE))
		node.custom_minimum_size.y = 100 * UiTheme.text_scale
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.disabled = key == open
		row.add_child(node)
	return row


## A small icon from the art, `size` across; empty when the art is missing.
static func icon(id: String, size := 32.0) -> TextureRect:
	var node := TextureRect.new()
	node.texture = Art.texture(id)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(size, size)
	return node


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func signed(value: float) -> String:
	return ("+%d" if value >= 0 else "−%d") % absi(roundi(value))


## Amounts with each resource's icon, for a rich label: "[img]…[/img] 320 …".
## Without the art it falls back to resource_text.
static func costs(amounts: Dictionary, icon_size := 30) -> String:
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		var file := Art.path("resource/" + kind)
		if file == "" or not ResourceLoader.exists(file):
			return resource_text(amounts)
		parts.append("[img=%d]%s[/img] %d" % [icon_size, file, amounts[kind]])
	return "  ".join(parts)


## A label that takes BBCode, for text with icons in it (UI.costs).
static func rich(text := "", font_size := SMALL_SIZE, color := MUTED) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("normal_font_size", scaled(font_size))
	node.add_theme_color_override("default_color", color)
	node.text = text
	return node


## The name of a resource in the current language ("Wood", "Stone", …).
static func resource_name(kind: String) -> String:
	return {
		"wood": UI.t("Wood"),
		"stone": UI.t("Stone"),
		"grain": UI.t("Grain"),
		"iron": UI.t("Iron"),
	}.get(kind, kind.capitalize())


static func resource_text(amounts: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		parts.append("%s %d" % [resource_name(kind), amounts[kind]])
	return "  ".join(parts)
