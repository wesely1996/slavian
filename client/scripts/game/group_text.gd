class_name GroupText
extends RefCounted
## Words for the group's world settings: difficulty and quiet hours.

const DIFFICULTIES := ["story", "normal", "hard", "nightmare"]
const DIFFICULTY_LABELS := ["Story difficulty", "Normal difficulty", "Hard difficulty", "Nightmare difficulty"]
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
		return "No quiet hours: hordes may arrive any time"
	return "Hordes hold off %s–%s (%s)" % [hhmm(int(window.start)), hhmm(int(window.end)), offset_text(int(window.utcOffsetMinutes))]


static func difficulty(data: Dictionary, id: String) -> String:
	return data.get("difficulty", {}).get("presets", {}).get(id, {}).get("name", id.capitalize())
