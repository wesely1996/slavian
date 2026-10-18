class_name ResearchRules
extends RefCounted
## Display-side copy of server/src/sim/research.ts.


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
static func problem(data: Dictionary, tech: String, academy_level: int, done: Dictionary, researching: bool) -> String:
	var def: Dictionary = data.research.techs.get(tech, {})
	if def.is_empty():
		return "Unknown tech."
	if done.has(tech):
		return "Known."
	if researching:
		return "One tech at a time."
	if academy_level < int(def.academyLevel):
		return "Needs an Academy of level %d." % int(def.academyLevel)
	var missing := PackedStringArray()
	for required in def.requires:
		if not done.has(required):
			missing.append(data.research.techs[required].name)
	if not missing.is_empty():
		return "Needs %s first." % " and ".join(missing)
	return ""


static func bonus(bonuses: Dictionary, key: String) -> float:
	return float(bonuses.get(key, 0.0))


## Multiplier for a duration ("buildTime" or "trainTime"), never below 0.1.
static func time_factor(bonuses: Dictionary, key: String) -> float:
	return maxf(0.1, 1.0 + bonus(bonuses, key))


static func production_factor(bonuses: Dictionary, kind: String) -> float:
	return 1.0 + bonus(bonuses, "production." + kind) + bonus(bonuses, "production.all")
