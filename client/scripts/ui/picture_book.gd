class_name PictureBook
extends Control
## The intro: a few pictured pages on how the game goes (the run, the first
## steps, the hero, the village, the map, the hordes, battle), turned with
## Back and Next, skippable at any page. Emits `closed` when put away.

signal closed

## [title, words] a page; the words name the mechanics.
const PAGES := [
	["The Holy City", "Hordes come from the edges of the world, wave after wave, for the Holy City at its heart. Raise villages around it, hold them, and build the Kalinov Bridge before the city falls."],  # tr
	["First steps", "The card at the top of the map shows the next step and why it matters, with a reward for each. Stuck? The ? button explains; once the steps are done it opens the almanac."],  # tr
	["Your hero", "A hero from the old tales leads your armies. It gains levels and skills, wears gear that beaten hordes leave behind, and goes on quests for more."],  # tr
	["Your village", "Fields bring wood, stone, grain and iron, and each village keeps its own stores. The Elder's Hall opens more plots; barracks train troops; walls and towers keep the hordes out."],  # tr
	["The map", "Around your villages lie rich hexes for outposts, roads that speed marches, camps to clear and old sites to explore. Hold a hex on a horde's road, and an ambush or a fort can stop it there."],  # tr
	["The hordes", "Each wave is told before it sets out, and its road is drawn in red. Scouts count it. Meet it on the road, behind your walls, or send help to whoever it comes for."],  # tr
	["Battle", "Battles go round by round. Numbers, stance, walls, the ground and help from neighbours decide them. Win, and the horde is gone; lose, and it raids or burns the village."],  # tr
]

## The art each page shows, its pieces side by side.
const ART := [
	["settlement/holy_city"],
	["building/elder_hall_1", "field/woodcutter_2", "field/farm_2"],
	["hero/dobrynya", "hero/vasilisa", "hero/ilya"],
	["building/elder_hall_3", "building/barracks_2", "building/wall_timber"],
	["map/outpost", "map/fort", "map/camp_bandit"],
	["faction/north", "faction/east", "faction/order"],
	["unit/spearman", "unit/archer", "unit/horseman"],
]

var _page := 0
var _body: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var sheet := UI.panel(1.0, 24)
	sheet.custom_minimum_size.x = minf(720.0, get_viewport_rect().size.x - 48.0)
	center.add_child(sheet)
	_body = UI.vbox(18)
	sheet.add_child(_body)
	_show()


func _show() -> void:
	UI.clear(_body)
	var page: Array = PAGES[_page]
	var top := UI.hbox(12)
	var count := UI.label(tr("%d / %d") % [_page + 1, PAGES.size()], UI.SMALL_SIZE, UI.MUTED)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(count)
	top.add_child(UI.button(tr("Skip"), _close))
	_body.add_child(top)
	# The picture: its pieces side by side, the first a little larger.
	var picture := UI.hbox(10)
	picture.alignment = BoxContainer.ALIGNMENT_CENTER
	var ids: Array = ART[_page]
	for i in ids.size():
		if Art.has(ids[i]):
			picture.add_child(UI.icon(ids[i], 200.0 if ids.size() == 1 else (150.0 if i == 0 else 120.0)))
	_body.add_child(picture)
	var title := UI.label(tr(page[0]), UI.HEADING_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(title)
	_body.add_child(UI.label(tr(page[1])))
	var turn := UI.hbox(12)
	var back := UI.button(tr("Back"), func() -> void: _turn(-1), "icon/back")
	back.disabled = _page == 0
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn.add_child(back)
	var last := _page == PAGES.size() - 1
	var next := UI.primary(tr("Begin") if last else tr("Next"), _close if last else func() -> void: _turn(1))
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn.add_child(next)
	_body.add_child(turn)


func _turn(by: int) -> void:
	_page = clampi(_page + by, 0, PAGES.size() - 1)
	_show()


func _close() -> void:
	closed.emit()
