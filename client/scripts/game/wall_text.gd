class_name WallText
extends RefCounted
## Words for walls, their towers and sieges (server/src/sim/walls.ts,
## data/walls.json).


## The tier walls at `level` are built to: {minLevel, name, material,
## toughness}; {} with no walls.
static func tier_def(data: Dictionary, level: int) -> Dictionary:
	if level <= 0:
		return {}
	var found := {}
	for t in data.get("walls", {}).get("tiers", []):
		if level >= int(t.minLevel) or found.is_empty():
			found = t
	return found


## "Palisade", "Timber Rampart", "Stone Wall", "Fortress Walls"; "" with no
## walls.
static func tier(data: Dictionary, level: int) -> String:
	return String(tier_def(data, level).get("name", ""))


## "wood", "timber", "stone", "fortress"; "" with no walls.
static func material(data: Dictionary, level: int) -> String:
	return String(tier_def(data, level).get("material", ""))


static func integrity(data: Dictionary, wall_level: int, gate_level := 0) -> int:
	var w: Dictionary = data.get("walls", {})
	if w.is_empty():
		return 0
	var toughness := float(tier_def(data, wall_level).get("toughness", 1.0))
	return roundi(float(w.integrityPerLevel) * wall_level * toughness * (1.0 + gate_level * float(w.towers.gate_tower.integrityPerLevel)))


## How many men the walls hold at `level`.
static func capacity(data: Dictionary, level: int) -> int:
	return roundi(level * float(data.get("walls", {}).get("manning", {}).get("menPerLevel", 0)))


## Whether the moat at `level` (the ditch tower) holds water.
static func moat_water(data: Dictionary, level: int) -> bool:
	return level >= int(data.get("walls", {}).get("towers", {}).get("ditch", {}).get("waterAt", 4))


## What the walls do at `level`, and what the next level adds.
static func wall_effect(data: Dictionary, level: int) -> String:
	var w: Dictionary = data.get("walls", {})
	if w.is_empty():
		return ""
	var text := ""
	if level > 0:
		text = "%s: %d to batter down; the garrison defends %d%% better while it stands, and %d archers shoot from it %d%% harder. Until it falls, the horde strikes at %d%% but where ladders and siege towers carry it over. %d wall slot%s open." % [
			tier(data, level), integrity(data, level), roundi(level * float(w.defensePerLevel) * 100.0),
			capacity(data, level), roundi(level * float(w.manning.archerAttackPerLevel) * 100.0),
			roundi(float(w.escalade.meleeHeld) * 100.0),
			Rules.open_tower_slots(data, level), "" if Rules.open_tower_slots(data, level) == 1 else "s"]
	else:
		text = "No walls yet: a horde walks straight in."
	if level < 10:
		var next := level + 1
		text += " Level %d: %s, %d to batter down%s." % [next, tier(data, next), integrity(data, next),
			", opens a wall slot" if Rules.open_tower_slots(data, next) > Rules.open_tower_slots(data, level) else ""]
	return text


## What a tower does at `level` and at the next.
static func tower_effect(data: Dictionary, tower: String, level: int) -> String:
	var t: Dictionary = data.get("walls", {}).get("towers", {}).get(tower, {})
	if t.is_empty():
		return ""
	var at := func(l: int) -> String:
		match tower:
			"archer_tower":
				return "+%d%% attack for the garrison while the walls stand" % roundi(l * float(t.attackPerLevel) * 100.0)
			"gate_tower":
				return "+%d%% to the walls' strength" % roundi(l * float(t.integrityPerLevel) * 100.0)
			"ballista":
				return "smashes %.1f siege engines a round" % (l * float(t.enginesPerLevel))
			"murder_holes":
				return "+%d%% defense while the walls stand" % roundi(l * float(t.defensePerLevel) * 100.0)
			"ditch":
				return "%s keeps off %d%% of the battering and %d%% of the climbers; engines take %d%% longer to build" % [
					"a water-filled moat" if moat_water(data, l) else "a dry moat with stakes",
					roundi(minf(0.9, l * float(t.siegeCutPerLevel)) * 100.0), roundi(minf(0.9, l * float(t.get("escaladeCutPerLevel", 0.0))) * 100.0),
					roundi(l * float(t.setupPerLevel) * 100.0)]
			"watchtower":
				return "warns of a horde %d hour%s earlier" % [roundi(l * float(t.warningHoursPerLevel)), "" if roundi(l * float(t.warningHoursPerLevel)) == 1 else "s"]
		return ""
	var now: String = at.call(level) if level > 0 else "Not built yet"
	return "%s. Level %d: %s." % [now.left(1).to_upper() + now.substr(1), level + 1, at.call(level + 1)]


## "The walls hold: 540 of 720 left." / "The walls are breached!" for a
## round's log, with how many came over them; "" when no walls stood.
static func round_text(battle: Dictionary, entry: Dictionary) -> String:
	if not entry.has("wallLeft"):
		return ""
	var over := float(entry.get("over", 0.0))
	var climbing := ""
	if over >= 1.0:
		climbing = " Their ladders and towers put every man of them on the walls."
	elif over > 0.0:
		climbing = " Their ladders and towers carried %d%% of them onto the walls." % roundi(over * 100.0)
	if entry.get("breach", false):
		return "The walls are breached!" + climbing
	var wall: Dictionary = battle.get("setup", {}).get("wall", {})
	return "The walls hold: %d of %d left." % [int(entry.wallLeft), int(wall.get("max", entry.wallLeft))] + climbing
