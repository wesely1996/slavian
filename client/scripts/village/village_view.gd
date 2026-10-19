class_name VillageView
extends Control
## The inside of a village: resource fields on a ring around the outside,
## the walls inside them, and the building slots in a circle around the
## Elder's Hall in the middle, each drawn from the
## art (client/art/art.json) by its stage, with a level badge. Tap a plot to
## pick it. Without art the plots fall back to plain shapes.

signal plot_tapped(plot: String)

## The wall ring's radius, of the fields' ring.
const WALL_RING := 0.66
## The ring of building slots around the Hall, its slots' size and the
## Hall's, of the fields' ring.
const SLOT_RING := 0.435
const SLOT_SIZE := 0.185
const HALL_SIZE := 0.38
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
const WALL_COLORS := {
	"wood": Color("#6e4b2c"),
	"timber": Color("#7a5a36"),
	"stone": Color("#9d978c"),
	"fortress": Color("#b9b2a4"),
}
const MOAT_WATER := Color("#3d6f86")
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
## the Hall's slot (c0) in the middle and the other center slots in a circle
## around it. Each rect is the plot's tap area.
static func layout(area: Vector2, field_count: int, slot_count: int, tower_count := 0) -> Dictionary:
	var rects := {}
	var middle := area / 2.0
	var radius := minf(area.x, area.y) * 0.4
	var field_size := radius * 0.36
	for i in field_count:
		var angle := TAU * i / field_count - PI / 2.0
		var at := middle + Vector2(cos(angle), sin(angle)) * radius
		rects["f%d" % i] = Rect2(at - Vector2.ONE * field_size / 2.0, Vector2.ONE * field_size)
	# On the wall ring, between the fields: the gate (the walls' plot) at the
	# bottom, the wall slots around the rest.
	var ring := radius * WALL_RING
	var gate := radius * 0.24
	var gate_at := middle + Vector2(cos(deg_to_rad(105.0)), sin(deg_to_rad(105.0))) * ring
	rects["w"] = Rect2(gate_at - Vector2.ONE * gate / 2.0, Vector2.ONE * gate)
	var tower := radius * 0.2
	for i in tower_count:
		var angle := deg_to_rad(-165.0 + 60.0 * i)
		var at := middle + Vector2(cos(angle), sin(angle)) * ring
		rects["t%d" % i] = Rect2(at - Vector2.ONE * tower / 2.0, Vector2.ONE * tower)
	if slot_count <= 0:
		return rects
	var hall := radius * HALL_SIZE
	rects["c0"] = Rect2(middle - Vector2.ONE * hall / 2.0, Vector2.ONE * hall)
	var around := slot_count - 1
	var ring_r := radius * SLOT_RING
	var slot := minf(radius * SLOT_SIZE, 2.0 * ring_r * sin(PI / maxf(around, 1)) * 0.76)
	for i in around:
		var angle := TAU * i / around - PI / 2.0
		var at := middle + Vector2(cos(angle), sin(angle)) * ring_r
		rects["c%d" % (i + 1)] = Rect2(at - Vector2.ONE * slot / 2.0, Vector2.ONE * slot)
	return rects


static func plot_at(rects: Dictionary, point: Vector2) -> String:
	for plot in rects:
		if (rects[plot] as Rect2).has_point(point):
			return plot
	return ""


func _rects() -> Dictionary:
	var v: Dictionary = data.buildings.village
	return layout(size, v.fields.size(), int(v.centerSlots), data.get("walls", {}).get("slotsAt", []).size())


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
		_draw_moat(middle, radius * WALL_RING, _moat_level())
		_shaded_disc(middle, radius * WALL_RING, SQUARE_EDGE, SQUARE_EARTH)
		_draw_paths(middle, rects)
		_draw_wall_ring(middle, radius * WALL_RING, Rules.wall_level(village))
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


## The walls around the square by their material: a pegged line where none
## stand yet, a palisade of sharpened logs, a timber rampart on an earth
## bank, a stone wall with merlons, fortress walls with round bastions.
func _draw_wall_ring(center: Vector2, r: float, level: int) -> void:
	if level <= 0:
		for i in 48:
			var a := TAU * i / 48.0
			draw_arc(center, r, a, a + TAU / 96.0, 3, Color(PALISADE, 0.6), r * 0.012, true)
		return
	var material := WallText.material(data, level)
	var width: float = r * {"wood": 0.05, "timber": 0.065, "stone": 0.075, "fortress": 0.095}.get(material, 0.05)
	var body: Color = WALL_COLORS.get(material, PALISADE)
	draw_arc(center + Vector2(0, width * 0.35), r, 0.0, TAU, 128, Color(0, 0, 0, 0.35), width * 1.15, true)
	if material == "timber":
		# The earth bank under the breastwork.
		draw_arc(center, r, 0.0, TAU, 128, Color("#6f5a3c"), width * 1.5, true)
	draw_arc(center, r, 0.0, TAU, 128, body, width, true)
	draw_arc(center, r + width * 0.3, PI * 0.9, PI * 1.7, 64, Color(1, 0.95, 0.85, 0.25), width * 0.3, true)
	match material:
		"wood", "timber":
			# Log ends along the top, the palisade's sharpened.
			var count := 96 if material == "wood" else 72
			for i in count:
				var a := TAU * i / count
				var dir := Vector2(cos(a), sin(a))
				draw_line(center + dir * (r - width * 0.5), center + dir * (r + width * (0.65 if material == "wood" else 0.5)), body.darkened(0.4), 1.5, true)
		_:
			# Coursed stone: a joint ring and merlons on the outer face.
			draw_arc(center, r, 0.0, TAU, 128, body.darkened(0.2), 1.0, true)
			var count := 64
			for i in count:
				var a := TAU * (i + 0.25) / count
				draw_arc(center, r + width * 0.5, a, a + TAU / count * 0.5, 3, body.lightened(0.12), width * 0.35, true)
			if material == "fortress":
				# Round bastions between the wall slots, clear of the gate.
				for deg in [45.0, 165.0, 225.0, 285.0, 345.0]:
					var a := deg_to_rad(deg)
					var at := center + Vector2(cos(a), sin(a)) * r
					draw_circle(at + Vector2(0, width * 0.3), width * 1.05, Color(0, 0, 0, 0.3))
					draw_circle(at, width * 1.0, body)
					draw_arc(at, width * 1.0, 0.0, TAU, 24, body.darkened(0.35), 1.5, true)


## The moat outside the walls (the ditch tower): a dry ditch with stakes,
## water from walls.towers.ditch.waterAt.
func _draw_moat(center: Vector2, r: float, level: int) -> void:
	if level <= 0:
		return
	var at := r * 1.13
	var width := r * (0.06 + 0.004 * level)
	draw_arc(center, at, 0.0, TAU, 128, Color("#3e3324"), width * 1.25, true)
	if WallText.moat_water(data, level):
		draw_arc(center, at, 0.0, TAU, 128, MOAT_WATER, width, true)
		draw_arc(center, at - width * 0.15, PI * 1.0, PI * 1.6, 64, Color(1, 1, 1, 0.18), width * 0.18, true)
	else:
		draw_arc(center, at, 0.0, TAU, 128, Color("#5a4a33"), width * 0.8, true)
		for i in 60:
			var a := TAU * i / 60.0
			var dir := Vector2(cos(a), sin(a))
			draw_line(center + dir * (at + width * 0.55), center + dir * (at + width * 0.95), PALISADE.darkened(0.3), 1.5, true)


## Beaten-earth paths from the Hall out to each slot around it and to the
## gate.
func _draw_paths(center: Vector2, rects: Dictionary) -> void:
	for plot in rects:
		var p := String(plot)
		if p == "c0" or not (p.begins_with("c") or p == "w"):
			continue
		var to: Vector2 = (rects[p] as Rect2).get_center()
		draw_line(center, to, Color(SQUARE_EDGE, 0.55), (rects[p] as Rect2).size.x * 0.16, true)


## The best level of the moat (ditch) in the wall slots; 0: none.
func _moat_level() -> int:
	var best := 0
	for plot in village.get("plots", {}):
		var holds: Dictionary = village.plots[plot]
		if Rules.is_tower_slot(String(plot)) and holds.get("building") == "ditch":
			best = maxi(best, int(holds.level))
	return best


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
		var material := WallText.material(data, maxi(level, 1)) if Rules.is_wall(plot) else ""
		id = Art.building_id(String(holds.building), maxi(level, 1), field, material)
	elif Rules.is_locked(data, village, plot):
		id = "plot/locked"
	else:
		id = "plot/empty"
	var tex := Art.texture(id)
	if tex == null:
		return false
	var tint := Color.WHITE if level > 0 or id.begins_with("plot/") else Color(1, 1, 1, 0.8)
	var box := rect.grow(rect.size.x * (0.12 if field else (0.34 if Rules.is_tower_slot(plot) or Rules.is_wall(plot) else 0.24)))
	draw_texture_rect(tex, box, false, tint)
	if plot == selected:
		draw_arc(rect.get_center(), rect.size.x * 0.62, 0.0, TAU, 48, SELECTED, 4.0)
	if under_way:
		draw_arc(rect.get_center(), rect.size.x * 0.56, 0.0, TAU, 48, BUILDING_ACTIVE, 5.0)
	if id == "plot/locked":
		var needs := ("Walls %d" % Rules.tower_unlock_level(data, Rules.plot_index(plot))) if Rules.is_tower_slot(plot) else ("Hall %d" % Rules.slot_unlock_level(data, Rules.plot_index(plot)))
		_text(font, rect.get_center() + Vector2(0, rect.size.y * 0.42), needs, rect.size.y * (0.24 if Rules.is_tower_slot(plot) else 0.18), Color.WHITE)
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
