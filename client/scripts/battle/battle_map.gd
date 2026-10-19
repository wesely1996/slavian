class_name BattleMap
extends Control
## The battle as a campaign map on parchment (docs/reference/battle-map.jpg):
## our squads above, the enemy's below, each unit type a run of blocks with
## its map symbol in the side's colour and one label, fallen blocks left as
## ghosts; leaders as their own oval markers. The lines close in round by
## round. At walls they run from border to border in their material, the
## moat before them; our archers stand on them, the enemy's engines at their
## foot and its climbers on them. A river is drawn only where it is an
## obstacle: across the field at a crossing, else along a flank. Show a
## battle with show_battle(); BattleStory does the counting.

const PARCHMENT := Color("#e8d8b0")
const STAIN := Color("#d6c08c")
const LIGHT := Color("#f3e7c6")
const BORDER := Color("#a8423a")
const INK := Color("#2b2118")
const ENEMY := Color("#d0453a")
const TREE := Color("#5f7f45")
const WATER := Color("#3f8fb0")
const ROAD := Color("#4a3b2a")
const BANK := Color("#b49a64")
const WALL_COLORS := {
	"wood": Color("#8a5e3a"),
	"timber": Color("#7f6440"),
	"stone": Color("#8f897e"),
	"fortress": Color("#a7a091"),
}
## Half the space between the lines before the first round, of the height.
const START_GAP := 0.09

var data: Dictionary = {}
var battle: Dictionary = {}
var round := 0
## Names and looks: {place, enemy, enemy_leader, leader, ours (colour),
## terrain, river (bool), road (bool)}.
var ctx: Dictionary = {}
var _font: Font
## The part of the width the squads stand in (a river along a flank takes
## the rest), as fractions.
var _field := Vector2(0.0, 1.0)


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
	_field = Vector2(0.0, 1.0)
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
	var wall_y := size.y / 2.0 - gap * 0.2
	var standing := _wall_standing()
	# At walls the river they crossed lies behind the horde.
	if _crossing():
		_draw_river_across(size.y * (0.9 if _has_wall() else 0.5), rng)
	_draw_moat(wall_y)
	_draw_wall(wall_y)
	# While the walls stand our archers are up on them and the enemy's
	# engines stand at their foot.
	var our_squads := BattleStory.squads(data, ours_start, now.defender)
	var on_walls := []
	if standing:
		on_walls = our_squads.filter(func(q: Dictionary) -> bool: return q.family == "archers")
		our_squads = our_squads.filter(func(q: Dictionary) -> bool: return q.family != "archers")
	var their_squads := BattleStory.squads(data, start.attacker, now.attacker)
	var engines := []
	if standing:
		engines = their_squads.filter(func(q: Dictionary) -> bool: return BattleStory.is_engine(data, q.unit))
		their_squads = their_squads.filter(func(q: Dictionary) -> bool: return not BattleStory.is_engine(data, q.unit))
	# Room for the men on the walls and the engines at their foot.
	var room := size.y * 0.05 if standing else 0.0
	var our_back := _draw_side(our_squads, ours, size.y / 2.0 - gap - room * 0.6, -1, room * 0.6)
	var their_back := _draw_side(their_squads, ENEMY, size.y / 2.0 + gap + room, 1, room)
	_draw_on_walls(on_walls, ours, wall_y)
	_draw_engines(engines, wall_y)
	if standing:
		_draw_climbers(wall_y)
	if round > 0:
		_draw_clash(Vector2(size.x / 2.0, size.y / 2.0), size.x * 0.035)
	# Leaders stand behind their lines.
	if ctx.has("leader"):
		_draw_leader(Vector2(size.x * 0.5, maxf(our_back - size.x * 0.03, size.y * 0.15)), ours, ctx.leader)
	_draw_leader(Vector2(size.x * 0.5, minf(their_back + size.x * 0.03, size.y * 0.85)), ENEMY, ctx.get("enemy_leader", tr("Warlord")))
	_label(Vector2(size.x / 2.0, size.y * 0.035), ctx.get("place", ""), 22.0)
	_label(Vector2(size.x / 2.0, size.y * 0.975), tr("From the %s") % String(ctx.get("from", "wilds")), 18.0)
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
	# A river is an obstacle, never a stream: across the field where the
	# horde came over it, else along a flank, where the lines can't stand.
	if ctx.get("river", false) and not _crossing():
		_draw_river_flank(rng)


## One side's squads in rows by family, front row nearest the middle.
## `facing` -1: ours (above the line), 1: theirs (below). Gives the y behind
## the back row, where the leader stands. `room`: how much further from the
## middle the side starts than usual.
func _draw_side(squads: Array, color: Color, front_y: float, facing: int, room := 0.0) -> float:
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
	var half := size.y * (0.5 - START_GAP - 0.07) - room
	var span := size.x * (_field.y - _field.x)
	var block_w := minf(minf(size.x * 0.06, (span * 0.88) / float(maxi(widest, 1))), half / (keys.size() * 1.51 + 2.6))
	var block := Vector2(block_w * 0.9, block_w * 0.62)
	var row_h := block.y + block_w * 0.95
	var y := front_y + facing * block.y * 0.6
	for key in keys:
		var row: Array = rows[key]
		var width := 0.0
		for squad in row:
			width += (int(squad.blocks) + 1) * block_w
		var x := size.x * _field.x + (span - width + block_w) / 2.0
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
	var name := tr("%s %d") % [BattleStory.plural(BattleStory.unit_name(data, squad.unit), int(squad.now)), int(squad.now)]
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


## Our walls between the lines from border to border, in their material,
## what is left of them after the round shown: whole, battered (cracked,
## its strength under it), or breached (a gap of rubble in the middle).
func _draw_wall(y: float) -> void:
	if not _has_wall():
		return
	var wall: Dictionary = _setup().wall
	var left := _wall_left()
	var material := WallText.material(data, int(wall.level))
	var h: float = size.y * {"wood": 0.026, "timber": 0.03, "stone": 0.032, "fortress": 0.036}.get(material, 0.03)
	var body: Color = WALL_COLORS.get(material, WALL_COLORS.stone)
	var gap := Vector2(size.x * 0.43, size.x * 0.57) if left <= 0 else Vector2(size.x * 0.5, size.x * 0.5)
	for span in [Vector2(0.0, gap.x), Vector2(gap.y, size.x)]:
		if span.y <= span.x:
			continue
		var w: float = span.y - span.x
		draw_rect(Rect2(span.x, y - h * 0.8, w, h * 2.0), Color(0, 0, 0, 0.25))
		if material == "timber":
			# The earth bank the breastwork stands on.
			draw_rect(Rect2(span.x, y - h * 0.4, w, h * 1.5), Color("#9a7f55"))
		draw_rect(Rect2(span.x, y - h * 1.2, w, h * 2.0), body)
		match material:
			"wood", "timber":
				# Upright logs, the palisade's sharpened to points.
				var step: float = h * (0.55 if material == "wood" else 0.75)
				var x: float = span.x
				while x < span.y:
					draw_line(Vector2(x, y - h * 1.2), Vector2(x, y + h * 0.8), body.darkened(0.35), 1.0)
					if material == "wood":
						draw_colored_polygon(PackedVector2Array([Vector2(x, y - h * 1.2), Vector2(minf(x + step, span.y), y - h * 1.2), Vector2(minf(x + step * 0.5, span.y), y - h * 1.75)]), body)
					x += step
			_:
				# Coursed stone with merlons; fortress walls with round towers.
				draw_line(Vector2(span.x, y - h * 0.2), Vector2(span.y, y - h * 0.2), body.darkened(0.2), 1.0)
				draw_line(Vector2(span.x, y + h * 0.35), Vector2(span.y, y + h * 0.35), body.darkened(0.2), 1.0)
				var step: float = h * 1.6
				var x: float = span.x
				while x < span.y - step * 0.3:
					draw_rect(Rect2(x, y - h * 1.9, step * 0.55, h * 0.7), body.lightened(0.15))
					x += step
				if material == "fortress":
					var every := size.x / 6.0
					var tx := every / 2.0
					while tx < size.x:
						if tx > span.x + h and tx < span.y - h:
							draw_rect(Rect2(tx - h * 1.1, y - h * 2.1, h * 2.2, h * 3.4), body.lightened(0.05))
							draw_rect(Rect2(tx - h * 1.1, y - h * 2.1, h * 2.2, h * 3.4), INK, false, 1.5)
						tx += every
		draw_rect(Rect2(span.x, y - h * 1.2, w, h * 2.0), INK, false, 1.5)
	var label_at := Vector2(size.x * (_field.x + 0.03), y + h * 2.4)
	if left <= 0:
		for i in 7:
			var p := Vector2(lerpf(gap.x, gap.y, (i + 0.5) / 7.0), y + (i % 3 - 1) * h * 0.5)
			draw_circle(p, h * 0.55, body.darkened(0.2))
		var breached := tr("%s breached!") % WallText.tier(data, int(wall.level))
		_label(label_at + Vector2(_width(breached, 18.0) / 2.0 + 6.0, 0), breached, 18.0)
	else:
		var share := float(left) / maxf(1.0, float(wall.max))
		if share < 1.0:
			for i in int((1.0 - share) * 6.0):
				var cx: float = size.x * ((i * 0.37 + 0.11) - floor(i * 0.37 + 0.11))
				draw_line(Vector2(cx, y - h), Vector2(cx + h * 0.6, y + h * 0.6), INK, 1.5, true)
		var text := tr("%s  %d / %d") % [WallText.tier(data, int(wall.level)), left, int(wall.max)]
		_label(label_at + Vector2(_width(text, 16.0) / 2.0 + 6.0, 0), text, 16.0)


## The moat before the walls, on the enemy's side: a dry ditch with stakes,
## or water.
func _draw_moat(y: float) -> void:
	if not _has_wall():
		return
	var level := int(_setup().wall.get("moat", 0))
	if level <= 0:
		return
	var top := y + size.y * 0.034
	var h := size.y * (0.016 + 0.0012 * level)
	draw_rect(Rect2(0, top - 1.5, size.x, h + 3.0), Color("#6b5434"))
	if WallText.moat_water(data, level):
		draw_rect(Rect2(0, top, size.x, h), WATER)
		for i in 10:
			var x := size.x * (i + 0.3) / 10.0
			draw_line(Vector2(x, top + h * 0.45), Vector2(x + size.x * 0.03, top + h * 0.45), Color(1, 1, 1, 0.35), 1.0, true)
	else:
		draw_rect(Rect2(0, top, size.x, h), Color("#8e7650"))
		var x := size.x * 0.01
		while x < size.x:
			draw_line(Vector2(x, top + h), Vector2(x + h * 0.4, top + h * 0.2), ROAD, 1.5, true)
			x += h * 0.9


## Our archers up on the walls: a block per squad's block, along the top.
func _draw_on_walls(squads: Array, color: Color, y: float) -> void:
	if squads.is_empty():
		return
	var count := 0
	for squad in squads:
		count += int(squad.blocks) + 1
	var step := minf(size.x * 0.035, size.x * 0.8 / float(maxi(count, 1)))
	var block := Vector2(step * 0.85, step * 0.55)
	var x := (size.x - count * step + step) / 2.0
	for squad in squads:
		for i in int(squad.blocks):
			var rect := Rect2(Vector2(x + i * step, y - size.y * 0.03 - block.y), block)
			draw_rect(rect, color if i < int(squad.alive) else Color(color, 0.2))
			draw_rect(rect, INK, false, 1.5)
			if i < int(squad.alive):
				draw_circle(rect.get_center(), rect.size.y * 0.22, INK)
		var name := tr("%s %d on the walls") % [BattleStory.plural(BattleStory.unit_name(data, squad.unit), int(squad.now)), int(squad.now)]
		_label(Vector2(x + (int(squad.blocks) - 1) * step / 2.0 + block.x / 2.0, y - size.y * 0.03 - block.y - 12.0), name, 14.0)
		x += (int(squad.blocks) + 1) * step


## The enemy's engines at the foot of the walls: ladders lean on them, siege
## towers stand against them, rams and catapults before them.
func _draw_engines(squads: Array, y: float) -> void:
	if squads.is_empty():
		return
	var all := 0
	for squad in squads:
		all += int(squad.start)
	var shown := mini(all, 14)
	var i := 0
	var foot := y + size.y * 0.075
	for squad in squads:
		var n := maxi(1, roundi(float(squad.start) / maxf(1.0, all) * shown))
		var alive := ceili(float(squad.now) / maxf(1.0, squad.start) * n)
		for k in n:
			var x := _engine_x(i, shown)
			_engine(String(squad.unit), Vector2(x, foot), k < alive, y)
			i += 1
		var label := tr("%s %d") % [BattleStory.plural(BattleStory.unit_name(data, squad.unit), int(squad.now)), int(squad.now)]
		_label(Vector2((_engine_x(i - n, shown) + _engine_x(i - 1, shown)) / 2.0, foot + size.y * 0.025), label, 14.0)


## Where the i-th of `shown` engines stands: in the field, clear of the
## wall's label on the left.
func _engine_x(i: int, shown: int) -> float:
	var x0 := _field.x + 0.26
	var x1 := _field.y - 0.06
	return size.x * (x0 + (x1 - x0) * (i + 0.5) / float(maxi(shown, 1)))


func _engine(unit: String, foot: Vector2, alive: bool, wall_y: float) -> void:
	var color := ENEMY if alive else Color(ENEMY, 0.2)
	var line := INK if alive else Color(INK, 0.3)
	var s := size.y * 0.03
	if BattleStory.escalade(data, unit) > 0.0:
		if BattleStory.escalade(data, unit) >= 20.0:
			# A siege tower against the walls.
			var rect := Rect2(foot.x - s * 0.6, wall_y - s * 0.5, s * 1.2, foot.y - wall_y + s * 0.5)
			draw_rect(rect, color)
			draw_rect(rect, line, false, 2.0)
			for f in 3:
				var fy := rect.position.y + rect.size.y * (f + 1) / 4.0
				draw_line(Vector2(rect.position.x, fy), Vector2(rect.end.x, fy), line, 1.0)
		else:
			# A ladder leaning on the walls.
			var top := Vector2(foot.x + s * 0.3, wall_y - s * 0.3)
			var off := Vector2(s * 0.3, 0)
			draw_line(foot - off, top - off, line, 2.0, true)
			draw_line(foot + off, top + off, line, 2.0, true)
			for r in 5:
				var p := foot.lerp(top, (r + 0.5) / 5.0)
				draw_line(p - off, p + off, line, 1.5)
	else:
		# A ram or catapult: a wheeled frame.
		var rect := Rect2(foot.x - s * 0.8, foot.y - s * 0.5, s * 1.6, s * 0.7)
		draw_rect(rect, color)
		draw_rect(rect, line, false, 2.0)
		draw_circle(rect.position + Vector2(s * 0.3, rect.size.y), s * 0.22, line)
		draw_circle(rect.end - Vector2(s * 0.3, 0), s * 0.22, line)


## Enemies up on the walls this round, come over by ladder and tower.
func _draw_climbers(y: float) -> void:
	var over := 0.0
	for entry in battle.get("rounds", []):
		if int(entry.round) == round:
			over = float(entry.get("over", 0.0))
	if over <= 0.0:
		return
	var n := clampi(roundi(over * 10.0), 1, 10)
	var s := size.y * 0.022
	for i in n:
		var x := size.x * (0.1 + 0.8 * (i + 0.5) / 10.0) + s
		var rect := Rect2(x, y - s * 0.6, s * 1.3, s)
		draw_rect(rect, ENEMY)
		draw_rect(rect, INK, false, 1.5)


## A broad river across the field between the lines, with the bridge the
## horde came over.
func _draw_river_across(y: float, rng: RandomNumberGenerator) -> void:
	var w := size.y * 0.05
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		var cy := y + size.y * 0.012 * sin(t * 7.0 + rng.randf())
		top.append(Vector2(size.x * t, cy - w / 2.0))
		bottom.append(Vector2(size.x * t, cy + w / 2.0))
	_river_band(top, bottom)
	var bridge := Rect2(size.x * 0.46, y - w * 0.75, size.x * 0.08, w * 1.5)
	draw_rect(bridge, Color("#a07a4c"))
	draw_rect(bridge, INK, false, 2.0)
	_label(Vector2(size.x * 0.5 + size.x * 0.12, y), tr("River"), 16.0)


## A broad river down one flank: the lines keep to the rest of the field.
func _draw_river_flank(rng: RandomNumberGenerator) -> void:
	var right := rng.randf() < 0.5
	var w := size.x * 0.07
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		var cx := (size.x * 0.93 if right else size.x * 0.07) + size.x * 0.012 * sin(t * 6.0 + rng.randf())
		left_edge.append(Vector2(cx - w / 2.0, size.y * t))
		right_edge.append(Vector2(cx + w / 2.0, size.y * t))
	_river_band(left_edge, right_edge)
	_field = Vector2(0.0, 0.86) if right else Vector2(0.14, 1.0)


## Water between two banks, with the banks' edges.
func _river_band(a: PackedVector2Array, b: PackedVector2Array) -> void:
	var poly := PackedVector2Array(a)
	var back := PackedVector2Array(b)
	back.reverse()
	poly.append_array(back)
	draw_colored_polygon(poly, WATER)
	draw_polyline(a, BANK, 3.0, true)
	draw_polyline(b, BANK, 3.0, true)
	for i in range(1, a.size() - 1, 3):
		var mid_point := a[i].lerp(b[i], 0.5)
		draw_line(mid_point - (b[i] - a[i]).orthogonal().normalized() * 6.0, mid_point + (b[i] - a[i]).orthogonal().normalized() * 6.0, Color(1, 1, 1, 0.3), 1.0, true)


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
	var text := (tr("Victory") if won else tr("Defeat"))
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


func _setup() -> Dictionary:
	return battle.get("setup", {}) if battle.get("setup") is Dictionary else {}


func _has_wall() -> bool:
	return _setup().has("wall")


## Whether the horde came over a river into the fight.
func _crossing() -> bool:
	return _setup().get("river", false)


## What is left of the walls after the round shown.
func _wall_left() -> int:
	var left := int(_setup().get("wall", {}).get("max", 0))
	for entry in battle.get("rounds", []):
		if int(entry.round) <= round and entry.has("wallLeft"):
			left = int(entry.wallLeft)
	return left


func _wall_standing() -> bool:
	return _has_wall() and _wall_left() > 0


## The round the walls fell in (the lines close from then on); 0 without
## walls, beyond the last round while they stand.
func _breach_round() -> int:
	if not _has_wall():
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
