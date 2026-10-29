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


## An "i" to hold (or tap) for `text`, in a parchment popup beside it:
## explanations live here rather than under every button.
static func info(text: String) -> Button:
	var node := info_card(func() -> Control: return label(text, SMALL_SIZE))
	node.tooltip_text = text
	return node


## An info mark whose popup holds what `make` builds (a building's card,
## say), made when it is opened.
static func info_card(make: Callable) -> Button:
	var node := Button.new()
	node.icon = Art.texture("icon/info")
	node.flat = true
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(56, 56) * UiTheme.text_scale
	node.add_theme_constant_override("icon_max_width", int(38 * UiTheme.text_scale))
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		node.add_theme_color_override(state, UiTheme.WHEAT if state != "icon_normal_color" else UiTheme.MUTED)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.button_down.connect(func() -> void: _show_info(node, make.call()))
	return node


static func _show_info(anchor: Control, content: Control) -> void:
	var popup := PopupPanel.new()
	popup.add_theme_stylebox_override("panel", UiTheme.sheet_style(14))
	var area := anchor.get_viewport_rect().size
	var width := minf(600.0, area.x - 32.0)
	content.custom_minimum_size.x = width - 50.0
	popup.add_child(content)
	anchor.add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	# Under the mark (or over it, near the bottom), kept on the screen.
	var at := anchor.get_screen_position()
	var x := clampf(at.x + anchor.size.x - width, 16.0, area.x - width - 16.0)
	popup.popup(Rect2i(Vector2i(int(x), int(at.y + anchor.size.y + 6.0)), Vector2i(int(width), 0)))
	var keep_on_screen := func() -> void:
		if popup.position.y + popup.size.y > area.y - 16.0:
			popup.position.y = int(maxf(16.0, at.y - popup.size.y - 6.0))
	keep_on_screen.call()
	# Content that changes size (a scroll unrolling) is fitted again, and
	# kept on the screen.
	content.minimum_size_changed.connect(func() -> void:
		popup.reset_size()
		popup.size.x = int(width)
		keep_on_screen.call())


## `control` with an info card's mark at its end (UI.info_card), as one row.
static func with_card(control: Control, make: Callable) -> HBoxContainer:
	var row := hbox(8)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	row.add_child(info_card(make))
	return row


## `control` with an info mark at its end (UI.info), as one row.
static func with_info(control: Control, text: String) -> HBoxContainer:
	var row := hbox(8)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	row.add_child(info(text))
	return row


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
		node.add_theme_font_size_override("font_size", scaled(SMALL_SIZE))
		node.custom_minimum_size = Vector2(0, 64 * UiTheme.text_scale)
		# Four tabs share a phone's width: a word too long is cut short.
		node.clip_text = true
		node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.disabled = key == open
		row.add_child(node)
	return row


## Tabs down a sheet's side, pictures rather than words (the name shows on
## hover): `tabs_` is [[key, art id, name], ...], each tab `size` square.
## Line icons (icon/...) take the theme's ink; portraits and emblems keep
## their colours.
static func side_tabs(tabs_: Array, open: String, on_pick: Callable, size := 88.0) -> VBoxContainer:
	var column := vbox(6)
	for tab in tabs_:
		var key: String = tab[0]
		var node := picture_button(tab[1], tab[2], func() -> void: on_pick.call(key), size)
		node.disabled = key == open
		column.add_child(node)
	return column


## A square button that is all picture (a side tab's look), `size` across;
## `name` shows on hover. Shown pressed while disabled.
static func picture_button(art_id: String, name: String, on_pressed: Callable, size := 88.0) -> Button:
	var node := Button.new()
	node.theme_type_variation = "SideTab"
	node.icon = Art.texture(art_id)
	node.expand_icon = true
	node.tooltip_text = name
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(size, size) * UiTheme.text_scale
	node.add_theme_constant_override("icon_max_width", roundi(size * 0.72 * UiTheme.text_scale))
	if not art_id.begins_with("icon/"):
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color"]:
			node.add_theme_color_override(state, Color.WHITE)
	node.pressed.connect(on_pressed)
	return node


## A sheet with side tabs: the tabs on the left, and the box (returned
## second) where the open tab's content goes.
static func side_layout(tabs_: Array, open: String, on_pick: Callable, size := 88.0) -> Array:
	var row := hbox(14)
	var column := side_tabs(tabs_, open, on_pick, size)
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(column)
	var content := vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	return [row, content]


## Page `page` of `items`, `per_page` at a time: [the items on it, a row of
## ◀ n / m ▶ to turn pages (empty when they all fit)]. `on_page` gets the
## page to show.
static func paged(items: Array, page: int, per_page: int, on_page: Callable) -> Array:
	var pages := maxi(1, ceili(items.size() / float(per_page)))
	var at := clampi(page, 0, pages - 1)
	var shown := items.slice(at * per_page, (at + 1) * per_page)
	var row := hbox(8)
	if pages > 1:
		var back := button("◀", func() -> void: on_page.call(at - 1))
		back.disabled = at == 0
		row.add_child(back)
		var where := label(t("%d / %d") % [at + 1, pages], SMALL_SIZE, MUTED)
		where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(where)
		var next := button("▶", func() -> void: on_page.call(at + 1))
		next.disabled = at == pages - 1
		row.add_child(next)
	return [shown, row]


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


## A number as it reads best: whole numbers bare, else one decimal.
static func number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


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
