class_name BattleText
extends RefCounted
## Words for battles from the server (see server/src/sim/battle.ts).


static func total(units: Dictionary) -> int:
	var sum := 0
	for unit in units:
		sum += int(units[unit])
	return sum


## Total losses per side over all rounds so far.
static func losses(battle: Dictionary) -> Dictionary:
	var attacker := 0
	var defender := 0
	for round in battle.rounds:
		attacker += total(round.attackerLosses)
		defender += total(round.defenderLosses)
	return {"attacker": attacker, "defender": defender}


## "Defended Vesna's village: 8 of the horde fell, we lost 3."
static func outcome(battle: Dictionary, village_name: String) -> String:
	var lost := losses(battle)
	var tally := "%d of the horde fell, we lost %d" % [lost.attacker, lost.defender]
	match battle.status:
		"defended":
			return "Defended %s: %s." % [village_name, tally]
		"raided":
			if battle.has("q") and battle.get("villageId") == null:
				return "Our army fell back from %s: %s. The horde marched on." % [village_name, tally]
			return "%s was raided: %s. Taken: %s." % [village_name, tally, loot_text(battle.loot)]
	return "Battle at %s, round %d: %s." % [village_name, battle.round, tally]


## "Ambush, fort" — what the ground gave the holders: a river the horde
## had to cross counts too.
static func setup_text(battle: Dictionary) -> String:
	var setup: Dictionary = battle.get("setup", {}) if battle.get("setup") is Dictionary else {}
	var parts := PackedStringArray()
	for key in ["ambush", "choke", "fort", "river"]:
		if setup.get(key, false):
			parts.append({"ambush": "ambush", "choke": "choke point", "fort": "fort", "river": "river crossing"}[key])
	return ", ".join(parts).capitalize() if not parts.is_empty() else ""


static func loot_text(loot: Variant) -> String:
	if not loot is Dictionary:
		return "nothing"
	var parts := PackedStringArray()
	for kind in Ledger.KINDS:
		if int(loot.get(kind, 0)) > 0:
			parts.append("%s %d" % [kind.capitalize(), loot[kind]])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## "A horde burned Vesna's village's outpost at (3, -2) to ruins."
static func raid(raid: Dictionary, village_name: String) -> String:
	var after := int(raid.levelAfter)
	var result := "to ruins" if after <= 0 else "down to level %d" % after
	return "A horde burned the outpost of %s at (%d, %d) %s." % [village_name, int(raid.q), int(raid.r), result]
