class_name CaravanText
extends RefCounted
## Words for caravan trips, seen from one village.


static func describe(caravan: Dictionary, village_id: int, now: float) -> String:
	var outgoing := int(caravan.villageId) == village_id
	var where := "the Holy City vault" if caravan.destinationVillageId == null else Game.village_name(caravan.destinationVillageId)
	var cargo := _load_text(caravan.cargo)
	if not outgoing:
		var from := Game.village_name(caravan.villageId)
		if caravan.status == "outbound":
			return "From %s: %s · arrives in %s" % [from, cargo, TimeUtil.format_duration(TimeUtil.parse_iso(caravan.arrivesAt) - now)]
		return "From %s: delivered %s" % [from, cargo]
	match caravan.status:
		"outbound":
			var verb := "Fetching" if caravan.kind == "fetch" else "To %s:" % where
			if caravan.kind == "fetch":
				return "%s %s from the vault · there in %s" % [verb, cargo, TimeUtil.format_duration(TimeUtil.parse_iso(caravan.arrivesAt) - now)]
			return "%s %s · arrives in %s" % [verb, cargo, TimeUtil.format_duration(TimeUtil.parse_iso(caravan.arrivesAt) - now)]
		"returning":
			var back := _load_text(caravan.carriedBack) if caravan.carriedBack != null else "nothing"
			return "Heading home with %s · back in %s" % [back, TimeUtil.format_duration(TimeUtil.parse_iso(caravan.returnsAt) - now)]
	var brought := _load_text(caravan.carriedBack) if caravan.carriedBack != null else "nothing"
	if caravan.kind == "fetch":
		return "Fetched %s from the vault" % brought
	return "Delivered to %s%s" % [where, "" if brought == "nothing" else "; %s did not fit and came back" % brought]


static func _load_text(amounts: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		if int(amounts.get(kind, 0)) > 0:
			parts.append("%s %d" % [kind.capitalize(), int(amounts[kind])])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
