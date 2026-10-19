class_name ScoutText
extends RefCounted
## Words for a scout report from the server (see server/src/sim/scouting.ts).


static func describe(report: Dictionary) -> String:
	if report.get("dispersed", false):
		return UI.t("The horde had already scattered.")
	if report.tier == "none":
		return UI.t("None of the %d scouts came back.") % report.sent
	var size: Dictionary = report.size
	var units: Array = report.units
	var head := UI.t("%s units") % _range(size)
	if report.get("stance") != null:
		head = UI.t("%s, %s stance") % [head, String(report.stance).replace("_", " ")]
	if report.tier == "rough" or units.is_empty() or units[0].min == null:
		return UI.t("%s, mostly %s") % [head, UI.t(units[0].name)] if not units.is_empty() else head
	var parts := PackedStringArray()
	for unit in units:
		parts.append(UI.t("%s %s") % [UI.t(unit.name), _range(unit)])
	return UI.t("%s: %s") % [head, ", ".join(parts)]


static func survivors(report: Dictionary) -> String:
	return UI.t("%d of %d scouts returned") % [report.survivors, report.sent]


static func _range(value: Dictionary) -> String:
	var low := int(value.min)
	var high := int(value.max)
	return str(low) if low == high else "%d–%d" % [low, high]
