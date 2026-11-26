class_name RaidText
extends RefCounted
## Words and sums for raids beyond the map's edge (data/raids.json,
## server/src/sim/raids.ts).


## "the North", "the East", …
static func front_name(front: String) -> String:
	return {"north": UI.t("the North"), "east": UI.t("the East"), "south": UI.t("the South"), "west": UI.t("the West")}.get(front, front)


## "2 fields, then the Monster Lair"
static func plan(data: Dictionary, front: String, depth: int) -> String:
	var stronghold := UI.t(String(data.raids.fronts.get(front, {}).get("stronghold", "")))
	return UI.tn("%d field, then the %s", "%d fields, then the %s", depth) % [depth, stronghold]


## What the raid of `front` is after.
static func prize(front: String) -> String:
	if front == "north":
		return UI.t("Little to carry off, but each battle won may bring hero gear, a lore scroll (rare research) or a Svarog's Ember.")
	return UI.t("Resources for every enemy killed, and the stronghold's stores if it falls, as much as the troops and wagons can carry.")


## The share of a horde gathered at its encampment `hours_early` game hours
## before it sets out (sim/raids.ts strikeShare).
static func strike_share(data: Dictionary, hours_early: float) -> float:
	return LocalRaids.strike_share(data, hours_early)


## What a raid of `units` can carry home (sim/raids.ts raidCapacity).
static func capacity(data: Dictionary, units: Dictionary) -> int:
	return int(LocalRaids.capacity(data, units))


## Game hours a raid of `depth` spends beyond the edge (the stages).
static func stage_hours(data: Dictionary, depth: int) -> float:
	return float(data.raids.stageHours) * (depth + 1)


## Grain `units` eat in a game hour.
static func upkeep(data: Dictionary, units: Dictionary) -> float:
	var per_hour := 0.0
	for unit in units:
		per_hour += float(data.units.units.get(unit, {}).get("upkeepPerHour", 0)) * int(units[unit])
	return per_hour


## Where a raid stands now: "Marching to the edge", "Beyond the edge: 1 of
## 3 battles fought", "Coming home".
static func progress(army: Dictionary) -> String:
	var raid: Dictionary = army.get("raid", {}) if army.get("raid") is Dictionary else {}
	if raid.is_empty():
		return ""
	var stages := int(raid.depth) + 1
	match String(army.status):
		"marching":
			return UI.t("On the way to the edge of the map")
		"stationed":
			return UI.t("Beyond the edge: %d of %d battles fought") % [int(raid.stage), stages]
		"returning":
			return UI.t("Coming home")
	return UI.t("Back home")


## One line per battle fought: "Won at the Open Steppe: 24 against 31 ·
## 4 rounds · 14 killed, 2 lost · +520 loot" (the base stats where the raid
## recorded them).
static func battles(raid: Dictionary) -> Array:
	var out: Array = []
	for b in raid.get("battles", []):
		var name := UI.t(String(b.name))
		var line := (UI.t("Won at the %s") if b.won else UI.t("Beaten at the %s")) % name
		if b.stronghold and b.won:
			line = UI.t("Sacked the %s") % name
		var parts := PackedStringArray()
		if b.get("army") != null:
			parts.append(UI.t("%d against %d") % [int(b.army), int(b.enemy)])
			parts.append(UI.tn("%d round", "%d rounds", int(b.rounds)) % int(b.rounds))
		parts.append(UI.t("%d killed, %d lost") % [int(b.kills), int(b.lost)])
		if b.get("loot") is Dictionary and LocalLogistics.total(b.loot) > 0:
			parts.append(UI.t("+%d loot") % int(LocalLogistics.total(b.loot)))
		out.append(line + ": " + " · ".join(parts))
	return out


## Loot a campaign won, by resource (the battles' own, where recorded).
static func campaign_loot(raid: Dictionary) -> Dictionary:
	var sum := {"wood": 0, "stone": 0, "grain": 0, "iron": 0}
	for b in raid.get("battles", []):
		if b.get("loot") is Dictionary:
			for kind in sum:
				sum[kind] = int(sum[kind]) + int(b.loot.get(kind, 0))
	return sum


## Loot a raid of `front` to `depth` would win if every battle is won: each
## enemy force (sim/raids.ts raidStage's size, `waves` hordes so far) beaten
## when it breaks (its stance's retreat share times its front's nerve), the
## stronghold's stores besides, richer the deeper and the more the front
## hates (`hatred`). An estimate: before what the troops can carry.
static func loot_estimate(data: Dictionary, front: String, depth: int, waves: int, hatred := 0.0) -> Dictionary:
	var rules: Dictionary = data.raids
	var nerve := float(data.enemies.fronts.get(front, {}).get("personality", {}).get("nerve", 1.0))
	var sum := {"wood": 0.0, "stone": 0.0, "grain": 0.0, "iron": 0.0}
	for stage in range(1, depth + 2):
		var stronghold := stage > depth
		var size := float(rules.enemy.baseUnits) * pow(float(rules.enemy.growthPerStage), stage - 1) * pow(float(rules.enemy.growthPerWave), waves) \
			* (float(rules.stronghold.sizeFactor) if stronghold else 1.0)
		var stance := String(rules.stronghold.stance) if stronghold else String(rules.fieldStance)
		var retreat: Variant = data.battle.stances[stance].retreatAt
		var share := 1.0 if retreat == null else minf(0.95, float(retreat) * nerve)
		var gain := LocalRaids.loot(data, front, roundi(maxf(1.0, roundf(size)) * share), stronghold, stage, hatred)
		for kind in sum:
			sum[kind] = float(sum[kind]) + float(gain[kind])
	return sum


## A raid battle's report line (battle.setup.raid): "" for other battles.
static func report(battle: Dictionary, lost: Dictionary) -> String:
	var raid: Variant = battle.get("setup", {}).get("raid") if battle.get("setup") is Dictionary else null
	if not raid is Dictionary:
		return ""
	var name := UI.t(String(raid.name))
	var won: bool = battle.status == "cleared"
	if raid.get("strike", false):
		return (UI.t("Strike on the horde of %s: broke it in its encampment; %d fell, we lost %d.") if won else UI.t("Strike on the horde of %s: thrown back from its encampment; %d of them fell, we lost %d.")) % [front_name(String(raid.front)), int(lost.attacker), int(lost.defender)]
	if raid.get("stronghold", false):
		return (UI.t("Raid on %s: sacked the %s; %d fell, we lost %d.") if won else UI.t("Raid on %s: thrown back from the %s; %d of them fell, we lost %d.")) % [front_name(String(raid.front)), name, int(lost.attacker), int(lost.defender)]
	return (UI.t("Raid on %s: won at the %s; %d fell, we lost %d.") if won else UI.t("Raid on %s: beaten at the %s; %d of them fell, we lost %d.")) % [front_name(String(raid.front)), name, int(lost.attacker), int(lost.defender)]
