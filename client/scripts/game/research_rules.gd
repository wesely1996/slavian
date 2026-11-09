class_name ResearchRules
extends RefCounted
## Display-side copy of server/src/sim/research.ts.


## Techs the group knows, and the one it is gathering for or researching
## ({} if none): research is shared.
static func group(research: Array) -> Dictionary:
	var done := {}
	var current := {}
	for entry in research:
		if entry.status == "done":
			done[entry.tech] = true
		elif current.is_empty() or entry.status == "funding":
			current = entry
	return {"done": done, "current": current}


## How much of a tech's cost the members have sent (0..1; 1 for research
## from before it was shared).
static func paid_share(entry: Dictionary) -> float:
	if not entry.get("cost") is Dictionary or not entry.get("paid") is Dictionary:
		return 1.0
	var cost := 0.0
	var paid := 0.0
	for kind in entry.cost:
		cost += float(entry.cost[kind])
		paid += minf(float(entry.paid.get(kind, 0)), float(entry.cost[kind]))
	return 1.0 if cost <= 0.0 else paid / cost


## What a tech being gathered for still needs.
static func still_needed(entry: Dictionary) -> Dictionary:
	var out := {}
	if not entry.get("cost") is Dictionary or not entry.get("paid") is Dictionary:
		return out
	for kind in entry.cost:
		var left := int(entry.cost[kind]) - int(entry.paid.get(kind, 0))
		if left > 0:
			out[kind] = left
	return out


## Techs `account_id` knows, and the one they are researching ({} if none).
static func progress(research: Array, account_id: int) -> Dictionary:
	var done := {}
	var current := {}
	for entry in research:
		if int(entry.accountId) != account_id:
			continue
		if entry.status == "done":
			done[entry.tech] = true
		else:
			current = entry
	return {"done": done, "current": current}


## Why the tech can't be started ("" when it can).
static func problem(data: Dictionary, tech: String, academy_level: int, done: Dictionary, researching: bool, scrolls: Dictionary = {}) -> String:
	var def: Dictionary = data.research.techs.get(tech, {})
	if def.is_empty():
		return UI.t("Unknown tech.")
	if done.has(tech):
		return UI.t("Known.")
	if researching:
		return UI.t("One tech at a time.")
	var scroll: Variant = def.get("requiresScroll")
	if scroll != null and not scrolls.has(scroll):
		return UI.t("Needs the %s scroll.") % UI.t(data.lore.scrolls.get(scroll, {}).get("name", scroll))
	if academy_level < int(def.academyLevel):
		return UI.t("Needs an Academy of level %d.") % int(def.academyLevel)
	var missing := PackedStringArray()
	for required in def.requires:
		if not done.has(required):
			missing.append(UI.t(data.research.techs[required].name))
	if not missing.is_empty():
		return UI.t("Needs %s first.") % " and ".join(missing)
	return ""


static func bonus(bonuses: Dictionary, key: String) -> float:
	return float(bonuses.get(key, 0.0))


## Multiplier for a duration ("buildTime" or "trainTime"), never below 0.1.
static func time_factor(bonuses: Dictionary, key: String) -> float:
	return maxf(0.1, 1.0 + bonus(bonuses, key))


static func production_factor(bonuses: Dictionary, kind: String) -> float:
	return 1.0 + bonus(bonuses, "production." + kind) + bonus(bonuses, "production.all")


## Research `tech` takes, besides its resources (sim/research.ts researchCost).
static func research_cost(data: Dictionary, tech: String) -> int:
	return roundi(float(data.research.techs[tech].seconds) * float(data.research.get("researchPerSecond", 0)))


## The research a member's Academies have brought in by `now` (seconds),
## credited a minute's worth at every whole minute, as the server does.
static func points(member: Dictionary, now: float) -> float:
	var research: Dictionary = member.get("research", {})
	var amount := float(research.get("points", 0))
	if research.get("settledAt") == null:
		return amount
	var minutes := floori(now / 60.0) - floori(TimeUtil.parse_iso(research.settledAt) / 60.0)
	return amount + float(research.get("perHour", 0)) * maxi(0, minutes) / 60.0
