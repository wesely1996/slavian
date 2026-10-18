class_name ScoutText
extends RefCounted
## Words for a scout report from the server (see server/src/sim/scouting.ts).


static func describe(report: Dictionary) -> String:
	if report.get("dispersed", false):
		return "The horde had already scattered."
	if report.tier == "none":
		return "None of the %d scouts came back." % report.sent
	var size: Dictionary = report.size
	var units: Array = report.units
	var head := "%s units" % _range(size)
	if report.get("stance") != null:
		head = "%s, %s stance" % [head, String(report.stance).replace("_", " ")]
	if report.tier == "rough" or units.is_empty() or units[0].min == null:
		return "%s, mostly %s" % [head, units[0].name] if not units.is_empty() else head
	var parts := PackedStringArray()
	for unit in units:
		parts.append("%s %s" % [unit.name, _range(unit)])
	return "%s: %s" % [head, ", ".join(parts)]


static func survivors(report: Dictionary) -> String:
	return "%d of %d scouts returned" % [report.survivors, report.sent]


static func _range(value: Dictionary) -> String:
	var low := int(value.min)
	var high := int(value.max)
	return str(low) if low == high else "%d–%d" % [low, high]
