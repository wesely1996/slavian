class_name LeaderText
extends RefCounted
## Words for the enemy's leaders (server leaderView, data/leaders.json).


## "Khan Konchak · level 4"
static func name_line(leader: Dictionary) -> String:
	return UI.t("%s · level %d") % [leader.title, int(leader.level)]


## "3 battles: 2 won, 1 lost · 1 village razed · 14 of ours slain"
static func record(leader: Dictionary) -> String:
	var parts := PackedStringArray([UI.tn("%d battle: %d won, %d lost", "%d battles: %d won, %d lost", int(leader.battles)) % [int(leader.battles), int(leader.wins), int(leader.losses)]])
	if int(leader.razed) > 0:
		parts.append(UI.tn("%d village razed", "%d villages razed", int(leader.razed)) % int(leader.razed))
	if int(leader.kills) > 0:
		parts.append(UI.t("%d of ours slain") % int(leader.kills))
	return " · ".join(parts)


## Where they stand now: fallen, wounded (and for how long), or ready.
static func state(leader: Dictionary, now: float) -> String:
	if leader.status == "dead":
		return UI.t("Fell in battle")
	var wounded: Variant = leader.get("woundedUntil")
	if wounded != null and TimeUtil.parse_iso(wounded) > now:
		return UI.t("Wounded · back in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(wounded) - now)
	return UI.t("Ready to ride")


## "+8% attack, +4% defense, holds 6% longer": what they give their horde.
static func effects(leader: Dictionary) -> String:
	var fx: Dictionary = leader.get("effects", {})
	var parts := PackedStringArray()
	if float(fx.get("attack", 0)) > 0:
		parts.append(UI.t("+%d%% attack") % roundi(float(fx.attack) * 100.0))
	if float(fx.get("defense", 0)) > 0:
		parts.append(UI.t("+%d%% defense") % roundi(float(fx.defense) * 100.0))
	if float(fx.get("nerve", 0)) > 0:
		parts.append(UI.t("holds %d%% longer") % roundi(float(fx.nerve) * 100.0))
	if float(fx.get("loot", 0)) > 0:
		parts.append(UI.t("+%d%% plunder") % roundi(float(fx.loot) * 100.0))
	return ", ".join(parts) if not parts.is_empty() else UI.t("no skills yet")


## "Swore revenge on Vesna's village (+15% attack there)", or "".
static func grudge(data: Dictionary, leader: Dictionary, village_name: Callable) -> String:
	if leader.get("grudgeVillageId") == null or leader.status == "dead":
		return ""
	var bonus := roundi(float(data.get("leaders", {}).get("grudge", {}).get("attack", 0)) * 100.0)
	return UI.t("Swore revenge on %s (+%d%% attack there)") % [village_name.call(leader.grudgeVillageId), bonus]


## How a battle left its leader, for the end of the battle story.
static func after_battle(leader: Dictionary, battle: Dictionary, place: String) -> String:
	if leader.is_empty() or battle.get("status", "ongoing") == "ongoing":
		return ""
	var assault := battle.get("campId") != null or battle.get("siteId") != null
	if assault:
		return ""
	if battle.status == "raided":
		return UI.t("%s rode on, prouder.") % leader.title
	if leader.status == "dead" and leader.get("diedAt") != null and battle.get("endedAt") != null and String(leader.diedAt) == String(battle.endedAt):
		return UI.t("%s fell with the last of them.") % leader.title
	return UI.t("%s fled the field wounded, swearing revenge on %s.") % [leader.title, place]
