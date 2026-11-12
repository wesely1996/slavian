class_name LocalBridge
extends RefCounted
## The Kalinov Bridge's rules for the local engine: server/src/sim/bridge.ts.
## Dates in the bridge's state are ISO strings, as the server keeps them.


static func new_bridge(at: int, sanctity: int) -> Dictionary:
	return {"stage": 0, "donated": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "embers": 0, "quests": {},
		"stageStartedAt": LocalTime.iso(at), "sanctityAtStart": sanctity, "status": "open", "raisedAt": null}


static func current_stage(data: Dictionary, bridge: Dictionary) -> Variant:
	if bridge.status == "complete" or int(bridge.stage) >= data.bridge.stages.size():
		return null
	return data.bridge.stages[int(bridge.stage)]


## Svarog's Embers the open stage still wants: its own and, when its quest
## is open, the ritual torc's (sim/bridge.ts embersWanted).
static func embers_wanted(data: Dictionary, bridge: Dictionary) -> int:
	var need := needs(data, bridge)
	return int(need.embers) + (int(data.bridge.ritualEmbers) if "ritual" in need.quests else 0)


## What the stage still needs: {resources, embers, quests}.
static func needs(data: Dictionary, bridge: Dictionary) -> Dictionary:
	var stage: Variant = current_stage(data, bridge)
	if stage == null:
		return {"resources": {"wood": 0, "stone": 0, "grain": 0, "iron": 0}, "embers": 0, "quests": []}
	var quests: Array = []
	for q in stage.quests:
		if not bridge.quests.has(q.kind):
			quests.append(q.kind)
	return {
		"resources": LocalVillage.resources(func(kind: String) -> float: return maxf(0.0, float(stage.cost[kind]) - float(bridge.donated[kind]))),
		"embers": maxi(0, int(stage.embers) - int(bridge.embers)), "quests": quests,
	}


static func is_ready(data: Dictionary, bridge: Dictionary) -> bool:
	var need := needs(data, bridge)
	return bridge.status == "open" and LocalLedger.KINDS.all(func(k: String) -> bool: return float(need.resources[k]) == 0.0) \
		and int(need.embers) == 0 and need.quests.is_empty()


## A quest of the open stage is done (null: not one of its open quests).
static func complete_quest(data: Dictionary, bridge: Dictionary, quest: String, at: int) -> Variant:
	if bridge.status != "open" or bridge.quests.has(quest):
		return null
	var stage: Variant = current_stage(data, bridge)
	if stage == null or not stage.quests.any(func(q: Dictionary) -> bool: return q.kind == quest):
		return null
	var next := bridge.duplicate(true)
	next.quests[quest] = LocalTime.iso(at)
	return next


static func start_raising(data: Dictionary, bridge: Dictionary, at: int, world_speed: float) -> Dictionary:
	var next := bridge.duplicate(true)
	next.status = "raising"
	next.raisedAt = LocalTime.iso(LocalTime.ms(at + (float(data.bridge.buildHours) * 3600000.0) / world_speed))
	return next


## sim/bridge.ts bridgeBonuses: the blessings of every stage that stands.
static func bridge_bonuses(data: Dictionary, bridge: Variant) -> Dictionary:
	var out := {}
	if not bridge is Dictionary or bridge.is_empty():
		return out
	var stages: Array = data.bridge.stages
	for i in mini(int(bridge.stage), stages.size()):
		var effects: Dictionary = stages[i].get("reward", {}).get("effects", {})
		for key in effects:
			out[key] = float(out.get(key, 0.0)) + float(effects[key])
	return out


## sim/bridge.ts questCell: where a quest's ruin or lair rises: the first
## open hex minDistance to maxDistance from the Holy City, nearest first,
## each ring walked from a point the seed picks (Vector2i.MAX: none).
static func quest_cell(data: Dictionary, terrain: Dictionary, taken: Dictionary, seed_value: int, min_distance: int, max_distance: int, center := Vector2i.ZERO) -> Vector2i:
	for d in range(min_distance, max_distance + 1):
		var cells := HexMath.ring(center, d)
		var start := (seed_value & 0xffffffff) % cells.size()
		for i in cells.size():
			var cell: Vector2i = cells[(start + i) % cells.size()]
			var key := LocalLand.key(cell)
			var kind: Variant = terrain.get(key)
			if kind == null or kind == "holy_city" or taken.has(key):
				continue
			var def: Dictionary = data.terrain.terrain.get(kind, {})
			if def.is_empty() or def.moveCost == null or def.get("edge", false):
				continue
			return cell
	return Vector2i.MAX


## Who each front's small horde strikes while a stage is raised: the
## group's villages in order, then the Holy City (null).
static func construction_targets(fronts: Array, villages: Array) -> Array:
	var targets: Array = villages.duplicate()
	targets.append(null)
	var out: Array = []
	for i in fronts.size():
		out.append(targets[i % targets.size()])
	return out


static func construction_size(data: Dictionary, stage: int) -> int:
	var rules: Dictionary = data.bridge.constructionRaids
	return int(rules.units) + int(rules.unitsPerStage) * (stage + 1)
