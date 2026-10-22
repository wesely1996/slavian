class_name ScrollRoll
extends VBoxContainer
## A small scroll of paper between two wooden rollers, laid over a sheet:
## it unrolls when shown, and what is on it scrolls when it is longer than
## `max_height` (a building card's levels, say).

const ROD := 22.0
const UNROLL_SEC := 0.45
const WOOD_LIGHT := Color("#9a6a3c")
const WOOD_DARK := Color("#4a2e17")
const CAP := Color("#c99a2e")

var max_height := 320.0
var _paper: PanelContainer
var _scroll: ScrollContainer
var _content: Control


func _init(content: Control, height := 320.0) -> void:
	max_height = height
	_content = content
	add_theme_constant_override("separation", 0)
	add_child(_Rod.new())
	_paper = PanelContainer.new()
	_paper.add_theme_stylebox_override("panel", _paper_style())
	add_child(_paper)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = 0.0
	_paper.add_child(_scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	add_child(_Rod.new())


func _ready() -> void:
	# Unroll to the paper's length once it is laid out (wrapped text knows
	# its height only then).
	for i in 2:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var unroll := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	unroll.tween_property(_scroll, "custom_minimum_size:y", _length(), UNROLL_SEC)
	# Rich text grows to its full height while it unrolls: follow it.
	unroll.finished.connect(func() -> void:
		_fit()
		_content.resized.connect(_fit))


## As long as what is on it, up to max_height.
func _length() -> float:
	return minf(_content.size.y, max_height)


func _fit() -> void:
	_scroll.custom_minimum_size.y = _length()


## Paper a shade lighter than the sheet under it, shadowed under the rods.
static func _paper_style() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#f3ead2")
	style.border_color = Color(UiTheme.INK, 0.25)
	style.border_width_left = 1
	style.border_width_right = 1
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


## A wooden roller a little wider than the paper, gold-capped at its ends.
class _Rod:
	extends Control

	func _init() -> void:
		custom_minimum_size.y = ScrollRoll.ROD
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		var body := Rect2(-6.0, h * 0.18, size.x + 12.0, h * 0.64)
		# The round of the wood: dark at the edges, light along the top.
		draw_rect(body, ScrollRoll.WOOD_DARK)
		draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.15), Vector2(body.size.x, body.size.y * 0.4)), ScrollRoll.WOOD_LIGHT)
		draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.22), Vector2(body.size.x, body.size.y * 0.1)), Color(1, 1, 1, 0.18))
		for x in [-8.0, size.x + 8.0]:
			draw_circle(Vector2(x, h / 2.0), h * 0.42, ScrollRoll.WOOD_DARK)
			draw_circle(Vector2(x, h / 2.0), h * 0.3, ScrollRoll.CAP)
			draw_circle(Vector2(x - h * 0.08, h / 2.0 - h * 0.08), h * 0.1, Color(1, 1, 1, 0.35))
