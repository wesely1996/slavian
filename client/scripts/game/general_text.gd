class_name GeneralText
extends RefCounted
## Words for generals (server/src/sim/generals.ts): where one is, and what a
## Hero's Hall gives.


## How many generals a player may keep, by the levels of their Hero's Halls.
static func limit(data: Dictionary, hall_levels: Array) -> int:
	var g: Dictionary = data.heroes.generals
	var n := 0
	for level in hall_levels:
		if int(level) > 0:
			n += int(g.perHall) + floori(float(int(level) - 1) / int(g.hallLevelsPerGeneral))
	return n


## What the next general costs a player who keeps `owned` already.
static func recruit_cost(data: Dictionary, owned: int) -> Dictionary:
	var g: Dictionary = data.heroes.generals
	var cost := {}
	for kind in Ledger.KINDS:
		cost[kind] = roundi(float(g.cost[kind]) * pow(float(g.costGrowth), owned))
	return cost


## How much faster the hero heals in a village with a Hall of `level`, in %.
static func faster_healing(data: Dictionary, level: int) -> int:
	return roundi(minf(0.9, float(data.heroes.generals.hallRecoveryPerLevel) * level) * 100.0)


## A Hall's level, in a few words: how many generals it keeps and how fast
## the hero heals.
static func hall_gives(data: Dictionary, level: int) -> String:
	var keeps := limit(data, [level])
	return UI.tn("keeps %d general", "keeps %d generals", keeps) % keeps + " · " + UI.t("the hero heals %d%% faster") % faster_healing(data, level)


## "Radoslav (Lv 2) commands this garrison" and the like.
static func whereabouts(general: Dictionary, place: String, now: float) -> String:
	var until := TimeUtil.parse_iso(String(general.until)) - now if general.get("until") != null else 0.0
	match general.status:
		"recruiting":
			return UI.t("%s is on the way to %s · %s") % [general.name, place, TimeUtil.format_duration(until)]
		"traveling":
			return UI.t("%s is on the road to %s · %s") % [general.name, place, TimeUtil.format_duration(until)]
		"with_army":
			return UI.t("%s (Lv %d) leads an army in the field") % [general.name, int(general.level)]
	return UI.t("%s (Lv %d) stands in %s") % [general.name, int(general.level), place]


## "+2% attack, +2% defense" for the troops a general leads.
static func bonuses(general: Dictionary) -> String:
	return HeroText.effects(general.get("bonuses", {}))
