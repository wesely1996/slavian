class_name OnboardingText
extends RefCounted
## The getting-started chain (data/onboarding.json, server scheduler/onboarding.ts).
## A member's "onboarding" holds the steps done, "onboardingClaimed" the
## rewards claimed (and "finale" once the chain's own reward is in).


## The step the quest card shows: the first done one whose reward waits,
## else the first one not done yet, else {} when the chain is over. In a
## `solo` world, in its solo words (worded).
static func current(data: Dictionary, member: Dictionary, solo := false) -> Dictionary:
	var done: Dictionary = member.get("onboarding", {})
	var claimed: Dictionary = member.get("onboardingClaimed", {})
	for step in data.onboarding.steps:
		if done.has(step.id) and not claimed.has(step.id):
			return worded(step, solo)
	return next_step(data, member, solo)


## The first step this member has not done yet, or {} when all are done.
static func next_step(data: Dictionary, member: Dictionary, solo := false) -> Dictionary:
	var done: Dictionary = member.get("onboarding", {})
	for step in data.onboarding.steps:
		if not done.has(step.id):
			return worded(step, solo)
	return {}


## The step with its solo words in a solo world, where there are no
## teammates (its `solo` in data/onboarding.json).
static func worded(step: Dictionary, solo: bool) -> Dictionary:
	if not solo or not step.get("solo") is Dictionary:
		return step
	var out := step.duplicate()
	out.merge(step.solo, true)
	return out


## Whether the step is done and its reward waits to be claimed.
static func claimable(member: Dictionary, step: Dictionary) -> bool:
	return not step.is_empty() and member.get("onboarding", {}).has(step.id) and not member.get("onboardingClaimed", {}).has(step.id)


## "Getting started 2 of 6": rewards claimed of all.
static func progress(data: Dictionary, member: Dictionary) -> String:
	var claimed := 0
	for step in data.onboarding.steps:
		if member.get("onboardingClaimed", {}).has(step.id):
			claimed += 1
	return UI.t("Getting started %d of %d") % [claimed, data.onboarding.steps.size()]


## "Reward: Wood 150, Stone 150, …".
static func reward(step: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in ["wood", "stone", "grain", "iron"]:
		if int(step.reward.get(kind, 0)) > 0:
			parts.append(UI.t("%s %d") % [UI.resource_name(kind), int(step.reward[kind])])
	return UI.t("Reward: ") + ", ".join(parts)


## "1. Tap Village in the top bar." lines.
static func how(step: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var lines: Array = step.get("how", [])
	for i in lines.size():
		out.append("%d. %s" % [i + 1, UI.t(lines[i])])
	return out
