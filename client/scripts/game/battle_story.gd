class_name BattleStory
extends RefCounted
## A battle round by round, for the battle screen: what each side had after
## any round, its squads as map blocks, and what happened, in words. The
## enemy is always the attacker (a horde, or a camp's or site's guardians);
## our side, garrison and armies, the defender (server/src/sim/battle.ts).

## Front to back: the order squads are drawn in, from the line of battle.
const FAMILY_ROWS := ["infantry", "cavalry", "archers", "scout"]
## At most this many blocks for a side's biggest squad.
const MAX_BLOCKS := 8


## Each side's units after `round` rounds (0: as the battle began). Armies
## join the defenders in their round; harassers ride off after it.
static func units_at(battle: Dictionary, round: int) -> Dictionary:
	var attacker := _copy(battle.get("attackerInitial", {}))
	var defender := _copy(battle.get("defenderInitial", {}))
	for entry in battle.get("rounds", []):
		if int(entry.round) > round:
			break
		var joined: Array = entry.get("joined", [])
		for army in joined:
			_add(defender, army.units)
		_subtract(attacker, entry.attackerLosses)
		_subtract(defender, entry.defenderLosses)
		for army in joined:
			if army.orders == "harass":
				_subtract(defender, army.units)
	return {"attacker": attacker, "defender": defender}


## How many men one block stands for, so the side's biggest squad (at the
## start) fits in MAX_BLOCKS.
static func per_block(units: Dictionary) -> int:
	var most := 0
	for unit in units:
		most = maxi(most, int(units[unit]))
	return maxi(1, ceili(most / float(MAX_BLOCKS)))


## A side's squads: one per unit type, in rows by family (front first):
## [{unit, family, start, now, blocks, alive}], `blocks` drawn in all and
## `alive` of them still standing.
static func squads(data: Dictionary, start: Dictionary, now: Dictionary) -> Array:
	var per := per_block(start)
	var out := []
	for unit in start:
		var count := int(start[unit])
		if count <= 0:
			continue
		var left := int(now.get(unit, 0))
		out.append({
			"unit": unit,
			"family": unit_family(data, unit),
			"start": count,
			"now": left,
			"blocks": ceili(count / float(per)),
			"alive": ceili(left / float(per)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := FAMILY_ROWS.find(a.family)
		var rb := FAMILY_ROWS.find(b.family)
		return ra < rb if ra != rb else int(a.start) > int(b.start))
	return out


## A unit's name, ours or any front's.
static func unit_name(data: Dictionary, unit: String) -> String:
	var def := _unit_def(data, unit)
	return String(def.get("name", unit.replace("_", " ").capitalize()))


static func unit_family(data: Dictionary, unit: String) -> String:
	return String(_unit_def(data, unit).get("family", "infantry"))


## "32 Grey Wolves and 12 Leshy's Thralls" (counts above zero, biggest first).
static func units_text(data: Dictionary, units: Dictionary) -> String:
	var keys := units.keys().filter(func(u: String) -> bool: return int(units[u]) > 0)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(units[a]) > int(units[b]))
	var parts := PackedStringArray()
	for unit in keys:
		parts.append("%d %s" % [int(units[unit]), plural(unit_name(data, unit), int(units[unit]))])
	if parts.is_empty():
		return "no one"
	if parts.size() == 1:
		return parts[0]
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]


static func plural(name: String, count: int) -> String:
	if count == 1:
		return name
	if name.ends_with("man"):
		return name.trim_suffix("man") + "men"
	if name.ends_with("f"):
		return name.trim_suffix("f") + "ves"
	if name.ends_with("s") or name.ends_with("x"):
		return name + "es"
	return name + "s"


## What the battle looked like before the first blow. `ctx` names things:
## {enemy: "The Northern horde", place: "Vesna's village", helpers: Callable}.
static func opening(data: Dictionary, battle: Dictionary, ctx: Dictionary) -> String:
	var stance := String(battle.get("attackerStance", "balanced")).replace("_", " ")
	var text := "%s came on, %s, with %s. %s held with %s." % [
		_sentence(ctx.get("enemy", "the horde")), stance, units_text(data, battle.get("attackerInitial", {})),
		_sentence(ctx.get("place", "the village")), units_text(data, battle.get("defenderInitial", {}))]
	var ground := BattleText.setup_text(battle)
	if ground != "":
		text += " The ground favoured us: %s." % ground.to_lower()
	return text


## Round `round` (from 1) in a few sentences.
static func narrate(data: Dictionary, battle: Dictionary, round: int, ctx: Dictionary) -> String:
	var rounds: Array = battle.get("rounds", [])
	if round < 1 or round > rounds.size():
		return ""
	var entry: Dictionary = rounds[round - 1]
	var lines := PackedStringArray()
	var village_name: Callable = ctx.get("village_name", func(_id: Variant) -> String: return "a neighbour")
	for army in entry.get("joined", []):
		var how: String = {"harass": "harried the flank", "pincer": "struck from behind", "support": "joined the line"}.get(String(army.orders), "joined the fight")
		lines.append("Help from %s %s with %s%s." % [village_name.call(army.villageId), how, units_text(data, army.units), (" (+%d%%)" % roundi(float(army.bonus) * 100.0)) if float(army.bonus) > 0.0 else ""])
	var theirs := BattleText.total(entry.attackerLosses)
	var ours := BattleText.total(entry.defenderLosses)
	lines.append("%s fell on their side." % _sentence(units_text(data, entry.attackerLosses)) if theirs > 0 else "None of them fell.")
	lines.append("We lost %s." % units_text(data, entry.defenderLosses) if ours > 0 else "We lost no one.")
	var before := units_at(battle, round - 1)
	var share_theirs := theirs / maxf(1.0, BattleText.total(before.attacker))
	var share_ours := ours / maxf(1.0, BattleText.total(before.defender))
	lines.append(_mood(share_theirs, share_ours))
	if round == rounds.size() and battle.get("status", "ongoing") != "ongoing":
		lines.append(ending(battle, ctx))
	return " ".join(lines)


## The last word: who held the field.
static func ending(battle: Dictionary, ctx: Dictionary) -> String:
	var assault := battle.get("campId") != null or battle.get("siteId") != null
	match String(battle.get("status", "")):
		"defended":
			return "The enemy broke and fled. The field is ours." if not assault else "We fell back; they still hold their ground."
		"cleared":
			return "The last of them fell. The camp is ours to burn."
		"raided":
			if battle.get("villageId") == null and not assault:
				return "Our line broke and fell back; the horde marched on."
			var decision: Variant = battle.get("decision")
			if decision is Dictionary and decision.get("choice") == "raze":
				return "Our line broke. The horde stayed to burn %s." % ctx.get("place", "the village")
			return "Our line broke. The horde carried off %s." % BattleText.loot_text(battle.get("loot"))
	return "The fight goes on."


static func _mood(theirs: float, ours: float) -> String:
	if theirs <= 0.0 and ours <= 0.0:
		return "Both lines stood and glared."
	if theirs > ours * 2.0:
		return "Their ranks are thinning fast."
	if ours > theirs * 2.0:
		return "Our line bends under the weight."
	return "Neither side gives ground."


## "vesna's village" → "Vesna's village": only the first letter.
static func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func _unit_def(data: Dictionary, unit: String) -> Dictionary:
	var ours: Dictionary = data.get("units", {}).get("units", {})
	if ours.has(unit):
		return ours[unit]
	for front in data.get("enemies", {}).get("fronts", {}).values():
		if front.get("units", {}).has(unit):
			return front.units[unit]
	return {}


static func _copy(units: Variant) -> Dictionary:
	var out := {}
	if units is Dictionary:
		for unit in units:
			out[unit] = int(units[unit])
	return out


static func _add(into: Dictionary, units: Dictionary) -> void:
	for unit in units:
		into[unit] = int(into.get(unit, 0)) + int(units[unit])


static func _subtract(from: Dictionary, units: Dictionary) -> void:
	for unit in units:
		from[unit] = maxi(0, int(from.get(unit, 0)) - int(units[unit]))
