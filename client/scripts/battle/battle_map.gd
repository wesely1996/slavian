class_name BattleMap
extends Control
## The battle as a campaign map on parchment (docs/reference/battle-map.jpg):
## our squads above, the enemy's below, each unit type a run of blocks with
## its map symbol in the side's colour and one label, fallen blocks left as
## ghosts; leaders as their own oval markers. The lines close in round by
## round. Show a battle with show_battle(); BattleStory does the counting.

const PARCHMENT := Color("#e8d8b0")
const STAIN := Color("#d6c08c")
const LIGHT := Color("#f3e7c6")
const BORDER := Color("#a8423a")
const INK := Color("#2b2118")
const ENEMY := Color("#d0453a")
const TREE := Color("#5f7f45")
const WATER := Color("#3f8fb0")
const ROAD := Color("#4a3b2a")
## Half the space between the lines before the first round, of the height.
const START_GAP := 0.09

var data: Dictionary = {}
var battle: Dictionary = {}
var round := 0
## Names and looks: {place, enemy, enemy_leader, leader, ours (colour),
## terrain, river (bool), road (bool)}.
var ctx: Dictionary = {}
var _font: Font


func _ready() -> void:
	_font = load(UiTheme.HEADING_FONT) if ResourceLoader.exists(UiTheme.HEADING_FONT) else ThemeDB.fallback_font
	resized.connect(queue_redraw)
	clip_contents = true


func show_battle(data_: Dictionary, battle_: Dictionary, round_: int, ctx_: Dictionary) -> void:
	data = data_
	battle = battle_
	round = round_
	ctx = ctx_
	queue_redraw()


func _draw() -> void:
	if battle.is_empty():
		return
	var area := Rect2(Vector2.ZERO, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(battle.get("id", 1)) * 7919
	_draw_parchment(area, rng)
	_draw_ground(area, rng)
	var rounds := int(data.get("battle", {}).get("maxRounds", 12))
	# The lines close in round by round; at walls, only once they're breached.
	var since := round - _breach_round()
	var closing := clampf(float(since) / float(maxi(1, rounds)) * 2.0, 0.0, 1.0)
	var start := BattleStory.units_at(battle, 0)
	var now := BattleStory.units_at(battle, round)
	# Armies that joined later hold their place from the start, as ghosts
	# until they come.
	var ours_start := _plus(start.defender, _joined_units())
	var ours: Color = ctx.get("ours", Color("#4caf50"))
	var gap := size.y * lerpf(START_GAP, 0.04, closing)
	var our_back := _draw_side(BattleStory.squads(data, ours_start, now.defender), ours, size.y / 2.0 - gap, -1)
	var their_back := _draw_side(BattleStory.squads(data, start.attacker, now.attacker), ENEMY, size.y / 2.0 + gap, 1)
	_draw_wall(size.y / 2.0 - gap * 0.2)
	if round > 0:
		_draw_clash(Vector2(size.x / 2.0, size.y / 2.0), size.x * 0.035)
	# Leaders stand behind their lines.
	if ctx.has("leader"):
		_draw_leader(Vector2(size.x * 0.5, maxf(our_back - size.x * 0.03, size.y * 0.15)), ours, ctx.leader)
	_draw_leader(Vector2(size.x * 0.5, minf(their_back + size.x * 0.03, size.y * 0.85)), ENEMY, ctx.get("enemy_leader", "Warlord"))
	_label(Vector2(size.x / 2.0, size.y * 0.035), ctx.get("place", ""), 22.0)
	_label(Vector2(size.x / 2.0, size.y * 0.975), "From the %s" % String(ctx.get("from", "wilds")), 18.0)
	var over: bool = round >= int(battle.get("rounds", []).size()) and battle.get("status", "ongoing") != "ongoing"
	if over:
		_draw_verdict()


func _draw_parchment(area: Rect2, rng: RandomNumberGenerator) -> void:
	draw_rect(area, PARCHMENT)
	for i in 7:
		var center := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		_blot(center, size.x * rng.randf_range(0.12, 0.3), Color(STAIN, 0.45), rng)
	for i in 4:
		var center := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		_blot(center, size.x * rng.randf_range(0.08, 0.2), Color(LIGHT, 0.6), rng)
	var inner := area.grow(-6.0)
	draw_rect(inner, BORDER, false, 3.0)
	draw_rect(inner.grow(-6.0), Color(BORDER, 0.5), false, 1.5)


## The battlefield's own ground: hills, woods, marsh, water and road.
func _draw_ground(_area: Rect2, rng: RandomNumberGenerator) -> void:
	var terrain := String(ctx.get("terrain", "plains"))
	match terrain:
		"hills", "mountain":
			for i in 3:
				var c := Vector2(rng.randf_range(0.1, 0.9) * size.x, rng.randf_range(0.15, 0.85) * size.y)
				for ring in 3:
					_blot(c, size.x * (0.16 - ring * 0.045), Color("#bfa46c", 0.28), rng)
		"forest", "dark_forest":
			for i in 5:
				var c := Vector2([rng.randf_range(0.04, 0.22), rng.randf_range(0.78, 0.96)][i % 2] * size.x, rng.randf_range(0.15, 0.85) * size.y)
				for t in 6:
					_tree(c + Vector2(rng.randf_range(-40, 40), rng.randf_range(-30, 30)), size.x * 0.018)
		"swamp", "lake":
			for i in 4:
				var c := Vector2([rng.randf_range(0.05, 0.2), rng.randf_range(0.8, 0.95)][i % 2] * size.x, rng.randf_range(0.2, 0.8) * size.y)
				for t in 5:
					_tuft(c + Vector2(rng.randf_range(-40, 40), rng.randf_range(-24, 24)), size.x * 0.016)
	if ctx.get("road", false):
		var road := PackedVector2Array()
		for i in 9:
			var t := i / 8.0
			road.append(Vector2(size.x * (0.62 + 0.08 * sin(t * 5.0 + rng.randf())), size.y * t))
		draw_polyline(road, ROAD, 2.0, true)
	if ctx.get("river", false):
		var river := PackedVector2Array()
		for i in 13:
			var t := i / 12.0
			river.append(Vector2(size.x * t, size.y * (0.5 + 0.12 * sin(t * 6.0 + 1.3))))
		draw_polyline(river, WATER, 3.0, true)


## One side's squads in rows by family, front row nearest the middle.
## `facing` -1: ours (above the line), 1: theirs (below). Gives the y behind
## the back row, where the leader stands.
func _draw_side(squads: Array, color: Color, front_y: float, facing: int) -> float:
	if squads.is_empty():
		return front_y
	var rows := {}
	for squad in squads:
		var key := BattleStory.FAMILY_ROWS.find(squad.family)
		if not rows.has(key):
			rows[key] = []
		rows[key].append(squad)
	var keys := rows.keys()
	keys.sort()
	var widest := 0
	for key in keys:
		var blocks := 0
		for squad in rows[key]:
			blocks += int(squad.blocks) + 1
		widest = maxi(widest, blocks)
	# Blocks fit the width, and the rows plus the leader fit the half
	# between the title and the line (as wide as it is at the start).
	var half := size.y * (0.5 - START_GAP - 0.07)
	var block_w := minf(minf(size.x * 0.06, (size.x * 0.88) / float(maxi(widest, 1))), half / (keys.size() * 1.51 + 1.9))
	var block := Vector2(block_w * 0.9, block_w * 0.62)
	var row_h := block.y + block_w * 0.95
	var y := front_y + facing * block.y * 0.6
	for key in keys:
		var row: Array = rows[key]
		var width := 0.0
		for squad in row:
			width += (int(squad.blocks) + 1) * block_w
		var x := (size.x - width + block_w) / 2.0
		for squad in row:
			_draw_squad(squad, Vector2(x, y), block, block_w, color, facing)
			x += (int(squad.blocks) + 1) * block_w
		y += facing * row_h
	return y + facing * block.y * 0.3


func _draw_squad(squad: Dictionary, origin: Vector2, block: Vector2, step: float, color: Color, facing: int) -> void:
	var blocks := int(squad.blocks)
	for i in blocks:
		var rect := Rect2(origin + Vector2(i * step, -block.y / 2.0), block)
		if i < int(squad.alive):
			draw_rect(rect, color)
			draw_rect(rect, INK, false, 2.0)
			_symbol(rect, String(squad.family))
		else:
			draw_rect(rect, Color(color, 0.15))
			draw_rect(rect, Color(INK, 0.3), false, 1.0)
	# One label for the whole squad, on its outer side.
	var span := Vector2(origin.x - step * 0.05, origin.x + (blocks - 1) * step + block.x)
	var label_y := origin.y + facing * (block.y * 0.5 + step * 0.42)
	var name := "%s %d" % [BattleStory.plural(BattleStory.unit_name(data, squad.unit), int(squad.now)), int(squad.now)]
	var icon := Art.texture("unit/" + String(squad.unit))
	var center := Vector2((span.x + span.y) / 2.0, label_y)
	if icon != null:
		var s := step * 0.75
		draw_texture_rect(icon, Rect2(center - Vector2(s / 2.0 + _width(name, maxf(14.0, step * 0.32)) / 2.0 + s * 0.1, s / 2.0), Vector2(s, s)), false)
		center.x += s * 0.55
	_label(center, name, maxf(14.0, step * 0.32))


## NATO-like marks: infantry ✕, cavalry a slash, archers a dot, scouts a
## ring.
func _symbol(rect: Rect2, family: String) -> void:
	var r := rect.grow(-rect.size.y * 0.18)
	match family:
		"infantry":
			draw_line(r.position, r.end, INK, 2.0, true)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), INK, 2.0, true)
		"cavalry":
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), INK, 2.0, true)
		"archers":
			draw_circle(r.get_center(), r.size.y * 0.24, INK)
		_:
			draw_arc(r.get_center(), r.size.y * 0.32, 0.0, TAU, 16, INK, 2.0, true)


func _draw_leader(at: Vector2, color: Color, name: String) -> void:
	var rect := Rect2(at - Vector2(size.x * 0.035, size.x * 0.022), Vector2(size.x * 0.07, size.x * 0.044))
	draw_rect(rect, color)
	draw_rect(rect, INK, false, 2.0)
	var oval := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		oval.append(rect.get_center() + Vector2(cos(a) * rect.size.x * 0.34, sin(a) * rect.size.y * 0.3))
	draw_polyline(oval, INK, 2.0, true)
	draw_line(rect.get_center() + Vector2(-rect.size.x * 0.26, rect.size.y * 0.22), rect.get_center() + Vector2(rect.size.x * 0.26, -rect.size.y * 0.22), INK, 2.0, true)
	# The name on the outer side, away from the lines.
	_label(at + Vector2(0, (rect.size.y * 0.5 + 12.0) * (-1.0 if at.y < size.y / 2.0 else 1.0)), name, 17.0)


## Our walls between the lines, what is left of them after the round
## shown: whole, battered (cracked, its strength under it), or breached (a
## gap of rubble in the middle).
func _draw_wall(y: float) -> void:
	var setup: Dictionary = battle.get("setup", {}) if battle.get("setup") is Dictionary else {}
	if not setup.has("wall"):
		return
	var wall: Dictionary = setup.wall
	var left := int(wall.max)
	for entry in battle.get("rounds", []):
		if int(entry.round) <= round and entry.has("wallLeft"):
			left = int(entry.wallLeft)
	var h := size.y * 0.025
	var x0 := size.x * 0.06
	var x1 := size.x * 0.94
	var stone := Color("#8f897e") if int(wall.level) >= 4 else Color("#8a5e3a")
	var gap := Vector2(size.x * 0.44, size.x * 0.56) if left <= 0 else Vector2(size.x * 0.5, size.x * 0.5)
	for span in [Vector2(x0, gap.x), Vector2(gap.y, x1)]:
		if span.y <= span.x:
			continue
		draw_rect(Rect2(span.x, y - h, span.y - span.x, h * 2.0), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(span.x, y - h * 1.2, span.y - span.x, h * 2.0), stone)
		var step := h * 1.6
		var x: float = span.x
		while x < span.y - step * 0.5:
			draw_rect(Rect2(x, y - h * 1.9, step * 0.55, h * 0.7), stone.lightened(0.15))
			x += step
		draw_rect(Rect2(span.x, y - h * 1.2, span.y - span.x, h * 2.0), INK, false, 1.5)
	if left <= 0:
		for i in 7:
			var p := Vector2(lerpf(gap.x, gap.y, (i + 0.5) / 7.0), y + (i % 3 - 1) * h * 0.5)
			draw_circle(p, h * 0.55, stone.darkened(0.2))
		_label(Vector2(size.x / 2.0, y + h * 3.0), "Breach!", 20.0)
	else:
		var share := float(left) / maxf(1.0, float(wall.max))
		if share < 1.0:
			for i in int((1.0 - share) * 6.0):
				var cx := lerpf(x0, x1, (i * 0.37 + 0.11) - floor(i * 0.37 + 0.11))
				draw_line(Vector2(cx, y - h), Vector2(cx + h * 0.6, y + h * 0.6), INK, 1.5, true)
		var text := "%s  %d / %d" % [WallText.tier(data, int(wall.level)), left, int(wall.max)]
		_label(Vector2(x0 + _width(text, 16.0) / 2.0 + 6.0, y + h * 2.4), text, 16.0)


func _draw_clash(at: Vector2, r: float) -> void:
	for dir in [Vector2(1, 1), Vector2(-1, 1)]:
		draw_line(at - dir * r, at + dir * r, INK, 4.0, true)
		draw_line(at + dir * r * 0.55 + Vector2(dir.y, -dir.x) * r * 0.25, at + dir * r * 0.55 - Vector2(dir.y, -dir.x) * r * 0.25, INK, 3.0, true)


func _draw_verdict() -> void:
	var status := String(battle.get("status", ""))
	var won := status == "defended" or status == "cleared"
	var assault := battle.get("campId") != null or battle.get("siteId") != null
	if assault and status == "defended":
		won = false
	var text := ("Victory" if won else "Defeat")
	var font_size := size.x * 0.09
	var width := _width(text, font_size)
	var at := Vector2(size.x / 2.0, size.y / 2.0)
	draw_rect(Rect2(at - Vector2(width * 0.65, font_size * 0.62), Vector2(width * 1.3, font_size * 1.1)), Color(PARCHMENT, 0.85))
	draw_string_outline(_font, at + Vector2(-width / 2.0, font_size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), 6, LIGHT)
	draw_string(_font, at + Vector2(-width / 2.0, font_size * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), Color("#3c7a2c") if won else BORDER)


func _label(center: Vector2, text: String, font_size: float) -> void:
	if text == "":
		return
	var width := _width(text, font_size)
	var at := center + Vector2(-width / 2.0, font_size * 0.35)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), 4, Color(LIGHT, 0.9))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), INK)


func _width(text: String, font_size: float) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size)).x


func _blot(center: Vector2, radius: float, color: Color, rng: RandomNumberGenerator) -> void:
	var points := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		points.append(center + Vector2(cos(a), sin(a) * 0.7) * radius * rng.randf_range(0.7, 1.15))
	draw_colored_polygon(points, color)


func _tree(at: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.6), at + Vector2(s, 0), at + Vector2(-s, 0)]), TREE)
	draw_line(at, at + Vector2(0, s * 0.5), INK, 1.5)


func _tuft(at: Vector2, s: float) -> void:
	for dx in [-0.6, 0.0, 0.6]:
		draw_line(at + Vector2(dx * s, 0), at + Vector2(dx * s * 1.5, -s * (1.3 if dx == 0.0 else 0.9)), TREE, 2.0, true)


## The round the walls fell in (the lines close from then on); 0 without
## walls, beyond the last round while they stand.
func _breach_round() -> int:
	var setup: Dictionary = battle.get("setup", {}) if battle.get("setup") is Dictionary else {}
	if not setup.has("wall"):
		return 0
	for entry in battle.get("rounds", []):
		if entry.get("breach", false):
			return int(entry.round)
	return 9999


## Every army that ever joined, by unit, so the squads keep their place.
func _joined_units() -> Dictionary:
	var out := {}
	for entry in battle.get("rounds", []):
		for army in entry.get("joined", []):
			for unit in army.units:
				out[unit] = int(out.get(unit, 0)) + int(army.units[unit])
	return out


func _plus(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for unit in b:
		out[unit] = int(out.get(unit, 0)) + int(b[unit])
	return out
