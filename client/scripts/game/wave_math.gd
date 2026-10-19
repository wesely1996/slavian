class_name WaveMath
extends RefCounted
## Where a marching horde is, from the path the server sent: each step is
## [q, r, ms after spawnAt when the horde enters that hex].

## Each front's horde colour on the map: monsters red, nomads ochre, the
## Order violet.
const FRONT_COLORS := {
	"north": Color("#c8372d"),
	"east": Color("#d0862c"),
	"south": Color("#7b5aa6"),
	"west": Color("#7b5aa6"),
}

## Threat levels, a colour-blind-safe ramp (calm → grave), each with an icon
## so the level never rests on colour alone (M5 accessibility).
const THREAT_COLORS := {
	"Low": Color("#2f6e55"),
	"Moderate": Color("#c9a227"),
	"High": Color("#d0862c"),
	"Severe": Color("#a8322b"),
}
## Each threat level's skull: a plain skull for common threats, a horned
## (devil) skull for elite ones and a spiked (demon) skull for the worst.
const THREAT_ICONS := {
	"Low": "icon/threat_normal",
	"Moderate": "icon/threat_normal",
	"High": "icon/threat_elite",
	"Severe": "icon/threat_boss",
}
## Each front's faction emblem, so fronts are told apart by shape too.
const FRONT_ICONS := {
	"north": "faction/north",
	"east": "faction/east",
	"south": "faction/order",
	"west": "faction/order",
}


## {"from": Vector2i, "to": Vector2i, "t": 0..1} for the leg the horde is on,
## or {} when the wave has no path yet.
static func progress(wave: Dictionary, at_unix: float) -> Dictionary:
	var path: Variant = wave.get("path")
	if not path is Array or path.is_empty():
		return {}
	var elapsed_ms := (at_unix - TimeUtil.parse_iso(wave.spawnAt)) * 1000.0
	var last: Array = path[path.size() - 1]
	if wave.status != "marching" or elapsed_ms >= float(last[2]):
		var end := Vector2i(int(last[0]), int(last[1]))
		return {"from": end, "to": end, "t": 1.0}
	for i in range(1, path.size()):
		var step: Array = path[i]
		if elapsed_ms < float(step[2]):
			var prev: Array = path[i - 1]
			var span := float(step[2]) - float(prev[2])
			return {
				"from": Vector2i(int(prev[0]), int(prev[1])),
				"to": Vector2i(int(step[0]), int(step[1])),
				"t": clampf((elapsed_ms - float(prev[2])) / span, 0.0, 1.0) if span > 0.0 else 1.0,
			}
	var first: Array = path[0]
	var start := Vector2i(int(first[0]), int(first[1]))
	return {"from": start, "to": start, "t": 0.0}


## The hex the horde currently stands on (or is about to leave).
static func current_hex(wave: Dictionary, at_unix: float) -> Vector2i:
	var p := progress(wave, at_unix)
	if p.is_empty():
		return Vector2i.MAX
	return p.to if p.t >= 0.5 else p.from


## Hordes on the map: marching, or at their target (camped or fighting).
static func visible_waves(waves: Array) -> Array:
	return waves.filter(func(w: Dictionary) -> bool: return w.status in ["marching", "arrived", "battling"])


static func front_color(front: String) -> Color:
	return FRONT_COLORS.get(front, Color("#c8372d"))


static func front_icon(front: String) -> String:
	return FRONT_ICONS.get(front, "faction/north")


static func threat_color(level: String) -> Color:
	return THREAT_COLORS.get(level, UiTheme.MUTED)


static func threat_icon(level: String) -> String:
	return THREAT_ICONS.get(level, "icon/threat")


## "Monsters of the North (North): Beasts and creatures…" for one front,
## from data/enemies.json.
static func front_line(data: Dictionary, front: String) -> String:
	var def: Dictionary = data.get("enemies", {}).get("fronts", {}).get(front, {})
	if def.is_empty():
		return ""
	return UI.t("%s (%s): %s") % [UI.t(def.faction), String(front).capitalize(), UI.t(def.get("signature", ""))]


## One line per active front, from data/enemies.json.
static func front_lines(data: Dictionary, active_fronts: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for front in active_fronts:
		var line := front_line(data, String(front))
		if line != "":
			lines.append(line)
	return lines
