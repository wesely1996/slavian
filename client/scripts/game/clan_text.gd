class_name ClanText
extends RefCounted
## Words for the clans (data/clans.json, server sim/clans.ts).


## Whether a unit or building def is open to a village with these bonuses:
## a clan's own one only to that clan.
static func allowed(def: Dictionary, bonuses: Dictionary) -> bool:
	var clan: Variant = def.get("clan")
	return clan == null or float(bonuses.get("clan.%s" % clan, 0)) > 0


## "Rod Volka (Wolf)".
static func title(data: Dictionary, clan: Variant) -> String:
	if clan == null or not data.clans.clans.has(clan):
		return UI.t("No clan")
	var def: Dictionary = data.clans.clans[clan]
	return UI.t("%s (%s)") % [UI.t(def.name), UI.t(def.animal)]


## The clan's own unit or building, by name.
static func unique_name(data: Dictionary, clan: String) -> String:
	var unique: Dictionary = data.clans.clans[clan].unique
	if unique.has("unit"):
		return UI.t("%s (unit)") % UI.t(data.units.units[unique.unit].name)
	return UI.t("%s (building)") % UI.t(data.buildings.buildings[unique.building].name)


## "Best at: … · Weakness: … · Own: …".
static func perks(data: Dictionary, clan: String) -> String:
	var def: Dictionary = data.clans.clans[clan]
	return UI.t("Best at: %s · Weakness: %s · Own: %s") % [UI.t(def.best), UI.t(def.weakness), unique_name(data, clan)]


## Whose historic arms the clan's emblem follows.
static func arms(data: Dictionary, clan: String) -> String:
	return UI.t(String(data.clans.clans[clan].get("arms", "")))


static func ids(data: Dictionary) -> Array:
	return data.clans.clans.keys()
