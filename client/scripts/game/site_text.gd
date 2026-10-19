class_name SiteText
extends RefCounted
## Words for ancient sites and lore scrolls (see server/src/sim/sites.ts).


## "Hymn of Dazhbog", "Axe of Perun", "a Svarog's Ember", "Wood 600, …".
static func find(data: Dictionary, found: Variant) -> String:
	if not found is Dictionary:
		return ""
	match found.type:
		"gear":
			return data.heroes.items.get(found.item, {}).get("name", found.item)
		"ember":
			return "a Svarog's Ember"
		"scroll":
			return "the scroll “%s”" % data.lore.scrolls.get(found.scroll, {}).get("name", found.scroll)
	var parts := PackedStringArray()
	for kind in ["wood", "stone", "grain", "iron"]:
		if int(found.resources.get(kind, 0)) > 0:
			parts.append("%s %d" % [kind.capitalize(), int(found.resources[kind])])
	return ", ".join(parts)


## "Watched by 30 guardians" / "Guardians unknown" / "Nothing watches it".
static func guardians(site: Dictionary) -> String:
	if site.get("guardians") == null:
		return "Whether anything guards it is unknown"
	if int(site.guardians) <= 0:
		return "Nothing watches it any more"
	return "Watched by %d guardians" % int(site.guardians)


## "Explored by Vesna: found the scroll …" or "Unexplored · Watched by …".
static func status(data: Dictionary, site: Dictionary, explorer: String) -> String:
	if site.status == "explored":
		return "Explored by %s: found %s" % [explorer, find(data, site.find)]
	return "Unexplored · %s" % guardians(site)


## Scroll effects as "+5% attack" style text, or what it unlocks.
static func scroll_effect(data: Dictionary, scroll: String) -> String:
	var def: Dictionary = data.lore.scrolls.get(scroll, {})
	return def.get("description", "")
