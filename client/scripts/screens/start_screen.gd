extends Control
## The main menu (docs/art-style.md, "The main menu"): four doors, Play,
## Settings, Credits and Quit, each opening its own pages one step at a time.
## Play leads to Continue, solo worlds on this device (no sign-in or
## connection needed) and co-op worlds (sign in as a guest, create or join one
## and wait in its lobby until the host starts it). Every page has Back; the
## Android back key and Esc go one step up too.

const GAME_SCENE := "res://scenes/game.tscn"
const SPEEDS := [1, 2, 10]
const SPEED_LABELS := ["Normal (1×)", "Fast (2×)", "Test (10×)"]  # tr
const WORLD_STATUSES := ["Running", "Won", "Lost", "Abandoned"]  # tr
## Languages by their own names, never translated.
const LANGUAGES := [["en", "English"], ["sr_Latn", "Srpski"]]
## Text sizes: the setting and the letter size its button shows.
const TEXT_SIZES := [["small", 22], ["normal", 28], ["large", 36]]
const TEXT_SIZE_LABELS := ["Small", "Normal", "Large"]  # tr

## Each page's heading (the home page has none: the logo is its heading).
const PAGE_TITLES := {
	"play": "Play",
	"solo": "Play solo",
	"solo_new": "New solo world",
	"friends": "Play with friends",
	"friends_new": "New co-op world",
	"join": "Join with a code",
	"settings": "Settings",
	"language": "Language",
	"text_size": "Text size",
	"sound": "Sound",
	"account": "Account",
	"help": "Help and support",
	"credits": "Credits",
}  # tr

var _status: Label
var _content: VBoxContainer
var _layout: BoxContainer
var _hero: Control
var _logo: TextureRect
var _tagline: Label
var _frame: PanelContainer
## The page showing and the pages Back returns to.
var _page := "home"
var _trail: Array[String] = []
## The lobby on show and the world it belongs to.
var _lobby: Dictionary = {}
var _lobby_world_id := 0
## A solo world waiting for a second tap to be deleted.
var _delete_solo := 0
## Leaving a co-op world asks twice.
var _leave_armed := false
## Both the start request and the live "world started" push lead here.
var _entering := false


func _ready() -> void:
	# Full bleed, nothing wasted: the painting with the logo on one side (on
	# top on a phone), the sheet framed in plated wood on the other.
	var back := ColorRect.new()
	back.color = UiTheme.WOOD_DEEP
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_layout = BoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_theme_constant_override("separation", 0)
	add_child(_layout)
	_hero = _build_hero()
	_layout.add_child(_hero)

	_frame = PanelContainer.new()
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_frame)
	var sheet_box := UI.panel(1.0, 0)
	sheet_box.add_theme_stylebox_override("panel", UiTheme.sheet_style(24))
	_frame.add_child(sheet_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_box.add_child(scroll)
	var body := UI.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_status = UI.label("", UI.SMALL_SIZE, UI.ERROR)
	body.add_child(_status)
	_content = UI.vbox(20)
	body.add_child(_content)
	get_viewport().size_changed.connect(_arrange)
	_arrange()

	# The back key steps back through the menu instead of closing the app.
	get_tree().set_quit_on_go_back(false)
	Live.world_updated.connect(_on_live_world)
	Live.connection_changed.connect(_on_live_connection)
	if Session.is_logged_in():
		Push.register()
	Sound.music("map")
	_render("home")


## The painting, the logo in its sky and the tagline.
func _build_hero() -> Control:
	var hero := Control.new()
	hero.clip_contents = true
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio = 1.35
	var painting := TextureRect.new()
	painting.texture = Art.texture("ui/hero")
	painting.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	painting.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	painting.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero.add_child(painting)
	_logo = TextureRect.new()
	_logo.texture = Art.texture("brand/logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.add_child(_logo)
	_tagline = UI.label(tr("Defend the Holy City. Build the Kalinov Bridge."), UI.SMALL_SIZE + 6)
	_tagline.theme_type_variation = "OnWood"
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_tagline.add_theme_constant_override("outline_size", 8)
	hero.add_child(_tagline)
	hero.resized.connect(_place_logo)
	return hero


## Side by side on a wide screen, stacked on a tall one.
func _arrange() -> void:
	var area := get_viewport_rect().size
	var wide := area.x > area.y * 1.05
	_layout.vertical = not wide
	_hero.custom_minimum_size = Vector2.ZERO if wide else Vector2(0, area.y * 0.36)
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_FILL
	var frame := PlatedWood.new(18)
	# The gold rail runs where the wood meets the painting.
	if wide:
		frame.rails = [SIDE_LEFT]
		frame.plates = [CORNER_TOP_LEFT, CORNER_BOTTOM_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT]
	else:
		frame.rails = [SIDE_TOP]
		frame.plates = [CORNER_TOP_LEFT, CORNER_TOP_RIGHT]
	frame.content_margin_left = 26.0 if wide else 16.0
	frame.content_margin_top = 18.0 if wide else 24.0
	_frame.add_theme_stylebox_override("panel", frame)
	_place_logo.call_deferred()


## The logo in the painting's sky, as large as fits; the tagline under it.
func _place_logo() -> void:
	var box := _hero.size
	if _logo.texture == null or box.x <= 0.0:
		return
	var aspect := float(_logo.texture.get_width()) / float(_logo.texture.get_height())
	var height := minf(box.y * 0.5, box.x * 0.78 / aspect)
	var size := Vector2(height * aspect, height)
	_logo.position = Vector2((box.x - size.x) / 2.0, box.y * 0.05)
	_logo.size = size
	_tagline.position = Vector2(box.x * 0.05, _logo.position.y + size.y + 2.0)
	_tagline.size = Vector2(box.x * 0.9, 0)


func _exit_tree() -> void:
	get_tree().set_quit_on_go_back(true)
	Live.world_updated.disconnect(_on_live_world)
	Live.connection_changed.disconnect(_on_live_connection)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


# --- Navigation --------------------------------------------------------------

## One step further in: the page we leave is where Back returns to.
func _open(page: String) -> void:
	if page != _page:
		_trail.append(_page)
	_render(page)


## One step back; at home the back key does nothing (Quit closes the app).
func _back() -> void:
	if _trail.is_empty():
		if _page != "home":
			_render("home")
		return
	_render(_trail.pop_back())


## Draws a page: Back and its heading on top, then what it holds.
func _render(page: String) -> void:
	_page = page
	_set_status("")
	if page != "lobby" and _lobby_world_id != 0:
		_lobby_world_id = 0
		Live.stop()
	if page != "solo":
		_delete_solo = 0
	if page != "lobby":
		_leave_armed = false
	UI.clear(_content)
	if page != "home":
		var top := UI.hbox(14)
		var back := UI.button(tr("Back"), _back, "icon/back")
		back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		top.add_child(back)
		var heading := UI.label(_lobby.get("name", "") if page == "lobby" else tr(PAGE_TITLES.get(page, "")), UI.HEADING_SIZE)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(heading)
		_content.add_child(top)
	match page:
		"home": _home_page()
		"play": _play_page()
		"solo": _solo_page()
		"solo_new": _solo_form()
		"friends": _friends_page()
		"friends_new": _friends_form()
		"join": _join_page()
		"lobby": _lobby_page()
		"settings": _settings_page()
		"language": _language_page()
		"text_size": _text_size_page()
		"sound": _sound_page()
		"account": _account_page()
		"help": _help_page()
		"credits": _credits_page()


## A full-width door to the next step, with a line on where it leads.
func _door(text: String, about: String, page: String, icon_id := "", primary := false) -> void:
	var go := func() -> void: _open(page)
	var door := UI.primary(text, go, icon_id) if primary else UI.button(text, go, icon_id)
	door.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var group := UI.vbox(6)
	group.add_child(door)
	if about != "":
		group.add_child(UI.label(about, UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(group)


# --- Home --------------------------------------------------------------------

## Four doors: Play first and largest, Quit apart at the bottom.
func _home_page() -> void:
	var play := UI.primary(tr("Play"), func() -> void: _open("play"), "icon/play")
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.custom_minimum_size.y *= 1.35
	play.add_theme_font_size_override("font_size", UI.scaled(UI.HEADING_SIZE))
	_content.add_child(play)
	for entry in [["Settings", "settings", "icon/settings"], ["Credits", "credits", "icon/credits"]]:
		var page: String = entry[1]
		var door := UI.button(tr(entry[0]), func() -> void: _open(page), entry[2])
		door.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(door)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_content.add_child(gap)
	var quit := UI.button(tr("Quit"), func() -> void: get_tree().quit(), "icon/quit")
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(quit)
	var version := UI.label(tr("Version %s") % ProjectSettings.get_setting("application/config/version", ""), UI.SMALL_SIZE, UI.MUTED)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(version)


# --- Play --------------------------------------------------------------------

## Continue the world played last, or choose how to play.
func _play_page() -> void:
	_continue_button()
	_door(tr("Play solo"), tr("On this device, alone against the hordes. No connection needed."), "solo", "icon/village")
	_door(tr("Play with friends"), tr("Defend a world together, each from their own phone."), "friends", "icon/troops")


## The world played last, one tap away.
func _continue_button() -> void:
	var last: Dictionary = Session.last_world
	if last.is_empty():
		return
	var id := int(last.get("id", 0))
	var solo := id < 0
	if solo and not Local.server.worlds.has(id):
		return
	if not solo and not Session.is_logged_in():
		return
	var resume := UI.primary(tr("Continue: %s") % String(last.get("name", "")), func() -> void:
		if solo:
			_open_solo(id)
		else:
			_open_world(id), "icon/play")
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(resume)


## Solo worlds on this device: continue one or delete one, or start another.
## They need neither an account nor a connection (docs/local-engine.md).
func _solo_page() -> void:
	var worlds := Local.list_worlds()
	if worlds.is_empty():
		_content.add_child(UI.label(tr("No solo worlds yet. Start one; it plays on this device."), UI.SMALL_SIZE, UI.MUTED))
	for world in worlds:
		var row := UI.hbox()
		var id := int(world.id)
		var open := UI.button(world.name, func() -> void: _open_solo(id))
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(open)
		var about := UI.label("%s\n%s" % [tr(String(world.status).capitalize()), tr(GroupText.DIFFICULTY_LABELS[maxi(0, GroupText.DIFFICULTIES.find(world.difficulty))])], UI.SMALL_SIZE, UI.MUTED)
		about.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(about)
		var armed := _delete_solo == id
		row.add_child(UI.button(tr("Sure? Delete") if armed else tr("Delete"), func() -> void:
			if _delete_solo == id:
				Local.delete_world(id)
				_delete_solo = 0
			else:
				_delete_solo = id
			_render("solo")))
		_content.add_child(row)
	var new := UI.primary(tr("New solo world"), func() -> void: _open("solo_new")) if worlds.is_empty() else UI.button(tr("New solo world"), func() -> void: _open("solo_new"))
	new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(new)


func _solo_form() -> void:
	var data := LocalData.load_data()
	_content.add_child(UI.label(tr("World name"), UI.SMALL_SIZE, UI.MUTED))
	var world_name := UI.line_edit(tr("World name"), tr("A solo world"))
	_content.add_child(world_name)
	_content.add_child(UI.label(tr("Speed and difficulty"), UI.SMALL_SIZE, UI.MUTED))
	var row := UI.hbox()
	var speed := UI.options(SPEED_LABELS.map(tr), 0)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	var difficulty := UI.options(GroupText.DIFFICULTY_LABELS.map(tr), 1)
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(difficulty)
	_content.add_child(row)
	_content.add_child(UI.label(tr("Your hero"), UI.SMALL_SIZE, UI.MUTED))
	var kinds := HeroText.roster_ids(data)
	var hero := UI.options(kinds.map(func(kind: String) -> String: return HeroText.roster_title(data, kind)), 0)
	_content.add_child(hero)
	_content.add_child(UI.primary(tr("Start a solo world"), func() -> void:
		var who := String(Session.account.get("displayName", "")) if Session.is_logged_in() else ""
		_start_solo({"name": world_name.text.strip_edges() if world_name.text.strip_edges() != "" else tr("A solo world"),
			"displayName": who if who != "" else tr("You"), "speed": SPEEDS[speed.selected],
			"difficulty": GroupText.DIFFICULTIES[difficulty.selected], "heroKind": kinds[hero.selected] if not kinds.is_empty() else null}), "icon/play"))


func _start_solo(params: Dictionary) -> void:
	_set_status("")
	Live.stop()
	var view := Local.start(params)
	# The game's data comes from the app from here on, not the server.
	Local.world_id = int(view.id)
	_enter_game(view)


func _open_solo(id: int) -> void:
	_set_status("")
	Live.stop()
	var view := Local.open(id)
	if view.is_empty():
		_set_status(tr("That solo world is gone."))
		return
	Local.world_id = id
	_enter_game(view)


## Co-op: first a name to play as a guest, then the worlds you play with
## others, a new one and joining with a code.
func _friends_page() -> void:
	if not Session.is_logged_in():
		_guest_step(tr("Pick the name your group will see. You play as a guest; no email or password."))
		return
	var box := UI.vbox(14)
	_content.add_child(box)
	var waiting := UI.label(tr("Loading…"), UI.SMALL_SIZE, UI.MUTED)
	box.add_child(waiting)
	var response := await Api.get_json("/v1/me")
	if not is_instance_valid(box) or _page != "friends":
		return
	waiting.queue_free()
	if response.status == 401:
		Session.log_out()
		_render("friends")
		return
	if not response.ok:
		box.add_child(UI.label(tr("The server can't be reached. Solo worlds play on all the same."), UI.SMALL_SIZE, UI.MUTED))
		box.add_child(UI.button(tr("Retry"), func() -> void: _render("friends")))
		return
	Session.account = response.data.account
	Session.save()
	box.add_child(UI.label(tr("Your worlds"), UI.SMALL_SIZE, UI.MUTED))
	if response.data.worlds.is_empty():
		box.add_child(UI.label(tr("None yet. Create one or join with a code."), UI.SMALL_SIZE, UI.MUTED))
	for world in response.data.worlds:
		var row := UI.hbox()
		var world_id := int(world.id)
		var open := UI.button(world.name, func() -> void: _open_world(world_id))
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(open)
		var state := UI.label(tr("In the lobby") if world.status == "lobby" else tr(String(world.status).capitalize()), UI.SMALL_SIZE, UI.MUTED)
		state.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(state)
		box.add_child(row)
	var none: bool = response.data.worlds.is_empty()
	var create := UI.primary(tr("Create a world"), func() -> void: _open("friends_new")) if none else UI.button(tr("Create a world"), func() -> void: _open("friends_new"))
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(create)
	var join := UI.button(tr("Join with a code"), func() -> void: _open("join"))
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(join)


## Signing in as a guest, then on to the page that asked for it.
func _guest_step(why: String) -> void:
	_content.add_child(UI.label(why, UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(tr("Your name"), UI.SMALL_SIZE, UI.MUTED))
	var name_edit := UI.line_edit(tr("e.g. Vesna"))
	_content.add_child(name_edit)
	_content.add_child(UI.primary(tr("Play as guest"), func() -> void: _login(name_edit.text)))


func _friends_form() -> void:
	_content.add_child(UI.label(tr("World name"), UI.SMALL_SIZE, UI.MUTED))
	var world_name := UI.line_edit(tr("World name"), tr("%s's world") % Session.account.get("displayName", ""))
	_content.add_child(world_name)
	_content.add_child(UI.label(tr("Players and speed"), UI.SMALL_SIZE, UI.MUTED))
	var row := UI.hbox()
	var players := UI.options(range(1, 7).map(func(n: int) -> String: return tr_n("%d player", "%d players", n) % n), 1)
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(players)
	var speed := UI.options(SPEED_LABELS.map(tr), 0)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	_content.add_child(row)
	_content.add_child(UI.label(tr("Difficulty"), UI.SMALL_SIZE, UI.MUTED))
	var difficulty := UI.options(GroupText.DIFFICULTY_LABELS.map(tr), 1)
	_content.add_child(difficulty)
	_content.add_child(UI.primary(tr("Create world"), func() -> void:
		_create_world(world_name.text, players.selected + 1, SPEEDS[speed.selected], GroupText.DIFFICULTIES[difficulty.selected])))


func _join_page() -> void:
	_content.add_child(UI.label(tr("Ask the host for the six-character code shown in their lobby."), UI.SMALL_SIZE, UI.MUTED))
	var code := UI.line_edit(tr("Invite code"))
	_content.add_child(code)
	_content.add_child(UI.primary(tr("Join"), func() -> void: _join_world(code.text)))


func _login(display_name: String) -> void:
	_set_status("")
	var body := {}
	if display_name.strip_edges() != "":
		body.displayName = display_name.strip_edges()
	var response := await Api.post_json("/v1/auth/guest", body)
	if not response.ok:
		_set_status(response.error)
		return
	Session.token = response.data.token
	Session.account = response.data.account
	Session.save()
	Session.report_language()
	Push.register()
	_render(_page)


func _create_world(world_name: String, max_players: int, speed: int, difficulty := "normal") -> void:
	var response := await Api.post_json("/v1/worlds", {"name": world_name, "maxPlayers": max_players, "speed": speed, "difficulty": difficulty})
	_handle_world_response(response)


func _join_world(code: String) -> void:
	var response := await Api.post_json("/v1/worlds/join", {"inviteCode": code})
	_handle_world_response(response)


func _open_world(world_id: int) -> void:
	var response := await Api.get_json("/v1/worlds/%d" % world_id)
	_handle_world_response(response)


func _handle_world_response(response: Api.Response) -> void:
	if not response.ok:
		_set_status(response.error)
		return
	_set_status("")
	if response.data.status == "lobby":
		_show_lobby(response.data)
	else:
		_enter_game(response.data)


# --- Settings ----------------------------------------------------------------

## Asks the server who is signed in (a sign-in from before the app kept the
## account has a token but no name), then draws `page` again if it changed.
func _refresh_account(page: String) -> void:
	if not Session.is_logged_in():
		return
	var response := await Api.get_json("/v1/me")
	if _page != page:
		return
	if response.status == 401:
		Session.log_out()
		_render(page)
		return
	if not response.ok or response.data.account == Session.account:
		return
	Session.account = response.data.account
	Session.save()
	_render(page)


## One door per setting, each showing what it is set to now.
func _settings_page() -> void:
	_refresh_account("settings")
	var language := ""
	for entry in LANGUAGES:
		if entry[0] == Session.language:
			language = entry[1]
	var size := ""
	for i in TEXT_SIZES.size():
		if TEXT_SIZES[i][0] == Session.text_size:
			size = tr(TEXT_SIZE_LABELS[i])
	_door(tr("Language: %s") % language, "", "language", "icon/research")
	_door(tr("Text size: %s") % size, "", "text_size", "icon/settings")
	_door(tr("Sound"), tr("Music %d%%, effects %d%%") % [roundi(Session.music_volume * 100.0), roundi(Session.effects_volume * 100.0)], "sound", "icon/inbox")
	var who := String(Session.account.get("displayName", ""))
	var account := tr("Not signed in")
	if Session.is_logged_in():
		account = tr("Signed in as %s") % who if who != "" else tr("Signed in")
	_door(tr("Account"), account, "account", "icon/profile")
	_door(tr("Help and support"), tr("How a run goes, reporting a problem, the server costs and privacy."), "help", "icon/help")


## The language, by its own name.
func _language_page() -> void:
	for language in LANGUAGES:
		var code: String = language[0]
		var pick := UI.button(language[1], func() -> void:
			Session.set_language(code)
			get_tree().reload_current_scene())
		pick.theme_type_variation = "TabButton"
		pick.disabled = Session.language == code
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(pick)


## Text size for accessibility: the same letter at three sizes.
func _text_size_page() -> void:
	_content.add_child(UI.label(tr("Applies everywhere in the game."), UI.SMALL_SIZE, UI.MUTED))
	var sizes := UI.hbox(8)
	for i in TEXT_SIZES.size():
		var entry: Array = TEXT_SIZES[i]
		var size_code: String = entry[0]
		var size_pick := UI.button("A", func() -> void:
			Session.set_text_size(size_code)
			get_tree().reload_current_scene())
		size_pick.theme_type_variation = "TabButton"
		size_pick.add_theme_font_size_override("font_size", int(entry[1]))
		size_pick.tooltip_text = tr("Text size: %s") % tr(TEXT_SIZE_LABELS[i])
		size_pick.disabled = Session.text_size == size_code
		size_pick.custom_minimum_size = Vector2(76, 76)
		sizes.add_child(size_pick)
	_content.add_child(sizes)


func _sound_page() -> void:
	_volume_slider(tr("Music"), "Music", Session.music_volume)
	_volume_slider(tr("Sound effects"), "Effects", Session.effects_volume)


## A volume from 0 to 100%, kept on the device; effects tap as you slide.
func _volume_slider(text: String, bus: String, volume: float) -> void:
	var title := UI.label("", UI.SMALL_SIZE, UI.MUTED)
	_content.add_child(title)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume
	slider.custom_minimum_size.y = 48
	var show := func(value: float) -> void: title.text = tr("%s: %d%%") % [text, roundi(value * 100.0)]
	show.call(volume)
	slider.value_changed.connect(func(value: float) -> void:
		show.call(value)
		Sound.set_volume(bus, value)
		if bus == "Music":
			Session.music_volume = value
		else:
			Session.effects_volume = value
			Sound.effect("tap"))
	slider.drag_ended.connect(func(_changed: bool) -> void: Session.save())
	_content.add_child(slider)


# --- Account -----------------------------------------------------------------

## The privacy policy, in short (docs/privacy.md has the long version).
const PRIVACY := "Slavian keeps as little as it can: the name you choose (or a guest name), your sign-in sessions, and the state of the worlds you play in. There is no advertising, no tracking and no sharing with third parties. Push notifications use your device token only to reach you. You can download what is kept about you and delete your account at any time from this screen. Deletion removes the account, its sessions, memberships and device tokens."  # tr

var _delete_armed := false


## Who you are and your data; deleting the account stands apart.
func _account_page() -> void:
	_delete_armed = false
	if not Session.is_logged_in():
		_guest_step(tr("Solo worlds need no account. To play with friends, pick a name and play as a guest."))
		return
	_refresh_account("account")
	var who := String(Session.account.get("displayName", ""))
	_content.add_child(UI.label(tr("Signed in as"), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(who if who != "" else tr("Loading…"), UI.HEADING_SIZE))
	var rename := UI.hbox()
	var name_edit := UI.line_edit(tr("Your name"), who)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename.add_child(name_edit)
	rename.add_child(UI.button(tr("Rename"), func() -> void: _rename(name_edit.text)))
	_content.add_child(rename)
	_content.add_child(UI.button(tr("Sign out"), func() -> void:
		Session.log_out()
		_render("account")))
	_content.add_child(UI.label(tr("Your data"), UI.HEADING_SIZE))
	_content.add_child(UI.button(tr("Export my data"), _export_data))
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	_content.add_child(gap)
	_content.add_child(UI.button(tr("Delete my account"), _confirm_delete))


func _rename(display_name: String) -> void:
	_set_status("")
	var response := await Api.request(HTTPClient.METHOD_PATCH, "/v1/me", {"displayName": display_name.strip_edges()})
	if not response.ok:
		_set_status(response.error)
		return
	Session.account = response.data.get("account", Session.account)
	Session.save()
	_render("account")


func _export_data() -> void:
	var response := await Api.get_json("/v1/me/export")
	if not response.ok:
		_set_status(response.error)
		return
	var path := "user://export_%d.json" % int(Time.get_unix_time_from_system())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status(tr("Could not write the export file."))
		return
	file.store_string(JSON.stringify(response.data, "\t"))
	file.close()
	_set_status(tr("Your data is saved to %s") % ProjectSettings.globalize_path(path))


func _confirm_delete() -> void:
	if not _delete_armed:
		_delete_armed = true
		_set_status(tr("Tap again to delete your account and all its data."))
		return
	_delete_armed = false
	var response := await Api.request(HTTPClient.METHOD_DELETE, "/v1/me")
	if not response.ok:
		_set_status(response.error)
		return
	Session.log_out()
	_render("account")


# --- Help --------------------------------------------------------------------

## How a run goes, reporting a problem, supporting the game and privacy.
func _help_page() -> void:
	var data := LocalData.load_data()
	_content.add_child(UI.label(tr("How a run goes"), UI.HEADING_SIZE))
	for entry in AlmanacText.entries(data, "The run"):
		_content.add_child(UI.label(entry[0]))
		_content.add_child(UI.label(entry[1], UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(tr("In a world, the quest card shows the way, and the almanac explains the rest."), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(tr("Report a problem"), UI.HEADING_SIZE))
	if Session.is_logged_in():
		var message := TextEdit.new()
		message.placeholder_text = tr("What went wrong?")
		message.custom_minimum_size.y = 140
		_content.add_child(message)
		_content.add_child(UI.button(tr("Send"), func() -> void: _send_report(message.text)))
	else:
		_content.add_child(UI.label(tr("Sign in as a guest (Settings, Account) to send a report."), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(tr("Support and privacy"), UI.HEADING_SIZE))
	var costs_box := UI.vbox(10)
	_content.add_child(costs_box)
	_content.add_child(UI.label(tr("Privacy policy"), UI.SMALL_SIZE))
	_content.add_child(UI.label(tr(PRIVACY), UI.SMALL_SIZE, UI.MUTED))
	var costs := await Api.get_json("/v1/costs")
	if not is_instance_valid(costs_box) or _page != "help":
		return
	if not costs.ok or not costs.data is Dictionary:
		costs_box.add_child(UI.label(tr("Could not load the server costs."), UI.SMALL_SIZE, UI.MUTED))
		return
	var c: Dictionary = costs.data
	var currency := str(c.get("currency", "EUR"))
	var spent := float(c.get("costs", 0.0))
	var raised := float(c.get("donations", 0.0)) + float(c.get("carryIn", 0.0))
	costs_box.add_child(UI.label(tr("This month (%s): server costs %s, donations %s.") % [
		str(c.get("month", "")), "%s %.2f" % [currency, spent], "%s %.2f" % [currency, raised]], UI.SMALL_SIZE, UI.MUTED))
	var bar := ProgressBar.new()
	bar.max_value = maxf(spent, 0.01)
	bar.value = minf(raised, spent)
	bar.custom_minimum_size.y = 28
	bar.show_percentage = false
	costs_box.add_child(bar)
	costs_box.add_child(UI.label(tr("Carried to next month: %s") % ("%s %.2f" % [currency, raised - spent]), UI.SMALL_SIZE, UI.MUTED))
	var url := str(c.get("donationUrl", ""))
	if url != "":
		costs_box.add_child(UI.primary(tr("Buy me a coffee"), func() -> void: OS.shell_open(url)))


func _send_report(message: String) -> void:
	if message.strip_edges() == "":
		return
	var response := await Api.post_json("/v1/reports", {"message": message.strip_edges(), "worldId": null, "state": {"screen": "start"}})
	_set_status(tr("Thank you; the report is sent.") if response.ok else response.error)


# --- Credits -----------------------------------------------------------------

## The music and sounds, all CC0 (client/audio/CREDITS.md): what, and by
## whom (names stay as they are).
const CREDITS := [
	"Music for the map and the menu, the village, battles, victory and defeat",  # tr
	"Music when a horde is near",  # tr
	"The war horn",  # tr
	"Sound effects",  # tr
]
const CREDITED := ["RandomMind (opengameart.org)", "spring-spring (opengameart.org)", "stumpystrust (opengameart.org)", "Kenney (kenney.nl)"]


func _credits_page() -> void:
	_content.add_child(UI.label("Slavian", UI.TITLE_SIZE))
	_content.add_child(UI.label(tr("Version %s") % ProjectSettings.get_setting("application/config/version", ""), UI.SMALL_SIZE, UI.MUTED))
	# The studio: its mark pressed into red wax (tools/art/seal.py), then its name.
	var studio := Art.texture("brand/seal")
	if studio != null:
		var mark := TextureRect.new()
		mark.texture = studio
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(0, 240)
		_content.add_child(mark)
	_content.add_child(UI.label(tr("Made by"), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label("Night Forge"))
	_content.add_child(UI.label(tr("Music and sound"), UI.HEADING_SIZE))
	for i in CREDITS.size():
		_content.add_child(UI.label(tr(CREDITS[i]), UI.SMALL_SIZE, UI.MUTED))
		_content.add_child(UI.label(CREDITED[i]))
	_content.add_child(UI.label(tr("All under CC0, given freely. Thank you."), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(tr("Built with"), UI.HEADING_SIZE))
	_content.add_child(UI.label("Godot Engine (godotengine.org)"))


# --- Lobby -------------------------------------------------------------------

func _show_lobby(world: Dictionary) -> void:
	_lobby = world
	if _page == "lobby":
		_render("lobby")
	else:
		_open("lobby")


func _lobby_page() -> void:
	var world := _lobby
	if _lobby_world_id != int(world.id):
		_lobby_world_id = int(world.id)
		Live.watch(_lobby_world_id)
	_content.add_child(UI.label(tr("Invite code"), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(world.inviteCode, UI.TITLE_SIZE))
	_content.add_child(UI.label(tr("Share it with your group. %d of %d players joined.") % [world.members.size(), world.maxPlayers], UI.SMALL_SIZE, UI.MUTED))
	for member in world.members:
		var host := tr(" (host)") if int(member.accountId) == int(world.hostAccountId) else ""
		var clan := " · %s" % ClanText.title(Game.data, member.get("clan")) if not Game.data.is_empty() else ""
		var hero := " · %s" % tr(HeroText.roster(Game.data, member.get("heroKind")).get("name", "")) if member.get("heroKind") != null and not Game.data.is_empty() else ""
		_content.add_child(UI.label("• %s%s%s%s" % [member.displayName, host, clan, hero]))
	if int(world.hostAccountId) == int(Session.account.id):
		_content.add_child(UI.primary(tr("Start the world"), func() -> void: _start_world(int(world.id)), "icon/play"))
	else:
		_content.add_child(UI.label(tr("Waiting for the host to start…"), UI.SMALL_SIZE, UI.MUTED))
	_clan_picker(world)
	_hero_picker(world)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	_content.add_child(gap)
	_content.add_child(UI.button(tr("Sure? Leave this world") if _leave_armed else tr("Leave this world"), func() -> void: _leave_lobby(int(world.id)), "icon/quit"))


## Leaving the lobby asks twice; if you hosted it, the next player hosts it.
func _leave_lobby(world_id: int) -> void:
	if not _leave_armed:
		_leave_armed = true
		_render("lobby")
		_set_status(tr("Tap again to leave. If you host it, the next player in the lobby will."))
		return
	var response := await Api.post_json("/v1/worlds/%d/leave" % world_id)
	if not response.ok:
		_set_status(response.error)
		return
	if int(Session.last_world.get("id", 0)) == world_id:
		Session.last_world = {}
		Session.save()
	_back()


## Each member picks their clan in the lobby (and may change it until the start).
func _clan_picker(world: Dictionary) -> void:
	if Game.data.is_empty():
		var error := await Game.ensure_data()
		if error == "" and _lobby_world_id == int(world.id):
			_render("lobby")
		return
	var mine: Variant = null
	for member in world.members:
		if int(member.accountId) == int(Session.account.id):
			mine = member.get("clan")
	_content.add_child(UI.label(tr("Your clan: %s") % ClanText.title(Game.data, mine), UI.HEADING_SIZE))
	for clan in ClanText.ids(Game.data):
		var def: Dictionary = Game.data.clans.clans[clan]
		var pick := UI.button(("✓ " if clan == mine else "") + ClanText.title(Game.data, clan), func() -> void: _pick_clan(int(world.id), clan))
		_content.add_child(pick)
		_content.add_child(UI.label(tr(def.story), UI.SMALL_SIZE, UI.MUTED))
		_content.add_child(UI.label(ClanText.perks(Game.data, clan), UI.SMALL_SIZE, UI.MUTED))


## Each member picks a hero from the roster, one nobody else in the group
## has (and may change it until the start).
func _hero_picker(world: Dictionary) -> void:
	if Game.data.is_empty():
		return
	var mine: Variant = null
	var taken := {}
	for member in world.members:
		if int(member.accountId) == int(Session.account.id):
			mine = member.get("heroKind")
		elif member.get("heroKind") != null:
			taken[String(member.heroKind)] = String(member.displayName)
	_content.add_child(UI.label(tr("Your hero: %s") % HeroText.roster_title(Game.data, mine), UI.HEADING_SIZE))
	_content.add_child(UI.label(tr("Their strengths and traits reach all your villages; the hero leads the garrison where it stands."), UI.SMALL_SIZE, UI.MUTED))
	for kind in HeroText.roster_ids(Game.data):
		var def := HeroText.roster(Game.data, kind)
		var card := UI.hbox(14)
		var face := HeroText.portrait(kind, 104.0)
		face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.add_child(face)
		var text := UI.vbox(4)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(UI.label(HeroText.roster_title(Game.data, kind), 0, UI.ACCENT if kind == mine else Color.WHITE))
		text.add_child(UI.label(tr(def.story), UI.SMALL_SIZE, UI.MUTED))
		text.add_child(UI.label(HeroText.effects(def.effects), UI.SMALL_SIZE))
		for line in HeroText.roster_traits(Game.data, kind):
			text.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
		if taken.has(kind):
			text.add_child(UI.label(tr("Rides with %s") % taken[kind], UI.SMALL_SIZE, UI.MUTED))
		elif kind != mine:
			var pick := UI.button(tr("Pick %s") % tr(def.name), func() -> void: _pick_hero(int(world.id), kind))
			pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			text.add_child(pick)
		else:
			text.add_child(UI.label(tr("✓ Your hero"), UI.SMALL_SIZE, UI.ACCENT))
		card.add_child(text)
		_content.add_child(card)


func _pick_hero(world_id: int, kind: String) -> void:
	_set_status("")
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/hero" % world_id, {"kind": kind})
	if not response.ok:
		_set_status(response.error)
		return
	_show_lobby(response.data)


func _pick_clan(world_id: int, clan: String) -> void:
	_set_status("")
	var response := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/clan" % world_id, {"clan": clan})
	if not response.ok:
		_set_status(response.error)
		return
	_show_lobby(response.data)


func _start_world(world_id: int) -> void:
	var response := await Api.post_json("/v1/worlds/%d/start" % world_id)
	_handle_world_response(response)


func _on_live_world(world: Dictionary) -> void:
	if int(world.id) != _lobby_world_id:
		return
	if world.status == "lobby":
		_show_lobby(world)
	else:
		_enter_game(world)


func _on_live_connection(connected: bool) -> void:
	# Catch up on anything missed while disconnected.
	if connected and _lobby_world_id != 0:
		_open_world(_lobby_world_id)


func _enter_game(world: Dictionary) -> void:
	if _entering:
		return
	_entering = true
	_lobby_world_id = 0
	var error := await Game.ensure_data()
	if error != "":
		_entering = false
		_set_status(error)
		return
	Game.set_world(world)
	Session.last_world = {"id": int(world.id), "name": String(world.get("name", ""))}
	Session.save()
	get_tree().change_scene_to_file(GAME_SCENE)
