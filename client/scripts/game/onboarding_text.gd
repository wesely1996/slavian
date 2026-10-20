class_name OnboardingText
extends RefCounted
## The getting-started chain (data/onboarding.json, server scheduler/onboarding.ts).


## The first step this member has not done yet, or {} when all are done.
static func next_step(data: Dictionary, member: Dictionary) -> Dictionary:
	var done: Dictionary = member.get("onboarding", {})
	for step in data.onboarding.steps:
		if not done.has(step.id):
			return step
	return {}


## "Getting started 2 of 6".
static func progress(data: Dictionary, member: Dictionary) -> String:
	return UI.t("Getting started %d of %d") % [member.get("onboarding", {}).size(), data.onboarding.steps.size()]


## "Reward: Wood 150, Stone 150, …".
static func reward(step: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in ["wood", "stone", "grain", "iron"]:
		if int(step.reward.get(kind, 0)) > 0:
			parts.append(UI.t("%s %d") % [UI.resource_name(kind), int(step.reward[kind])])
	return UI.t("Reward: ") + ", ".join(parts)
