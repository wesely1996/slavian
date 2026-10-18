class_name UI
extends RefCounted
## Small builders for code-constructed screens, sized for phones.

const TITLE_SIZE := 56
const HEADING_SIZE := 34
const SMALL_SIZE := 22
const BUTTON_HEIGHT := 76.0
const MUTED := Color("#b8ae9c")
const ERROR := Color("#ff8a7a")


static func label(text := "", font_size := 0, color := Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_size > 0:
		node.add_theme_font_size_override("font_size", font_size)
	if color != Color.WHITE:
		node.add_theme_color_override("font_color", color)
	return node


static func button(text: String, on_pressed: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = BUTTON_HEIGHT
	node.pressed.connect(on_pressed)
	return node


static func line_edit(placeholder: String, text := "") -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.text = text
	node.custom_minimum_size.y = BUTTON_HEIGHT
	return node


static func options(items: Array, selected := 0) -> OptionButton:
	var node := OptionButton.new()
	for item in items:
		node.add_item(str(item))
	node.select(selected)
	node.custom_minimum_size.y = BUTTON_HEIGHT
	return node


static func vbox(separation := 16) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation := 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func panel(color := Color(0.13, 0.11, 0.09, 0.9), padding := 20) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.set_content_margin_all(padding)
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", style)
	return node


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func resource_text(amounts: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		parts.append("%s %d" % [kind.capitalize(), amounts[kind]])
	return "  ".join(parts)
