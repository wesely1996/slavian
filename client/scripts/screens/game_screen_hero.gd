extends "res://scripts/screens/game_screen_logistics.gd"
## The in-world screen, the hero's part: its sheet, skills, gear and quests.

## Where your hero is, seen from a village, with the way to its panel.
func _hero_line(village_id: int) -> void:
	var hero := Game.my_hero()
	if hero.is_empty():
		return
	var row := UI.hbox()
	var text := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var open := UI.button(tr("Hero"), func() -> void:
		_panel_mode = "hero"
		_rebuild_panel())
	open.custom_minimum_size.x = 120
	row.add_child(open)
	_panel_body.add_child(row)
	_tick(text, func() -> String: return HeroText.whereabouts(hero, village_id, Game.village_name(hero.villageId), Game.server_now()))


## Your hero: level, skills, gear and journeys.
func _hero_panel() -> void:
	var hero := Game.my_hero()
	if hero.is_empty():
		return
	var top := UI.hbox()
	var title := UI.label(tr("%s  Lv %d") % [hero.name, int(hero.level)], UI.HEADING_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_panel_body.add_child(top)
	var kind: Variant = hero.get("kind")
	var face := "hero/%s" % kind if kind != null and Art.has("hero/%s" % kind) else "ui/hero"
	_side_tabs("hero", [["about", face, tr("Your hero"), _hero_about.bind(hero)],
		["quests", "site/kurgan", tr("Quests"), _quest_section.bind(hero)],
		["stats", "icon/troops", tr("Stats"), _hero_stats.bind(hero)],
		["skills", "icon/research", tr("Skills"), _hero_skills.bind(hero)],
		["gear", "resource/iron", tr("Gear"), _hero_gear.bind(hero)],
		["journey", "icon/map", tr("Send to"), _hero_journey.bind(hero)]])


## Who it is: the portrait, the roster hero's strengths and traits, where
## it is and how far to the next level.
func _hero_about(hero: Dictionary) -> void:
	var kind: Variant = hero.get("kind")
	if not HeroText.roster(Game.data, kind).is_empty():
		var card := UI.hbox(14)
		var face := HeroText.portrait(kind, 104.0)
		face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.add_child(face)
		var about := UI.vbox(4)
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about.add_child(UI.label(tr(HeroText.roster(Game.data, kind).title), 0, UI.ACCENT))
		about.add_child(UI.label(tr("In all your villages: %s") % HeroText.effects(HeroText.roster(Game.data, kind).effects), UI.SMALL_SIZE))
		for line in HeroText.roster_traits(Game.data, kind):
			about.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
		card.add_child(about)
		_panel_body.add_child(card)
	var status := UI.label("", UI.SMALL_SIZE)
	_panel_body.add_child(status)
	_tick(status, func() -> String: return HeroText.whereabouts(hero, -1, Game.village_name(hero.villageId), Game.server_now()))
	var xp_text := tr("XP %d / %d") % [int(hero.xp), int(hero.xpToNext)] if hero.xpToNext != null else tr("Highest level")
	_panel_body.add_child(UI.with_info(UI.label(xp_text, UI.SMALL_SIZE, UI.MUTED), tr("XP comes from enemies slain while leading a garrison.")))
	if hero.xpToNext != null:
		var xp_bar := _gauge(UI.ACCENT)
		xp_bar.value = clampf(float(hero.xp) / maxf(1.0, float(hero.xpToNext)), 0.0, 1.0)
		_panel_body.add_child(xp_bar)
	if int(hero.skillPoints) > 0:
		var spend := UI.primary(tr_n("Spend %d skill point", "Spend %d skill points", int(hero.skillPoints)) % int(hero.skillPoints), func() -> void:
			_side["hero"] = "skills"
			_scroll.scroll_vertical = 0
			_rebuild_panel(), "icon/research")
		_panel_body.add_child(spend)
	var effects := HeroText.effects(hero.bonuses)
	if effects != "":
		_panel_body.add_child(UI.label(tr("Adds where it stands: %s") % effects, UI.SMALL_SIZE, UI.MUTED))


## What the hero adds, and from where: its own gifts (in all your
## villages), its skills and its gear (where it stands), and the total.
func _hero_stats(hero: Dictionary) -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Stats"), UI.HEADING_SIZE),
		tr("Its own gifts count in all your villages; what its skills and gear add counts where it stands, and for the army it leads.")))
	var xp_text := tr("XP %d / %d") % [int(hero.xp), int(hero.xpToNext)] if hero.xpToNext != null else tr("Highest level")
	_panel_body.add_child(UI.label(tr("Level %d · %s") % [int(hero.level), xp_text], UI.SMALL_SIZE, UI.MUTED))
	_panel_body.add_child(_champion_line("hero", int(hero.level)))
	for line in HeroText.base_stats(Game.data, hero, float(Game.world.speed)):
		_panel_body.add_child(UI.label(line, UI.SMALL_SIZE))
	var parts := HeroText.breakdown(Game.data, hero)
	if parts.is_empty():
		_panel_body.add_child(UI.label(tr("No bonuses yet."), UI.SMALL_SIZE, UI.MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for heading in [tr("Bonus"), tr("Own"), tr("Skills"), tr("Gear"), tr("Total")]:
		var head := UI.label(heading, UI.SMALL_SIZE, UI.MUTED)
		head.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if heading == tr("Bonus") else HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(head)
	for key in parts:
		var name := UI.label(HeroText.effect_name(key), UI.SMALL_SIZE)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name)
		for column in 4:
			var value: float = parts[key][column]
			var cell := UI.label(HeroText.percent(value), UI.SMALL_SIZE,
				UiTheme.INK if column < 3 or is_zero_approx(value) else (UI.GOOD if HeroText.helps(key, value) else UI.ERROR))
			cell.autowrap_mode = TextServer.AUTOWRAP_OFF
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(cell)
	_panel_body.add_child(grid)


## The skill tree, a branch to a page on a phone.
func _hero_skills(hero: Dictionary) -> void:
	var data: Dictionary = Game.data.heroes
	var skill_word := tr_n("skill point", "skill points", int(hero.skillPoints))
	_panel_body.add_child(UI.label(tr("%d %s to spend") % [int(hero.skillPoints), skill_word], UI.SMALL_SIZE, UI.MUTED))
	_paged("hero skills", data.branches.keys(), 1, func(branch: String) -> void:
		_panel_body.add_child(UI.label(tr(data.branches[branch]), UI.HEADING_SIZE))
		for skill in data.skills:
			var def: Dictionary = data.skills[skill]
			if def.branch != branch:
				continue
			var rank := int(hero.skills.get(skill, 0))
			var card := UI.card(10)
			var row := UI.hbox()
			card.add_child(row)
			var info := UI.vbox(2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var head := UI.hbox(10)
			var name := UI.label(tr(def.name))
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.add_child(name)
			# Its ranks as pips: filled for those learned.
			var pips := UI.label("●".repeat(rank) + "○".repeat(maxi(0, int(def.maxRank) - rank)), UI.SMALL_SIZE, UI.ACCENT if rank > 0 else UI.MUTED)
			pips.autowrap_mode = TextServer.AUTOWRAP_OFF
			pips.tooltip_text = tr("%d of %d") % [rank, int(def.maxRank)]
			head.add_child(pips)
			info.add_child(head)
			info.add_child(UI.label(tr(def.description), UI.SMALL_SIZE, UI.MUTED))
			row.add_child(info)
			if rank < int(def.maxRank) and int(hero.skillPoints) > 0:
				var learn := UI.primary("+", func() -> void: _hero_action("skills", {"skill": skill}))
				learn.custom_minimum_size.x = 80
				learn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(learn)
			_panel_body.add_child(card))


## What the hero wears, and what it carries to wear.
func _hero_gear(hero: Dictionary) -> void:
	var data: Dictionary = Game.data.heroes
	_panel_body.add_child(UI.label(tr("Gear"), UI.HEADING_SIZE))
	# What it wears: a card for each slot, two abreast.
	var slots := GridContainer.new()
	slots.columns = 2
	slots.add_theme_constant_override("h_separation", 8)
	slots.add_theme_constant_override("v_separation", 8)
	for slot in data.slots:
		var item: Variant = hero.gear.get(slot)
		var card := UI.card(8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var worn := UI.vbox(2)
		card.add_child(worn)
		worn.add_child(UI.label(tr(String(slot).capitalize()), UI.SMALL_SIZE - 2, UI.MUTED))
		worn.add_child(UI.label(tr(data.items[item].name) if item != null else tr("Empty"), UI.SMALL_SIZE, UiTheme.INK if item != null else UI.MUTED))
		if item != null:
			worn.add_child(UI.label(HeroText.effects(data.items[item].effects), UI.SMALL_SIZE - 2, UI.GOOD))
			var off := UI.button(tr("Take off"), func() -> void: _hero_action("unequip", {"slot": slot}))
			off.add_theme_font_size_override("font_size", UI.SMALL_SIZE)
			off.custom_minimum_size.y = 52
			worn.add_child(off)
		slots.add_child(card)
	_panel_body.add_child(slots)
	# Sets: what wearing all of one adds, and how much of it is worn.
	var wearing: Array = hero.gear.values()
	for set_id in data.get("sets", {}):
		var set_def: Dictionary = data.sets[set_id]
		var have: int = set_def.items.filter(func(it: String) -> bool: return it in wearing).size()
		if have > 0:
			_panel_body.add_child(UI.label(tr("%s set (%d of %d worn): %s") % [tr(set_def.get("name", set_id)), have, set_def.items.size(), HeroText.effects(set_def.effects)],
				UI.SMALL_SIZE, UI.GOOD if have == set_def.items.size() else UI.MUTED))
	if hero.inventory.is_empty():
		_panel_body.add_child(UI.with_info(UI.label(tr("No gear yet."), UI.SMALL_SIZE, UI.MUTED), tr("Beaten hordes sometimes leave gear behind for a hero who fought them.")))
	_paged("hero gear", hero.inventory, 4 if _roomy() else 2, func(item: String) -> void:
		var def: Dictionary = data.items[item]
		var card := UI.card(8)
		var row := UI.hbox()
		card.add_child(row)
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(tr("%s (%s)") % [tr(def.name), def.slot]))
		info.add_child(UI.label(HeroText.effects(def.effects), UI.SMALL_SIZE, UI.MUTED))
		row.add_child(info)
		var wear := UI.primary(tr("Wear"), func() -> void: _hero_action("equip", {"item": item}))
		wear.custom_minimum_size.x = 120
		wear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(wear)
		_panel_body.add_child(card))


## Send the hero to another of your villages, or rename it.
func _hero_journey(hero: Dictionary) -> void:
	var mine := Game.my_villages().filter(func(v: Dictionary) -> bool:
		return Game.is_mine(v) and (hero.villageId == null or int(hero.villageId) != int(v.id)))
	_panel_body.add_child(UI.label(tr("Send to"), UI.HEADING_SIZE))
	if mine.is_empty():
		_panel_body.add_child(UI.label(tr("Found another village to send the hero there."), UI.SMALL_SIZE, UI.MUTED))
	_paged("hero journey", mine, 6 if _roomy() else 3, func(village: Dictionary) -> void:
		var target := int(village.id)
		var go := UI.button(village.name, func() -> void: _hero_action("move", {"villageId": target}), Art.settlement_id(Rules.hall_level(village)))
		go.disabled = hero.status != "home"
		_panel_body.add_child(go))
	_panel_body.add_child(UI.label(tr("Name"), UI.HEADING_SIZE))
	var key := "hero:%d" % int(hero.accountId)
	var name_edit := _draft_field(key, tr("New name"), hero.name)
	_panel_body.add_child(name_edit)
	var rename := func(_text := "") -> void:
		if await _hero_action("rename", {"name": name_edit.text.strip_edges()}):
			_drafts.erase(key)
	name_edit.text_submitted.connect(rename)
	_panel_body.add_child(UI.button(tr("Rename"), rename))


## The quests the hero is offered, or the one it is on.
func _quest_section(hero: Dictionary) -> void:
	_panel_body.add_child(UI.with_info(UI.label(tr("Quests"), UI.HEADING_SIZE), tr("The hero rides out alone: no garrison to lead while away, and a chance to come back wounded. New quests every few hours.")))
	var kinds: Dictionary = Game.data.get("quests", {}).get("kinds", {})
	if hero.status == "questing" and hero.get("quest") is Dictionary:
		var quest: Dictionary = hero.quest
		_panel_body.add_child(UI.label(tr(kinds.get(String(quest.kind), {}).get("name", "")), 0, UI.ACCENT))
		_panel_body.add_child(UI.label(HeroText.quest_description(Game.data, quest, _site_name(quest.get("siteId"))), UI.SMALL_SIZE, UI.MUTED))
		var back := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(back)
		_tick(back, func() -> String: return tr("Back in %s") % TimeUtil.format_duration(TimeUtil.parse_iso(String(quest.returnsAt)) - Game.server_now()))
		# Called off: it turns for home where it is, and brings nothing back.
		if quest.get("cancelled", false) == true:
			_panel_body.add_child(UI.label(tr("Called off: coming home empty-handed."), UI.SMALL_SIZE, UI.MUTED))
		else:
			_panel_body.add_child(UI.with_info(UI.button(tr("Call off the quest"), func() -> void: _hero_action("quest/cancel", {})),
				tr("The hero turns for home where it is (as far back as it went, or from the place itself) and brings nothing back. Once on the way home, it can't be called off.")))
		return
	# The army quest it leads its army on: where, and how long it stands.
	if hero.get("armyQuest") is Dictionary:
		var on: Dictionary = hero.armyQuest
		_panel_body.add_child(UI.label(tr(HeroText.quest_def(Game.data, on).get("name", "")), 0, UI.ACCENT))
		_panel_body.add_child(UI.label(HeroText.quest_description(Game.data, on), UI.SMALL_SIZE, UI.MUTED))
		var left := UI.label("", UI.SMALL_SIZE)
		_panel_body.add_child(left)
		if on.get("endsAt") != null:
			_tick(left, func() -> String: return tr("At (%d, %d), gone in %s") % [int(on.q), int(on.r), TimeUtil.format_duration(TimeUtil.parse_iso(String(on.endsAt)) - Game.server_now())])
		var cell := Vector2i(int(on.q), int(on.r))
		_panel_body.add_child(UI.button(tr("Show on the map"), func() -> void: _go_to(cell), "icon/map"))
		return
	var offers: Array = hero.get("offers", [])
	if offers.is_empty():
		var why := tr("No quests while the hero is away or wounded.")
		if hero.status == "with_army":
			why = tr("Army quests come while the army the hero leads stands still.")
		_panel_body.add_child(UI.label(why, UI.SMALL_SIZE, UI.MUTED))
		return
	if hero.status == "with_army":
		_panel_body.add_child(UI.with_info(UI.label(tr("Army quests"), UI.SMALL_SIZE, UI.MUTED), tr("Leading an army, the hero can take it on harder quests: their place rises near the army, which marches on it at once. Clear it in time for XP and the spoils.")))
	_paged("quests", offers, 3 if _roomy() else 1, func(offer: Dictionary) -> void:
		var army: bool = offer.get("army", false)
		var row := UI.hbox()
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(tr(HeroText.quest_def(Game.data, offer).get("name", ""))))
		info.add_child(UI.label(HeroText.quest_description(Game.data, offer, _site_name(offer.get("siteId"))), UI.SMALL_SIZE, UI.MUTED))
		info.add_child(UI.label(HeroText.quest_terms(offer, float(Game.world.get("speed", 1))), UI.SMALL_SIZE))
		row.add_child(info)
		var go := UI.primary(tr("Lead the army") if army else tr("Set out"), func() -> void: _hero_action("quest", {"offer": String(offer.id)}))
		go.disabled = hero.status != ("with_army" if army else "home")
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(go)
		var card := UI.card(10)
		card.add_child(row)
		_panel_body.add_child(card))


## True when the server took it.
func _hero_action(action: String, body: Dictionary) -> bool:
	_status.text = ""
	var response := await Api.post_json("/v1/worlds/%d/hero/%s" % [Game.world_id(), action], body)
	if not response.ok:
		_status.text = response.error
		return false
	Game.note_server_time(response.data.serverTime)
	var updated: Dictionary = response.data.hero
	var heroes := Game.heroes.filter(func(h: Dictionary) -> bool: return int(h.accountId) != int(updated.accountId))
	heroes.append(updated)
	Game.set_heroes(Game.world_id(), heroes)
	return true


## A bridge quest's ruin or lair: its name and what the quest asks.
func _quest_place_line(quest: Variant) -> void:
	# A hero's army quest ("hero:<account>:<kind>"): whose, and what.
	if quest is String and String(quest).begins_with("hero:"):
		var parts := String(quest).split(":")
		var def: Dictionary = Game.data.get("quests", {}).get("army", {}).get("kinds", {}).get(parts[2] if parts.size() > 2 else "", {})
		if not def.is_empty():
			var whose := ""
			for h in Game.heroes:
				if str(h.accountId) == parts[1]:
					whose = String(h.name)
			_panel_body.add_child(UI.with_info(UI.label(tr(String(def.name)), UI.HEADING_SIZE, UiTheme.GOLD),
				(tr("%s's quest with the army.") % whose + " " if whose != "" else "") + tr(String(def.description))))
		return
	if quest == null or not Game.data.bridge.questPlaces.has(String(quest)):
		return
	var place: Dictionary = Game.data.bridge.questPlaces[String(quest)]
	var asks: Dictionary = Game.data.bridge.quests.get(String(quest), {})
	_panel_body.add_child(UI.with_info(UI.label(tr(String(place.name)), UI.HEADING_SIZE, UiTheme.GOLD), tr(String(asks.get("description", "")))))
