class_name VillageView
extends Control
## The inside of a village, Travian style: resource fields on a ring around
## the outside, building slots in a grid in the middle, each drawn from the
## art (client/art/art.json) by its stage, with a level badge. Tap a plot to
## pick it. Without art the plots fall back to plain shapes.

signal plot_tapped(plot: String)

const CENTER_COLUMNS := 4
const FIELD_COLORS := {
	"wood": Color("#5e7d3a"),
	"stone": Color("#7d7a72"),
	"grain": Color("#b8973a"),
	"iron": Color("#8a5a44"),
}
const GROUND := Color("#3b4a2a")
const SQUARE := Color("#6b5a42")
const SLOT_EMPTY := Color("#4a3f30")
const SLOT_LOCKED := Color("#2a241c")
const BUILDING := Color("#8f6d45")
const BUILDING_ACTIVE := Color("#e2b04a")
const SELECTED := Color.WHITE
const MEADOW := Color("#7d9150")
const MEADOW_EDGE := Color("#4c5e33")
const SQUARE_EARTH := Color("#9c8a66")
const SQUARE_EDGE := Color("#6e5f45")
const PALISADE := Color("#6e4b2c")
const INK := Color("#1d1813")

## Game data (buildings), the village as the server sent it, the picked plot.
var data: Dictionary = {}
var village: Dictionary = {}
var selected := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func show_village(game_data: Dictionary, new_village: Dictionary, new_selected: String) -> void:
	data = game_data
	village = new_village
	selected = new_selected
	queue_redraw()


## Where each plot sits inside a `size` rectangle: fields evenly on a ring,
## center slots in a grid inside it. Each rect is the plot's tap area.
static func layout(area: Vector2, field_count: int, slot_count: int) -> Dictionary:
	var rects := {}
	var middle := area / 2.0
	var radius := minf(area.x, area.y) * 0.4
	var field_size := radius * 0.36
	for i in field_count:
		var angle := TAU * i / field_count - PI / 2.0
		var at := middle + Vector2(cos(angle), sin(angle)) * radius
		rects["f%d" % i] = Rect2(at - Vector2.ONE * field_size / 2.0, Vector2.ONE * field_size)
	var rows := ceili(float(slot_count) / CENTER_COLUMNS)
	# The grid's corners stay inside the ring of fields.
	var inner := radius - field_size * 0.6
	var cell := inner * 2.0 / sqrt(CENTER_COLUMNS * CENTER_COLUMNS + rows * rows)
	var origin := middle - Vector2(CENTER_COLUMNS, rows) * cell / 2.0
	var gap := cell * 0.08
	for i in slot_count:
		var at := origin + Vector2(i % CENTER_COLUMNS, i / CENTER_COLUMNS) * cell
		rects["c%d" % i] = Rect2(at + Vector2.ONE * gap, Vector2.ONE * (cell - gap * 2.0))
	return rects


static func plot_at(rects: Dictionary, point: Vector2) -> String:
	for plot in rects:
		if (rects[plot] as Rect2).has_point(point):
			return plot
	return ""


func _rects() -> Dictionary:
	var v: Dictionary = data.buildings.village
	return layout(size, v.fields.size(), int(v.centerSlots))


## Mouse events only: on phones taps arrive as emulated mouse clicks, and
## handling touches too would count each tap twice.
func _gui_input(event: InputEvent) -> void:
	if data.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var plot := plot_at(_rects(), event.position)
		if plot != "":
			plot_tapped.emit(plot)
			accept_event()


func _draw() -> void:
	if village.is_empty() or data.is_empty():
		return
	var rects := _rects()
	var middle := size / 2.0
	var radius := minf(size.x, size.y) * 0.4
	var art := Art.has("plot/empty")
	if art:
		# A soft shadow, the meadow around, the village square inside its
		# palisade; each shaded lighter towards the upper left.
		for i in 6:
			draw_circle(middle + Vector2(0, radius * 0.04), radius * (1.32 - i * 0.02), Color(0, 0, 0, 0.08))
		_shaded_disc(middle, radius * 1.2, MEADOW_EDGE, MEADOW)
		_shaded_disc(middle, radius * 0.76, SQUARE_EDGE, SQUARE_EARTH)
		draw_arc(middle, radius * 0.76, 0.0, TAU, 96, PALISADE, radius * 0.045, true)
		draw_arc(middle + Vector2(-1, -1), radius * 0.76, PI * 0.9, PI * 1.6, 48, Color(1, 0.9, 0.7, 0.25), 2.0, true)
	else:
		draw_circle(middle, radius * 1.22, GROUND)
		draw_circle(middle, radius * 0.72, SQUARE)

	var building_plots := {}
	for item in village.queue:
		building_plots[item.get("plot", "")] = int(item.targetLevel)
	var font := get_theme_default_font()
	for plot in Rules.plot_ids(village):
		if not rects.has(plot):
			continue
		var rect: Rect2 = rects[plot]
		var holds: Dictionary = village.plots[plot]
		var level := int(holds.level)
		var def: Dictionary = data.buildings.buildings.get(holds.building, {}) if holds.building != null else {}
		var under_way := building_plots.has(plot)
		if art and _draw_plot_art(plot, rect, holds, level, under_way, font):
			continue
		if Rules.is_field(plot):
			var center := rect.get_center()
			var r := rect.size.x / 2.0
			var resource: String = def.get("production", {}).get("resource", "")
			var color: Color = FIELD_COLORS.get(resource, BUILDING)
			draw_circle(center, r, color if level > 0 else color.darkened(0.45))
			if under_way:
				draw_arc(center, r - 3.0, 0.0, TAU, 48, BUILDING_ACTIVE, 6.0)
			if plot == selected:
				draw_arc(center, r + 4.0, 0.0, TAU, 48, SELECTED, 4.0)
			_text(font, center - Vector2(0, r * 0.12), str(level), r * 0.7)
			_text(font, center + Vector2(0, r * 0.48), resource.capitalize(), r * 0.3)
			continue
		var locked := Rules.is_locked(data, village, plot)
		var fill := SLOT_LOCKED if locked else (SLOT_EMPTY if def.is_empty() else BUILDING)
		draw_rect(rect, fill)
		if under_way:
			draw_rect(rect.grow(-3.0), BUILDING_ACTIVE, false, 6.0)
		if plot == selected:
			draw_rect(rect.grow(4.0), SELECTED, false, 4.0)
		var font_size := rect.size.y * 0.2
		if locked:
			_text(font, rect.get_center(), "Hall %d" % Rules.slot_unlock_level(data, Rules.plot_index(plot)), font_size, UI.MUTED)
		elif def.is_empty():
			_text(font, rect.get_center(), "+", rect.size.y * 0.45, UI.MUTED)
		else:
			_text(font, rect.get_center() - Vector2(0, font_size * 0.6), _short_name(def.name), font_size)
			_text(font, rect.get_center() + Vector2(0, font_size * 0.7), str(level), font_size * 1.3)


## A disc shaded from `edge` at its rim to `middle_color` towards its lit
## upper left.
func _shaded_disc(center: Vector2, r: float, edge: Color, middle_color: Color) -> void:
	var steps := 10
	for i in steps:
		var t := float(i) / float(steps - 1)
		draw_circle(center - Vector2(r, r) * 0.12 * t, r * (1.0 - 0.55 * t), edge.lerp(middle_color, t))


## A plot from the art: the field or building by stage (faded before its
## first level), an empty or locked plot, a level badge, a gold ring while
## being built and a white one when picked. False when its art is missing.
func _draw_plot_art(plot: String, rect: Rect2, holds: Dictionary, level: int, under_way: bool, font: Font) -> bool:
	var field := Rules.is_field(plot)
	var id := ""
	if field or holds.building != null:
		id = Art.building_id(String(holds.building), maxi(level, 1), field)
	elif Rules.is_locked(data, village, plot):
		id = "plot/locked"
	else:
		id = "plot/empty"
	var tex := Art.texture(id)
	if tex == null:
		return false
	var tint := Color.WHITE if level > 0 or id.begins_with("plot/") else Color(1, 1, 1, 0.8)
	var box := rect.grow(rect.size.x * (0.12 if field else 0.24))
	draw_texture_rect(tex, box, false, tint)
	if plot == selected:
		draw_arc(rect.get_center(), rect.size.x * 0.62, 0.0, TAU, 48, SELECTED, 4.0)
	if under_way:
		draw_arc(rect.get_center(), rect.size.x * 0.56, 0.0, TAU, 48, BUILDING_ACTIVE, 5.0)
	if id == "plot/locked":
		_text(font, rect.get_center() + Vector2(0, rect.size.y * 0.42), "Hall %d" % Rules.slot_unlock_level(data, Rules.plot_index(plot)), rect.size.y * 0.18, Color.WHITE)
	elif id != "plot/empty":
		# The level in a dark badge at the plot's lower right.
		var at := rect.position + rect.size * Vector2(0.86, 0.84)
		var r := rect.size.x * 0.16
		draw_circle(at, r, INK)
		draw_circle(at, r * 0.82, BUILDING_ACTIVE if under_way else Color("#4a3f30"))
		_text(font, at, str(level), r * 1.2)
	return true


func _text(font: Font, center: Vector2, text: String, font_size: float, color := Color.WHITE) -> void:
	var px := maxi(8, roundi(font_size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var baseline := center + Vector2(-width / 2.0, font.get_ascent(px) / 2.0 - font.get_descent(px) / 2.0)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


## "Elder's Hall" → "Hall", "Scout Lodge" → "Lodge": slots are small.
func _short_name(full: String) -> String:
	var words := full.split(" ")
	return words[words.size() - 1]
