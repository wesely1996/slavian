class_name BridgeText
extends RefCounted
## Words for the Kalinov Bridge (see server/src/sim/bridge.ts).

const KINDS := ["wood", "stone", "grain", "iron"]


static func stage_def(data: Dictionary, bridge: Dictionary) -> Dictionary:
	if bridge.get("status", "") == "complete":
		return {}
	var stages: Array = data.bridge.stages
	var i := int(bridge.get("stage", 0))
	return stages[i] if i < stages.size() else {}


## "Stage 2 of 5: The Oak Piers" or "The bridge stands".
static func title(data: Dictionary, bridge: Dictionary) -> String:
	var stage := stage_def(data, bridge)
	if stage.is_empty():
		return "The Kalinov Bridge stands"
	return "Stage %d of %d: %s" % [int(bridge.stage) + 1, data.bridge.stages.size(), stage.name]


## What the stage still needs from the vault: {wood: n, …}.
static func missing(data: Dictionary, bridge: Dictionary) -> Dictionary:
	var stage := stage_def(data, bridge)
	var out := {}
	for kind in KINDS:
		out[kind] = 0 if stage.is_empty() else maxi(0, int(stage.cost[kind]) - int(bridge.donated.get(kind, 0)))
	return out


static func embers_missing(data: Dictionary, bridge: Dictionary) -> int:
	var stage := stage_def(data, bridge)
	return 0 if stage.is_empty() else maxi(0, int(stage.embers) - int(bridge.get("embers", 0)))


## "Wood 3000 / 5000, Stone done, …" for the stage's cost.
static func progress(data: Dictionary, bridge: Dictionary) -> String:
	var stage := stage_def(data, bridge)
	if stage.is_empty():
		return ""
	var parts := PackedStringArray()
	for kind in KINDS:
		var need := int(stage.cost[kind])
		if need > 0:
			parts.append("%s %d / %d" % [kind.capitalize(), mini(need, int(bridge.donated.get(kind, 0))), need])
	if int(stage.embers) > 0:
		parts.append("Ember %d / %d" % [int(bridge.get("embers", 0)), int(stage.embers)])
	return ", ".join(parts)


## [[done, quest name, its story for this stage], …].
static func quests(data: Dictionary, bridge: Dictionary) -> Array:
	var stage := stage_def(data, bridge)
	var out := []
	if stage.is_empty():
		return out
	for quest in stage.quests:
		var def: Dictionary = data.bridge.quests.get(quest.kind, {})
		out.append([bridge.quests.has(quest.kind), def.get("name", quest.kind), quest.story])
	return out
