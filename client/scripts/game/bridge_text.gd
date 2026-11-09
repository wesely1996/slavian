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
		return UI.t("The Kalinov Bridge stands")
	return UI.t("Stage %d of %d: %s") % [int(bridge.stage) + 1, data.bridge.stages.size(), UI.t(stage.name)]


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
			parts.append(UI.t("%s %d / %d") % [UI.resource_name(kind), mini(need, int(bridge.donated.get(kind, 0))), need])
	if int(stage.embers) > 0:
		parts.append(UI.t("Ember %d / %d") % [int(bridge.get("embers", 0)), int(stage.embers)])
	return ", ".join(parts)


## [[done, quest name, its story for this stage], …].
static func quests(data: Dictionary, bridge: Dictionary) -> Array:
	var stage := stage_def(data, bridge)
	var out := []
	if stage.is_empty():
		return out
	for quest in stage.quests:
		var def: Dictionary = data.bridge.quests.get(quest.kind, {})
		out.append([bridge.quests.has(quest.kind), UI.t(def.get("name", quest.kind)), UI.t(quest.story)])
	return out


## What a stage brings when it stands: "Every member gets 800 wood, … ·
## Blessing of the Old Builders: +5% all production" ("" for none).
static func reward(stage: Dictionary) -> String:
	var prize: Dictionary = stage.get("reward", {})
	var parts := PackedStringArray()
	var gift: Dictionary = prize.get("resources", {})
	var amounts := PackedStringArray()
	for kind in ["wood", "stone", "grain", "iron"]:
		if int(gift.get(kind, 0)) > 0:
			amounts.append("%d %s" % [int(gift[kind]), UI.resource_name(kind).to_lower()])
	if not amounts.is_empty():
		parts.append(UI.t("every member gets %s") % ", ".join(amounts))
	var effects: Dictionary = prize.get("effects", {})
	if not effects.is_empty():
		parts.append(UI.t("%s for the rest of the run: %s") % [UI.t(String(prize.get("name", ""))), HeroText.effects(effects)])
	return UI.t("When it stands: %s.") % "; ".join(parts) if not parts.is_empty() else ""
