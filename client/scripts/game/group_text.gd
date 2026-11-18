class_name GroupText
extends RefCounted
## Words for the group's world settings: difficulty and quiet hours.

## Hereditary titles, easiest first (data/difficulty.json).
const DIFFICULTIES := ["baron", "viscount", "count", "marquess", "duke"]
const DIFFICULTY_LABELS := ["Baron", "Viscount", "Count", "Marquess", "Duke"]  # tr
## Quiet windows the host can pick from, in local hours: [start, end].
const QUIET_CHOICES := [[22, 6], [23, 7], [0, 8]]


static func hhmm(minutes: int) -> String:
	return "%02d:%02d" % [int(minutes / 60) % 24, minutes % 60]


static func offset_text(offset_minutes: int) -> String:
	var sign := "+" if offset_minutes >= 0 else "−"
	var m := absi(offset_minutes)
	return "UTC%s%02d:%02d" % [sign, int(m / 60), m % 60]


## "Hordes hold off 22:00–06:00 (UTC+02:00)" or "No quiet hours".
static func quiet(window: Variant) -> String:
	if not window is Dictionary:
		return UI.t("No quiet hours: hordes may arrive any time")
	return UI.t("Hordes hold off %s–%s (%s)") % [hhmm(int(window.start)), hhmm(int(window.end)), offset_text(int(window.utcOffsetMinutes))]


static func difficulty(data: Dictionary, id: String) -> String:
	return data.get("difficulty", {}).get("presets", {}).get(id, {}).get("name", id.capitalize())


## What every title means, easiest first, for the difficulty's info button:
## its line from the data, then the numbers behind it.
static func difficulty_info(data: Dictionary) -> String:
	var presets: Dictionary = data.get("difficulty", {}).get("presets", {})
	var parts := PackedStringArray([UI.t("The difficulty is a title: the higher it is, the harder the run. Easiest first:")])
	for id in DIFFICULTIES:
		var p: Dictionary = presets.get(id, {})
		if p.is_empty():
			continue
		var grace := int(p.graceWaves)
		var lines := PackedStringArray()
		lines.append(UI.t("Hordes ×%s their usual size, between ×%s and ×%s; they grow with your group's villages and armies at ×%s the pace.") % [_x(p.waveScale), _x(p.floor), _x(p.maxFactor), _x(p.powerWeight)])
		lines.append(UI.t("Camps ×%s.") % _x(p.campRate))
		lines.append(UI.t("Grace: %d hordes only plunder before any may burn a village.") % grace if grace > 0 else UI.t("Even the first horde may burn a village."))
		parts.append("%s: %s %s" % [UI.t(String(p.name)), UI.t(String(p.get("description", ""))), " ".join(lines)])
	return "\n\n".join(parts)


static func _x(value: Variant) -> String:
	return String.num(float(value), 2)
