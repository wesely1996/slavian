class_name HexMap
extends Node2D
## Draws the current world's map (Game.terrain), villages and enemy hordes,
## from the art in client/art/art.json (docs/art-style.md), falling back to
## plain shapes where a piece is missing. Neighbouring hexes of one terrain
## merge: lines are drawn only where the terrain changes. Owners show by
## colour: green yours, blue allies', red enemies'. Redraws when something
## changes, and on every UI tick while a horde is on the move.

const OUTLINE_COLOR := Color(0, 0, 0, 0.25)
const SELECTION_COLOR := Color("#ffd75e")
const HOLY_CITY_COLOR := Color("#8a2b2b")
const MY_VILLAGE_COLOR := Color("#ffd75e")
const ALLY_VILLAGE_COLOR := Color("#f4efe1")
const VILLAGE_OUTLINE_COLOR := Color("#2b2118")
const HORDE_PATH_COLOR := Color(0.78, 0.22, 0.18, 0.6)
const RUINS_COLOR := Color("#6d655a")
const CARAVAN_COLOR := Color("#c99a5b")
const SETTLERS_COLOR := Color("#e8e2d0")
const HERO_COLOR := Color("#9b7bd4")
const ARMY_COLOR := Color("#5b8fd6")
const FORT_COLOR := Color("#8b6a45")
const SITE_COLOR := Color("#d9b85c")
## Sides, for banners and outlines.
const MINE_COLOR := Color("#4caf50")
const ALLY_COLOR := Color("#3f7fd6")
const ENEMY_COLOR := Color("#d0453a")
const SHORE_COLOR := Color(0.17, 0.13, 0.09, 0.35)
const RIVER_COLOR := Color("#4f8fb0")
const PLANK_COLOR := Color("#b07a45")
## Each front's emblem (art id "faction/<emblem>").
const EMBLEMS := {"north": "north", "east": "east", "south": "order", "west": "order"}

@export var hex_size := 48.0

var radius := 0
var selected := Vector2i.MAX


func refresh() -> void:
	var map: Variant = Game.world.get("map")
	radius = int(map.radius) if map is Dictionary else 0
	queue_redraw()


func has_hex(cell: Vector2i) -> bool:
	return Game.terrain.has(cell)


func local_to_hex(local_position: Vector2) -> Vector2i:
	return HexMath.from_pixel(local_position, hex_size)


func hex_to_local(cell: Vector2i) -> Vector2:
	return HexMath.to_pixel(cell, hex_size)


func select(cell: Vector2i) -> void:
	selected = cell
	queue_redraw()


## Bounding rectangle of all hex centres, in local coordinates.
func get_bounds() -> Rect2:
	var extent := HexMath.to_pixel(Vector2i(radius, 0), hex_size).x
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


func _draw() -> void:
	for cell in Game.terrain:
		_draw_terrain(cell)
	for cell in Game.terrain:
		_draw_shores(cell)
	for edge in Game.rivers:
		_draw_river(edge)

	if Game.terrain.has(Vector2i.ZERO):
		if not _draw_art("settlement/holy_city", Vector2.ZERO, hex_size * 1.5):
			draw_circle(Vector2.ZERO, hex_size * 0.45, HOLY_CITY_COLOR)
	for village in Game.villages.values():
		for plot in Rules.outpost_plots(village):
			_draw_outpost(Rules.outpost_hex(plot), int(village.plots[plot].level), Game.is_mine(village))
	for village in Game.villages.values():
		_draw_village(village)

	var now := Game.server_now()
	for caravan in Game.caravans:
		var p := CaravanMath.progress(caravan, now)
		if not p.is_empty():
			var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
			draw_circle(pos, hex_size * 0.2, CARAVAN_COLOR)
			draw_arc(pos, hex_size * 0.2, 0.0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)
	for expedition in Game.expeditions:
		var p := CaravanMath.progress(expedition, now)
		if not p.is_empty():
			var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
			if _draw_art("unit/settler", pos, hex_size * 0.5):
				continue
			var r := hex_size * 0.22
			var tri := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, r * 0.8), pos + Vector2(-r, r * 0.8)])
			draw_colored_polygon(tri, SETTLERS_COLOR)
			tri.append(tri[0])
			draw_polyline(tri, VILLAGE_OUTLINE_COLOR, 2.0)
	for fort in Game.forts:
		_draw_fort(fort)
	for camp in Game.camps:
		_draw_camp(camp)
	for site in Game.sites:
		_draw_site(site)
	for army in Game.armies:
		_draw_army(army, now)
	for hero in Game.heroes:
		_draw_hero(hero, now)
	for wave in WaveMath.visible_waves(Game.waves):
		_draw_horde(wave, now)

	if has_hex(selected):
		var outline := HexMath.corners(HexMath.to_pixel(selected, hex_size), hex_size * 0.92)
		outline.append(outline[0])
		draw_polyline(outline, SELECTION_COLOR, 4.0)


## A hex in its terrain's art, mirrored on every other hex so neighbours
## don't repeat in step; a flat colour without art.
func _draw_terrain(cell: Vector2i) -> void:
	var c := HexMath.to_pixel(cell, hex_size)
	var points := HexMath.corners(c, hex_size)
	var tex := Art.texture("terrain/" + Game.terrain[cell])
	if tex == null:
		draw_colored_polygon(points, Terrain.color(Game.terrain[cell]))
		return
	var flip := posmod(cell.x + cell.y * 2, 2) == 1
	var uvs := PackedVector2Array()
	for p in points:
		var u := (p.x - c.x) / (sqrt(3.0) * hex_size) + 0.5
		var v := (p.y - c.y) / (2.0 * hex_size) + 0.5
		uvs.append(Vector2(1.0 - u if flip else u, v))
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, tex)


## Lines only where the terrain changes, so forests, ranges and lakes read as
## one region. Each edge is drawn once, from the cell with the smaller key.
func _draw_shores(cell: Vector2i) -> void:
	var points := HexMath.corners(HexMath.to_pixel(cell, hex_size), hex_size)
	var kind: String = Game.terrain[cell]
	for i in 6:
		var other := cell + HexMath.DIRECTIONS[i]
		if not Game.terrain.has(other):
			continue
		if Game.terrain[other] == kind or (other.x < cell.x or (other.x == cell.x and other.y < cell.y)):
			continue
		var edge := _edge(points, i)
		draw_line(edge[0], edge[1], SHORE_COLOR, 2.0)


## A river along the edge between two hexes, and its bridge if one stands
## (faded while being built).
func _draw_river(edge: Array) -> void:
	var a := Vector2i(int(edge[0]), int(edge[1]))
	var b := Vector2i(int(edge[2]), int(edge[3]))
	var dir := RiverText.direction(a, b)
	if dir < 0:
		return
	var ends := _edge(HexMath.corners(HexMath.to_pixel(a, hex_size), hex_size), dir)
	draw_line(ends[0], ends[1], VILLAGE_OUTLINE_COLOR, hex_size * 0.2, true)
	draw_line(ends[0], ends[1], RIVER_COLOR, hex_size * 0.12, true)
	draw_circle(ends[0], hex_size * 0.06, RIVER_COLOR)
	draw_circle(ends[1], hex_size * 0.06, RIVER_COLOR)
	if String(edge[4]) == "none":
		return
	var mid: Vector2 = (ends[0] + ends[1]) / 2.0
	var across := (HexMath.to_pixel(b, hex_size) - HexMath.to_pixel(a, hex_size)).normalized()
	var tint := Color.WHITE if String(edge[4]) == "standing" else Color(1, 1, 1, 0.5)
	draw_line(mid - across * hex_size * 0.3, mid + across * hex_size * 0.3, VILLAGE_OUTLINE_COLOR * tint, hex_size * 0.3)
	draw_line(mid - across * hex_size * 0.27, mid + across * hex_size * 0.27, PLANK_COLOR * tint, hex_size * 0.22)


## The corners shared with the neighbour in direction i (E, NE, NW, W, SW, SE).
func _edge(points: PackedVector2Array, i: int) -> Array:
	# Corners run from -30° (upper right) clockwise in 60° steps.
	var first: int = [0, 5, 4, 3, 2, 1][i]
	return [points[first], points[(first + 1) % 6]]


## Draws art id centred at `center`, `size` wide; false if there is no art.
func _draw_art(id: String, center: Vector2, size: float, tint := Color.WHITE) -> bool:
	var tex := Art.texture(id)
	if tex == null:
		return false
	var s := tex.get_size()
	var h := size * s.y / s.x
	draw_texture_rect(tex, Rect2(center - Vector2(size, h) / 2.0, Vector2(size, h)), false, tint)
	return true


## A side's mark under something on the map: a ring in its colour.
func _draw_ring(center: Vector2, width: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		points.append(center + Vector2(cos(a) * width / 2.0, sin(a) * width * 0.17))
	draw_colored_polygon(points, Color(color, 0.22))
	draw_polyline(points, color, 3.0)


## The owner's banner beside something they hold.
func _draw_banner(base: Vector2, height: float, color: Color) -> void:
	var w := height * 64.0 / 96.0
	var rect := Rect2(base - Vector2(w * 0.22, height), Vector2(w, height))
	var pole := Art.texture("banner/pole")
	var cloth := Art.texture("banner/cloth")
	if pole == null or cloth == null:
		draw_line(base, base - Vector2(0, height), VILLAGE_OUTLINE_COLOR, 2.0)
		draw_rect(Rect2(base - Vector2(0, height), Vector2(height * 0.45, height * 0.35)), color)
		return
	draw_texture_rect(pole, rect, false)
	draw_texture_rect(cloth, rect, false, color)


## A village: its look by Elder's Hall level (or ruins), ringed and bannered
## in its owner's colour.
func _draw_village(village: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size)
	var ruined: bool = village.get("ruin") is Dictionary
	var side := MINE_COLOR if Game.is_mine(village) else ALLY_COLOR
	var id := "settlement/ruins" if ruined else Art.settlement_id(int(village.get("levels", {}).get("elder_hall", 1)))
	_draw_ring(c + Vector2(0, hex_size * 0.42), hex_size * 1.5, side)
	if _draw_art(id, c + Vector2(0, -hex_size * 0.05), hex_size * 1.4):
		if not ruined:
			_draw_banner(c + Vector2(hex_size * 0.62, hex_size * 0.2), hex_size * 0.75, side)
		return
	var half := hex_size * 0.3
	var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
	draw_rect(rect, RUINS_COLOR if ruined else (MY_VILLAGE_COLOR if Game.is_mine(village) else ALLY_VILLAGE_COLOR))
	draw_rect(rect, VILLAGE_OUTLINE_COLOR, false, 2.0)
	if ruined:
		draw_line(rect.position, rect.end, VILLAGE_OUTLINE_COLOR, 3.0)
		draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), VILLAGE_OUTLINE_COLOR, 3.0)


## A small watchtower: its art ringed in the owner's colour, faded while in
## ruins or under construction (a diamond without art).
func _draw_outpost(cell: Vector2i, level: int, mine: bool) -> void:
	var c := HexMath.to_pixel(cell, hex_size)
	var side := MINE_COLOR if mine else ALLY_COLOR
	if Art.has("map/outpost"):
		_draw_ring(c + Vector2(0, hex_size * 0.32), hex_size * 0.9, side)
		_draw_art("map/outpost", c, hex_size * 0.85, Color(1, 1, 1, 0.55) if level <= 0 else Color.WHITE)
		return
	var r := hex_size * 0.26
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	var fill := RUINS_COLOR if level <= 0 else (MY_VILLAGE_COLOR if mine else ALLY_VILLAGE_COLOR)
	draw_colored_polygon(diamond, fill)
	diamond.append(diamond[0])
	draw_polyline(diamond, VILLAGE_OUTLINE_COLOR, 2.0)


## An army: a blue shield on the road, or beside the village it guards.
func _draw_army(army: Dictionary, now: float) -> void:
	var pos := Vector2.INF
	var p := ArmyText.progress(army, now)
	if not p.is_empty():
		pos = HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	elif army.status in ["stationed", "engaged"] and ArmyText.held_hex(army) != Vector2i.MAX:
		pos = HexMath.to_pixel(ArmyText.held_hex(army), hex_size) + Vector2(hex_size * 0.36, hex_size * 0.3)
	elif army.status in ["stationed", "engaged"]:
		var village: Dictionary = Game.villages.get(int(army.targetVillageId), {})
		if not village.is_empty():
			pos = HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size) + Vector2(-hex_size * 0.42, hex_size * 0.38)
	if pos == Vector2.INF:
		return
	var side := MINE_COLOR if int(army.get("ownerAccountId", -1)) == Game.my_account_id() else ALLY_COLOR
	if Art.has("unit/" + ArmyText.main_unit(army)):
		draw_circle(pos, hex_size * 0.27, side)
		_draw_art("unit/" + ArmyText.main_unit(army), pos, hex_size * 0.46)
		return
	var r := hex_size * 0.2
	var shield := PackedVector2Array([pos + Vector2(-r, -r), pos + Vector2(r, -r), pos + Vector2(r, r * 0.3), pos + Vector2(0, r * 1.2), pos + Vector2(-r, r * 0.3)])
	draw_colored_polygon(shield, ARMY_COLOR)
	shield.append(shield[0])
	draw_polyline(shield, VILLAGE_OUTLINE_COLOR, 2.0)


## An ancient site: a standing stone, gold until explored.
func _draw_site(site: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(site.q), int(site.r)), hex_size)
	# Searched sites fade into the land.
	if _draw_art("site/" + String(site.kind), c, hex_size * 1.1, Color.WHITE if site.status == "unexplored" else Color(0.75, 0.72, 0.68, 0.7)):
		return
	var w := hex_size * 0.13
	var h := hex_size * 0.34
	var stone := PackedVector2Array([c + Vector2(-w, h * 0.7), c + Vector2(-w * 1.2, -h * 0.4), c + Vector2(0, -h), c + Vector2(w * 1.2, -h * 0.4), c + Vector2(w, h * 0.7)])
	draw_colored_polygon(stone, SITE_COLOR if site.status == "unexplored" else RUINS_COLOR)
	stone.append(stone[0])
	draw_polyline(stone, VILLAGE_OUTLINE_COLOR, 2.0)


## A bandit camp or monster lair: a tent in its faction's colour.
func _draw_camp(camp: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(camp.q), int(camp.r)), hex_size)
	if Art.has("map/camp_" + String(camp.kind)):
		_draw_ring(c + Vector2(0, hex_size * 0.4), hex_size * 1.2, ENEMY_COLOR)
		_draw_art("map/camp_" + String(camp.kind), c, hex_size * 1.15)
		return
	var r := hex_size * 0.32
	var tent := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.7), c + Vector2(-r, r * 0.7)])
	draw_colored_polygon(tent, WaveMath.front_color(String(camp.front)).darkened(0.25))
	tent.append(tent[0])
	draw_polyline(tent, VILLAGE_OUTLINE_COLOR, 2.0)
	draw_line(c + Vector2(0, -r * 0.1), c + Vector2(0, r * 0.7), VILLAGE_OUTLINE_COLOR, 2.0)


## A fort: a squat tower with battlements, faded while being built.
func _draw_fort(fort: Dictionary) -> void:
	var c := HexMath.to_pixel(Vector2i(int(fort.q), int(fort.r)), hex_size)
	if Art.has("map/fort"):
		var side := MINE_COLOR if int(fort.get("ownerAccountId", -1)) == Game.my_account_id() else ALLY_COLOR
		_draw_ring(c + Vector2(0, hex_size * 0.42), hex_size * 1.2, side)
		_draw_art("map/fort", c, hex_size * 1.1, Color.WHITE if fort.status == "standing" else Color(1, 1, 1, 0.5))
		return
	var w := hex_size * 0.3
	var h := hex_size * 0.26
	var tower := PackedVector2Array([
		c + Vector2(-w, h), c + Vector2(-w, -h), c + Vector2(-w * 0.5, -h), c + Vector2(-w * 0.5, -h * 0.6),
		c + Vector2(-w * 0.1, -h * 0.6), c + Vector2(-w * 0.1, -h), c + Vector2(w * 0.1, -h), c + Vector2(w * 0.1, -h * 0.6),
		c + Vector2(w * 0.5, -h * 0.6), c + Vector2(w * 0.5, -h), c + Vector2(w, -h), c + Vector2(w, h)])
	draw_colored_polygon(tower, FORT_COLOR if fort.status == "standing" else RUINS_COLOR)
	tower.append(tower[0])
	draw_polyline(tower, VILLAGE_OUTLINE_COLOR, 2.0)


## A hero: a small banner by its village, or on the road between two.
func _draw_hero(hero: Dictionary, now: float) -> void:
	var pos := Vector2.INF
	if hero.status == "traveling" and hero.path != null:
		var p := CaravanMath.progress({"status": "outbound", "departsAt": hero.departsAt, "path": hero.path}, now)
		if not p.is_empty():
			pos = HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	elif hero.villageId != null:
		var village: Dictionary = Game.villages.get(int(hero.villageId), {})
		if not village.is_empty():
			pos = HexMath.to_pixel(Vector2i(int(village.q), int(village.r)), hex_size) + Vector2(-hex_size * 0.42, -hex_size * 0.38)
	if pos == Vector2.INF:
		return
	var color := HERO_COLOR.darkened(0.45) if hero.status == "wounded" else HERO_COLOR
	draw_circle(pos, hex_size * 0.17, color)
	draw_arc(pos, hex_size * 0.17, 0.0, TAU, 16, VILLAGE_OUTLINE_COLOR, 2.0)


func has_moving_hordes() -> bool:
	return Game.waves.any(func(w: Dictionary) -> bool: return w.status == "marching") \
		or Game.caravans.any(func(c: Dictionary) -> bool: return c.status != "done") \
		or Game.expeditions.any(func(e: Dictionary) -> bool: return e.status in ["outbound", "returning"]) \
		or Game.heroes.any(func(h: Dictionary) -> bool: return h.status == "traveling") \
		or Game.armies.any(func(a: Dictionary) -> bool: return a.status in ["marching", "returning"])


func _draw_horde(wave: Dictionary, now: float) -> void:
	var p := WaveMath.progress(wave, now)
	if p.is_empty():
		return
	var pos := HexMath.to_pixel(p.from, hex_size).lerp(HexMath.to_pixel(p.to, hex_size), p.t)
	if wave.status == "marching":
		# The road still ahead, from the horde to its target.
		var trail := PackedVector2Array([pos])
		var ahead := false
		for step in wave.path:
			var cell := Vector2i(int(step[0]), int(step[1]))
			ahead = ahead or cell == p.to
			if ahead:
				trail.append(HexMath.to_pixel(cell, hex_size))
		if trail.size() >= 2:
			draw_polyline(trail, HORDE_PATH_COLOR, 5.0)
	else:
		# Camped at the gates: sit beside the village so both stay visible.
		pos += Vector2(hex_size * 0.42, -hex_size * 0.42)
	var emblem := "faction/" + String(EMBLEMS.get(String(wave.get("front", "north")), "north"))
	if Art.has(emblem):
		draw_circle(pos, hex_size * 0.42, ENEMY_COLOR)
		_draw_art(emblem, pos, hex_size * 0.72)
		return
	draw_circle(pos, hex_size * 0.34, WaveMath.front_color(String(wave.get("front", "north"))))
	draw_arc(pos, hex_size * 0.34, 0.0, TAU, 24, VILLAGE_OUTLINE_COLOR, 2.0)
