class_name VillageView
extends Control
## The inside of a village: resource fields round the outside, the walls
## inside them, and the building slots in a ring around the Elder's Hall in
## the middle, each drawn from the
## art (client/art/art.json) by its stage, with a level badge. Tap a plot to
## pick it. Without art the plots fall back to plain shapes. Nothing is a
## perfect circle: every ring follows the village's own wobbly outline
## (wobble(), seeded by the village), and the land runs on to the edges of
## the view, with the map's grain and light (VillageGround), wild grass and
## woods beyond the meadow and a road out of the gate.

signal plot_tapped(plot: String)

## The wall ring's radius, of the fields' ring.
const WALL_RING := 0.66
## The ring of building slots around the Hall, its slots' size and the
## Hall's, of the fields' ring.
const SLOT_RING := 0.435
const SLOT_SIZE := 0.165
const HALL_SIZE := 0.38
## Where the gate stands on the walls (degrees, clockwise from east).
const GATE_DEGREES := 105.0
const FIELD_COLORS := {
	"wood": Color("#5e7d3a"),
	"stone": Color("#7d7a72"),
	"grain": Color("#b8973a"),
	"iron": Color("#8a5a44"),
}
const SLOT_EMPTY := Color("#4a3f30")
const SLOT_LOCKED := Color("#2a241c")
const BUILDING := Color("#8f6d45")
const BUILDING_ACTIVE := Color("#e2b04a")
const SELECTED := Color.WHITE
const MEADOW := Color("#97a85c")
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
const ROAD_EARTH := Color("#a08a64")
## The moat's ring, of the walls'.
const MOAT_RING := 1.13
const INK := Color("#1d1813")

## Game data (buildings), the village as the server sent it, the picked plot.
var data: Dictionary = {}
var village: Dictionary = {}
var selected := ""
var _ground: VillageGround
var _woods := FastNoiseLite.new()
## What the ground is drawn for: the middle, the fields' radius, the seed.
var _middle := Vector2.ZERO
var _radius := 1.0
var _seed := 0
## Plots being built: what is left of each build (1: not started yet), so
## its ring empties clockwise as it goes.
var _left: Dictionary = {}
var _since_redraw := 0.0
## The time now (unix seconds): the game's server clock, set by the screen.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()


## Redraws now and then while something is being built, for the rings.
func _process(delta: float) -> void:
	if village.is_empty() or village.get("queue", []).is_empty():
		return
	_since_redraw += delta
	if _since_redraw >= 0.5:
		_since_redraw = 0.0
		queue_redraw()


## How much of the build on each plot in the queue is still to come.
static func builds_left(queue: Array, now: float) -> Dictionary:
	var left := {}
	for item in queue:
		var start := TimeUtil.parse_iso(String(item.get("startsAt", item.completesAt)))
		var done := TimeUtil.parse_iso(String(item.completesAt))
		var share := 1.0 if now <= start or done <= start else clampf((done - now) / (done - start), 0.0, 1.0)
		left[String(item.get("plot", ""))] = share
	return left


## The ring round a plot being built: what is still to do, from the top
## clockwise to where the work has got to.
func _draw_progress(center: Vector2, r: float, plot: String, width: float) -> void:
	var share: float = _left.get(plot, 1.0)
	if share <= 0.0:
		return
	draw_arc(center, r, -PI / 2.0 + TAU * (1.0 - share), -PI / 2.0 + TAU, 48, BUILDING_ACTIVE, width, true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	# Trees at the top edge would reach over the band above.
	clip_contents = true
	_ground = VillageGround.new()
	add_child(_ground)
	_woods.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_woods.frequency = 0.006


func show_village(game_data: Dictionary, new_village: Dictionary, new_selected: String) -> void:
	data = game_data
	village = new_village
	selected = new_selected
	queue_redraw()


## How far out the village's outline reaches at `angle`, as a share of a
## circle's: a few slow swells, different for every village (`seed`).
static func wobble(angle: float, seed: int) -> float:
	var a := float(seed % 97) * 0.37
	var b := float(seed % 89) * 0.53
	var c := float(seed % 83) * 0.71
	return 1.0 + 0.033 * sin(2.0 * angle + a) + 0.021 * sin(3.0 * angle + b) + 0.012 * sin(5.0 * angle + c)


## A steady pseudo-random number in [-1, 1] for item `i` of village `seed`.
static func jitter(seed: int, i: int) -> float:
	return fposmod(sin(float(seed) * 12.9898 + float(i) * 78.233) * 43758.5453, 1.0) * 2.0 - 1.0


## Where each plot sits inside a `size` rectangle: fields round the outside,
## the Hall's slot (c0) in the middle and the other center slots in a ring
## around it, all on the village's own outline (wobble). Each rect is the
## plot's tap area.
static func layout(area: Vector2, field_count: int, slot_count: int, tower_count := 0, seed := 0) -> Dictionary:
	var rects := {}
	var middle := area / 2.0
	var radius := minf(area.x, area.y) * 0.4
	var field_size := radius * 0.33
	for i in field_count:
		var angle := TAU * i / field_count - PI / 2.0
		var at := middle + Vector2(cos(angle), sin(angle)) * radius * wobble(angle, seed)
		var own := field_size * (1.0 + 0.04 * jitter(seed, i + 50))
		rects["f%d" % i] = Rect2(at - Vector2.ONE * own / 2.0, Vector2.ONE * own)
	# On the wall ring, between the fields: the gate (the walls' plot) at the
	# bottom, the wall slots around the rest.
	var ring := radius * WALL_RING
	var gate := radius * 0.21
	var gate_angle := deg_to_rad(GATE_DEGREES)
	var gate_at := middle + Vector2(cos(gate_angle), sin(gate_angle)) * ring * wobble(gate_angle, seed)
	rects["w"] = Rect2(gate_at - Vector2.ONE * gate / 2.0, Vector2.ONE * gate)
	var tower := radius * 0.17
	for i in tower_count:
		var angle := deg_to_rad(-165.0 + 60.0 * i)
		var at := middle + Vector2(cos(angle), sin(angle)) * ring * wobble(angle, seed)
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
		var at := middle + Vector2(cos(angle), sin(angle)) * ring_r * wobble(angle, seed)
		rects["c%d" % (i + 1)] = Rect2(at - Vector2.ONE * slot / 2.0, Vector2.ONE * slot)
	return rects


static func plot_at(rects: Dictionary, point: Vector2) -> String:
	for plot in rects:
		if (rects[plot] as Rect2).has_point(point):
			return plot
	return ""


func _rects() -> Dictionary:
	var v: Dictionary = data.buildings.village
	return layout(size, v.fields.size(), int(v.centerSlots), data.get("walls", {}).get("slotsAt", []).size(), int(village.get("id", 0)))


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
	# The land under it all, to the edges: square, meadow, moat, road, wilds.
	_middle = middle
	_radius = radius
	_seed = int(village.get("id", 0))
	_woods.seed = _seed
	_ground.build(size, hash([size, _seed]), _shade)
	if art:
		_draw_wilds(middle, radius)
		_draw_moat(middle, radius * WALL_RING, _moat_level())
		_draw_paths(middle, rects)
		_draw_wall_ring(middle, radius * WALL_RING, Rules.wall_level(village))

	var building_plots := {}
	for item in village.queue:
		building_plots[item.get("plot", "")] = int(item.targetLevel)
	_left = builds_left(village.queue, clock.call())
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
				_draw_progress(center, r - 3.0, plot, 6.0)
			if plot == selected:
				draw_arc(center, r + 4.0, 0.0, TAU, 48, SELECTED, 4.0)
			_text(font, center - Vector2(0, r * 0.12), str(level), r * 0.7)
			_text(font, center + Vector2(0, r * 0.48), UI.resource_name(resource), r * 0.3)
			continue
		var locked := Rules.is_locked(data, village, plot)
		var fill := SLOT_LOCKED if locked else (SLOT_EMPTY if def.is_empty() else BUILDING)
		draw_rect(rect, fill)
		if under_way:
			_draw_progress(rect.get_center(), rect.size.x * 0.48, plot, 6.0)
		if plot == selected:
			draw_rect(rect.grow(4.0), SELECTED, false, 4.0)
		var font_size := rect.size.y * 0.2
		if locked:
			_text(font, rect.get_center(), tr("Hall %d") % Rules.slot_unlock_level(data, Rules.plot_index(plot)), font_size, UI.MUTED)
		elif def.is_empty():
			_text(font, rect.get_center(), "+", rect.size.y * 0.45, UI.MUTED)
		else:
			_text(font, rect.get_center() - Vector2(0, font_size * 0.6), _short_name(tr(def.name)), font_size)
			_text(font, rect.get_center() + Vector2(0, font_size * 0.7), str(level), font_size * 1.3)


## The walls around the square by their material, along the village's
## outline: a pegged line where none stand yet, a palisade of sharpened logs,
## a timber rampart on an earth bank, a stone wall with merlons, fortress
## walls with round bastions.
func _draw_wall_ring(center: Vector2, r: float, level: int) -> void:
	if level <= 0:
		for i in 48:
			var a := TAU * i / 48.0
			draw_line(_on_ring(center, r, a), _on_ring(center, r, a + TAU / 96.0), Color(PALISADE, 0.6), r * 0.012, true)
		return
	var material := WallText.material(data, level)
	var width: float = r * {"wood": 0.05, "timber": 0.065, "stone": 0.075, "fortress": 0.095}.get(material, 0.05)
	var body: Color = WALL_COLORS.get(material, PALISADE)
	var line := _ring(center, r)
	var shadow := PackedVector2Array()
	for point in line:
		shadow.append(point + Vector2(0, width * 0.35))
	draw_polyline(shadow, Color(0, 0, 0, 0.35), width * 1.15, true)
	if material == "timber":
		# The earth bank under the breastwork.
		draw_polyline(line, Color("#6f5a3c"), width * 1.5, true)
	draw_polyline(line, body, width, true)
	match material:
		"wood", "timber":
			# Log ends along the top, the palisade's sharpened.
			var count := 96 if material == "wood" else 72
			for i in count:
				var a := TAU * i / count
				draw_line(_on_ring(center, r - width * 0.5, a), _on_ring(center, r + width * (0.65 if material == "wood" else 0.5), a), body.darkened(0.4), 1.5, true)
		_:
			# Coursed stone: a joint line and merlons on the outer face.
			draw_polyline(line, body.darkened(0.2), 1.0, true)
			var count := 64
			for i in count:
				var a := TAU * (i + 0.25) / count
				draw_line(_on_ring(center, r + width * 0.5, a), _on_ring(center, r + width * 0.5, a + TAU / count * 0.5), body.lightened(0.12), width * 0.35, true)
			if material == "fortress":
				# Round bastions between the wall slots, clear of the gate.
				for deg in [45.0, 165.0, 225.0, 285.0, 345.0]:
					var at := _on_ring(center, r, deg_to_rad(deg))
					draw_circle(at + Vector2(0, width * 0.3), width * 1.05, Color(0, 0, 0, 0.3))
					draw_circle(at, width * 1.0, body)
					draw_arc(at, width * 1.0, 0.0, TAU, 24, body.darkened(0.35), 1.5, true)


## The moat outside the walls (the ditch tower), along the outline: a dry
## ditch with stakes, water from walls.towers.ditch.waterAt.
func _draw_moat(center: Vector2, r: float, level: int) -> void:
	if level <= 0:
		return
	var width := _moat_width(level)
	var line := _ring(center, r * MOAT_RING)
	draw_polyline(line, Color("#3e3324"), width * 1.25, true)
	if WallText.moat_water(data, level):
		draw_polyline(line, MOAT_WATER, width, true)
		# The light's sheen on the water, towards the upper left.
		var sheen := PackedVector2Array()
		for i in 41:
			sheen.append(_on_ring(center, r * MOAT_RING - width * 0.15, PI + PI * 0.6 * i / 40.0))
		draw_polyline(sheen, Color(1, 1, 1, 0.18), width * 0.18, true)
	else:
		draw_polyline(line, Color("#5a4a33"), width * 0.8, true)
	draw_polyline(_ring(center, r * MOAT_RING - width * 0.55), Color("#4a3c2a", 0.7), 2.0, true)
	draw_polyline(_ring(center, r * MOAT_RING + width * 0.55), Color("#4a3c2a", 0.7), 2.0, true)
	if not WallText.moat_water(data, level):
		for i in 60:
			var a := TAU * i / 60.0
			draw_line(_on_ring(center, r * MOAT_RING + width * 0.55, a), _on_ring(center, r * MOAT_RING + width * 0.95, a), PALISADE.darkened(0.3), 1.5, true)


## The point at `angle` on a ring of radius `r` following the outline.
func _on_ring(center: Vector2, r: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * r * wobble(angle, _seed)


## A closed ring of radius `r` following the village's outline.
func _ring(center: Vector2, r: float, steps := 160) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps + 1:
		points.append(_on_ring(center, r, TAU * i / steps))
	return points


func _moat_width(level: int) -> float:
	return _radius * WALL_RING * (0.06 + 0.004 * level)


## The ground at `point`, its height in alpha (VillageGround): the square's
## beaten earth inside the walls, the moat, the meadow round the fields, the
## road out of the gate, and beyond the meadow wild grass and woods.
func _shade(point: Vector2) -> Color:
	var offset := point - _middle
	var angle := atan2(offset.y, offset.x)
	# How far out, on the village's own outline (1: the fields' ring).
	var t := offset.length() / (_radius * wobble(angle, _seed))
	var wild_mix := clampf(_woods.get_noise_2dv(point) * 1.6 + 0.45, 0.0, 1.0)
	var wild := Terrain.color("plains").darkened(0.08).lerp(Terrain.color("forest"), wild_mix)
	var color := Color(wild, 0.3 + 0.15 * wild_mix)
	# The meadow's edge swells further than the plots' outline (nothing
	# stands on it), so the village sits in an uneven clearing.
	var edge := 1.24 + 3.0 * (wobble(angle * 1.0 + 0.9, _seed + 5) - 1.0) + 0.04 * _woods.get_noise_2dv(point * 3.0)
	color = color.lerp(Color(MEADOW, 0.3), 1.0 - smoothstep(edge - 0.08, edge + 0.06, t))
	# The road from the gate out to the edge of the view.
	var gate := Vector2(cos(deg_to_rad(GATE_DEGREES)), sin(deg_to_rad(GATE_DEGREES)))
	var along := offset.dot(gate)
	var across := absf(offset.cross(gate) - sin(along * 0.012) * _radius * 0.06)
	if along > _radius * WALL_RING * 0.9:
		color = color.lerp(Color(ROAD_EARTH, 0.28), 1.0 - smoothstep(_radius * 0.035, _radius * 0.06, across))
	# Inside the walls: the square, lighter towards the Hall.
	var inside := 1.0 - smoothstep(WALL_RING - 0.02, WALL_RING + 0.01, t)
	var earth := SQUARE_EARTH.lerp(SQUARE_EDGE, smoothstep(0.3, WALL_RING, t))
	return color.lerp(Color(earth, 0.32), inside)


## Woods and brush beyond the meadow, each tree its own sprite, placed by
## the village's seed and drawn back to front; the road stays clear.
func _draw_wilds(center: Vector2, radius: float) -> void:
	var step := radius * 0.12
	var gate := Vector2(cos(deg_to_rad(GATE_DEGREES)), sin(deg_to_rad(GATE_DEGREES)))
	var trees := []
	var cols := ceili(size.x / step) + 1
	var rows := ceili(size.y / step) + 1
	for y in rows:
		for x in cols:
			var i := y * cols + x
			var p := Vector2((x + 0.5 + 0.4 * jitter(_seed, i)) * step, (y + 0.5 + 0.4 * jitter(_seed, i + 7919)) * step)
			var offset := p - center
			var t := offset.length() / (radius * wobble(atan2(offset.y, offset.x), _seed))
			var edge := 1.24 + 3.0 * (wobble(atan2(offset.y, offset.x) + 0.9, _seed + 5) - 1.0)
			if t < maxf(1.3, edge + 0.08):
				continue
			if offset.dot(gate) > 0.0 and absf(offset.cross(gate) - sin(offset.dot(gate) * 0.012) * radius * 0.06) < radius * 0.1:
				continue
			var woods := _woods.get_noise_2dv(p) * 1.6 + 0.35
			var pick := jitter(_seed, i + 31) * 0.5 + 0.5
			var id := ""
			if woods > 0.45:
				id = "feature/pine" if pick < 0.6 else "feature/oak"
			elif woods > 0.15 and pick < 0.45:
				id = "feature/oak" if pick < 0.15 else "feature/bush"
			elif pick < 0.12:
				id = "feature/grass"
			if id != "":
				trees.append([p, id, 1.0 + 0.15 * jitter(_seed, i + 99)])
	trees.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
	for tree in trees:
		var tex := Art.texture(tree[1])
		if tex == null:
			continue
		var w: float = radius * 0.14 * tree[2] * (0.6 if tree[1] == "feature/grass" or tree[1] == "feature/bush" else 1.0)
		var h := w * float(tex.get_height()) / float(tex.get_width())
		draw_texture_rect(tex, Rect2(tree[0] - Vector2(w / 2.0, h), Vector2(w, h)), false)


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
		_draw_progress(rect.get_center(), rect.size.x * 0.56, plot, 5.0)
	if id == "plot/locked":
		var needs := (tr("Walls %d") % Rules.tower_unlock_level(data, Rules.plot_index(plot))) if Rules.is_tower_slot(plot) else (tr("Hall %d") % Rules.slot_unlock_level(data, Rules.plot_index(plot)))
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
