class_name LocalAchievements
## Achievements (scheduler/achievements.ts): earned once per player per
## run, where the game's moments happen, and told with a push notice.


static func achieve(server: LocalServer, world: Dictionary, account_id: Variant, achievement: String, at: int) -> void:
	if account_id == null:
		return
	world.merge({"achievements": []})
	for earned in world.achievements:
		if int(earned.accountId) == int(account_id) and earned.achievement == achievement:
			return
	world.achievements.append({"accountId": int(account_id), "achievement": achievement, "earnedAt": at})
	var def: Dictionary = server.data.achievements.achievements[achievement]
	LocalInbox.tell(server, world, int(account_id), {"kind": "achievement", "tier": "push", "title": "Achievement: {name}", "body": "{description}",
		"vars": {"name": def.name, "description": def.description}}, at)


## For every member of the run.
static func achieve_all(server: LocalServer, world: Dictionary, achievement: String, at: int) -> void:
	for member in world.members:
		achieve(server, world, member.accountId, achievement, at)


static func view(world: Dictionary) -> Array:
	return world.get("achievements", []).map(func(e: Dictionary) -> Dictionary:
		return {"accountId": e.accountId, "achievement": e.achievement, "earnedAt": LocalTime.iso(e.earnedAt)})
