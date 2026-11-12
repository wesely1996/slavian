class_name LocalChampions
extends RefCounted
## Heroes and generals in battle (scheduler/champions.ts): they lead their
## troops and fight in the ranks. One commands: the hero if there is one,
## else the general, who takes the hero's place when the hero falls. A
## champion struck down falls: a hero is carried home wounded, a general dies.


## `base` with the commander's bonuses: the hero's, else the general's
## (either may be {}).
static func command_bonuses(data: Dictionary, base: Dictionary, hero: Dictionary, general: Dictionary) -> Dictionary:
	if not hero.is_empty():
		return LocalHeroes.combine(base, LocalHeroes.hero_bonuses(data, hero))
	if not general.is_empty():
		return LocalHeroes.combine(base, LocalGenerals.bonuses(data, general))
	return base.duplicate()


## The champions fighting with a force: its hero, its general.
static func champions_of(data: Dictionary, hero: Dictionary, general: Dictionary) -> Array:
	var out: Array = []
	if not hero.is_empty():
		out.append(LocalBattle.champion_of(data, "hero", int(hero.level)))
	if not general.is_empty():
		out.append(LocalBattle.champion_of(data, "general", int(general.level)))
	return out


## Champions struck down in a round: a hero is wounded (with an army,
## carried home to `home_village_id`), a general dies.
static func fall(server: LocalServer, world: Dictionary, fallen: Array, hero: Dictionary, general: Dictionary, home_village_id: Variant, input: Dictionary) -> void:
	if "hero" in fallen and not hero.is_empty():
		if home_village_id != null:
			hero.villageId = home_village_id
			hero.armyId = null
		LocalBattles.hero_after_battle(server, world, hero, {"kills": int(input.kills), "won": false, "battleId": input.battleId, "at": input.at})
		LocalAchievements.achieve(server, world, hero.accountId, "hero_fallen", int(input.at))
	if "general" in fallen and not general.is_empty():
		LocalGenerals.after_battle(server, world, general, {"kills": int(input.kills), "won": false, "at": input.at})
