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
