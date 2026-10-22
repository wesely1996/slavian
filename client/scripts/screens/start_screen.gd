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
## World lists show this many at a time, and turn pages for the rest.
const WORLDS_PER_PAGE := 4

const PAGE_TITLES := {
	"play": "Play",
	"solo": "Play solo",
	"solo_new": "New solo world",
	"friends": "Play with friends",
	"friends_new": "New co-op world",
	"join": "Join with a code",
	"pick_hero": "Choose your hero",
	"pick_clan": "Choose your clan",
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
## The world being made or joined: its fields as typed, and the hero and clan
## chosen for it (kept while the pickers are open).
var _form := {}
var _choice := {"hero": null, "clan": null}
## Where a picker's choice goes: "form" (a new world, joining) or "lobby".
var _pick_for := "form"
## The hero or clan shown in a picker before it is chosen.
var _pick_preview: Variant = null
## The side tab open on Help and Credits, and the page of each world list.
var _side := {"help": "run", "credits": "studio"}
var _list_page := {"solo": 0, "friends": 0}


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
	# On a phone the painting gives the sheet room past the first page.
	_hero.custom_minimum_size = Vector2.ZERO if wide else Vector2(0, area.y * (0.36 if _page == "home" else 0.2))
	_tagline.visible = wide or _page == "home"
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
	# A form opened afresh starts empty (coming back from a picker, it doesn't).
	if page in ["solo_new", "friends_new", "join"]:
		_form = {}
		_choice = {"hero": null, "clan": null}
		_pick_for = "form"
	if page in ["pick_hero", "pick_clan"]:
		_pick_preview = _choice.hero if page == "pick_hero" else _choice.clan
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
	var was_home := _page == "home"
	_page = page
	if was_home != (page == "home"):
		_arrange()
	_set_status("")
	# The lobby stays live while its hero and clan pickers are open.
	var in_lobby := page == "lobby" or (_pick_for == "lobby" and page in ["pick_hero", "pick_clan"])
	if not in_lobby and _lobby_world_id != 0:
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
		"pick_hero": _hero_pick_page()
		"pick_clan": _clan_pick_page()
		"lobby": _lobby_page()
		"settings": _settings_page()
		"language": _language_page()
		"text_size": _text_size_page()
		"sound": _sound_page()
		"account": _account_page()
		"help": _help_page()
		"credits": _credits_page()


## A full-width door to the next step; where it leads is behind its info
## mark (UI.info) rather than written under it.
func _door(text: String, about: String, page: String, icon_id := "", primary := false) -> void:
	var go := func() -> void: _open(page)
	var door := UI.primary(text, go, icon_id) if primary else UI.button(text, go, icon_id)
	door.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content.add_child(UI.with_info(door, about) if about != "" else door)


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
	var paged := UI.paged(worlds, _list_page.solo, WORLDS_PER_PAGE, func(page: int) -> void:
		_list_page.solo = page
		_render("solo"))
	for world in paged[0]:
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
	_content.add_child(paged[1])
	var new := UI.primary(tr("New solo world"), func() -> void: _open("solo_new")) if worlds.is_empty() else UI.button(tr("New solo world"), func() -> void: _open("solo_new"))
	new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(new)


func _solo_form() -> void:
	var world_name := _form_edit("name", tr("World name"), tr("A solo world"))
	_content.add_child(UI.label(tr("Speed and difficulty"), UI.SMALL_SIZE, UI.MUTED))
	var row := UI.hbox()
	row.add_child(_form_options("speed", SPEED_LABELS.map(tr), 0))
	row.add_child(_form_options("difficulty", GroupText.DIFFICULTY_LABELS.map(tr), 1))
	_content.add_child(row)
	_choice_buttons(LocalData.load_data())
	var start := UI.primary(tr("Start a solo world"), func() -> void:
		var who := String(Session.account.get("displayName", "")) if Session.is_logged_in() else ""
		_start_solo({"name": world_name.text.strip_edges() if world_name.text.strip_edges() != "" else tr("A solo world"),
			"displayName": who if who != "" else tr("You"), "speed": SPEEDS[int(_form.get("speed", 0))],
			"difficulty": GroupText.DIFFICULTIES[int(_form.get("difficulty", 1))], "heroKind": _choice.hero, "clan": _choice.clan}), "icon/play")
	_needs_choices(start)
	_content.add_child(start)


## A text field of the form, keeping what is typed in `_form[key]`.
func _form_edit(key: String, label: String, placeholder: String) -> LineEdit:
	_content.add_child(UI.label(label, UI.SMALL_SIZE, UI.MUTED))
	var edit := UI.line_edit(placeholder, String(_form.get(key, "")))
	edit.text_changed.connect(func(text: String) -> void: _form[key] = text)
	_content.add_child(edit)
	return edit


## A drop-down of the form, keeping the pick in `_form[key]`.
func _form_options(key: String, items: Array, default: int) -> OptionButton:
	var pick := UI.options(items, int(_form.get(key, default)))
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.item_selected.connect(func(i: int) -> void: _form[key] = i)
	return pick


## A world starts with a hero and a clan: until both are chosen, its button
## waits and says so.
func _needs_choices(button: Button) -> void:
	if _choice.hero != null and _choice.clan != null:
		return
	button.disabled = true
	button.text = tr("Choose a hero and a clan first")


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
	var paged := UI.paged(response.data.worlds, _list_page.friends, WORLDS_PER_PAGE, func(page: int) -> void:
		_list_page.friends = page
		_render("friends"))
	for world in paged[0]:
		var row := UI.hbox()
		var world_id := int(world.id)
		var open := UI.button(world.name, func() -> void: _open_world(world_id))
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(open)
		var state := UI.label(tr("In the lobby") if world.status == "lobby" else tr(String(world.status).capitalize()), UI.SMALL_SIZE, UI.MUTED)
		state.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(state)
		box.add_child(row)
	box.add_child(paged[1])
	var none: bool = response.data.worlds.is_empty()
	var create := UI.primary(tr("Create a world"), func() -> void: _open("friends_new")) if none else UI.button(tr("Create a world"), func() -> void: _open("friends_new"))
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(create)
	var join := UI.button(tr("Join with a code"), func() -> void: _open("join"))
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(join)


## Signing in as a guest, then on to the page that asked for it.
func _guest_step(why: String) -> void:
	_content.add_child(UI.with_info(UI.label(tr("Your name"), UI.SMALL_SIZE, UI.MUTED), why))
	var name_edit := UI.line_edit(tr("e.g. Vesna"))
	_content.add_child(name_edit)
	_content.add_child(UI.primary(tr("Play as guest"), func() -> void: _login(name_edit.text)))


func _friends_form() -> void:
	var world_name := _form_edit("name", tr("World name"), tr("%s's world") % Session.account.get("displayName", ""))
	_content.add_child(UI.label(tr("Players, speed and difficulty"), UI.SMALL_SIZE, UI.MUTED))
	var row := UI.hbox()
	row.add_child(_form_options("players", range(1, 7).map(func(n: int) -> String: return tr_n("%d player", "%d players", n) % n), 1))
	row.add_child(_form_options("speed", SPEED_LABELS.map(tr), 0))
	row.add_child(_form_options("difficulty", GroupText.DIFFICULTY_LABELS.map(tr), 1))
	_content.add_child(row)
	if not await _choices_with_data():
		return
	var create := UI.primary(tr("Create world"), func() -> void:
		var typed := world_name.text.strip_edges()
		_create_world(typed if typed != "" else world_name.placeholder_text, int(_form.get("players", 1)) + 1, SPEEDS[int(_form.get("speed", 0))], GroupText.DIFFICULTIES[int(_form.get("difficulty", 1))]))
	_needs_choices(create)
	_content.add_child(create)


func _join_page() -> void:
	var code := _form_edit("code", tr("Invite code"), tr("Ask the host for the six-character code"))
	if not await _choices_with_data():
		return
	var join := UI.primary(tr("Join"), func() -> void: _join_world(code.text))
	_needs_choices(join)
	_content.add_child(join)


## The hero and clan buttons once the game's data is here (co-op worlds
## take it from the server); false if it could not be loaded.
func _choices_with_data() -> bool:
	var page := _page
	if Game.data.is_empty():
		var error := await Game.ensure_data()
		if _page != page:
			return false
		if error != "":
			_set_status(error)
			return false
	_choice_buttons(Game.data)
	return true


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
	_handle_world_response(await _with_choices(response))


func _join_world(code: String) -> void:
	var response := await Api.post_json("/v1/worlds/join", {"inviteCode": code})
	_handle_world_response(await _with_choices(response))


## Sets the hero and clan chosen in the form on the world just made or joined;
## the answer is the lobby after them. A hero someone else took is left for
## the lobby, where the player picks another.
func _with_choices(response: Api.Response) -> Api.Response:
	if not response.ok or response.data.status != "lobby":
		return response
	var world_id := int(response.data.id)
	for pick in [["clan", "clan", _choice.clan], ["hero", "kind", _choice.hero]]:
		if pick[2] == null:
			continue
		var answer := await Api.request(HTTPClient.METHOD_PUT, "/v1/worlds/%d/%s" % [world_id, pick[0]], {pick[1]: pick[2]})
		if answer.ok:
			response = answer
		else:
			_set_status(answer.error)
	return response


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
	_door(tr("Sound: music %d%%, effects %d%%") % [roundi(Session.music_volume * 100.0), roundi(Session.effects_volume * 100.0)], "", "sound", "icon/inbox")
	# Who is signed in, on the door itself.
	var who := String(Session.account.get("displayName", ""))
	var account := tr("Account: not signed in")
	if Session.is_logged_in():
		account = tr("Account: %s") % who if who != "" else tr("Account: signed in")
	_door(account, "", "account", "icon/profile")
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

## How a run goes, reporting a problem, the server costs and privacy: one
## side tab each.
func _help_page() -> void:
	var tabs := [["run", "icon/research", tr("How a run goes")], ["report", "icon/inbox", tr("Report a problem")],
		["support", "icon/coin", tr("Support the game")], ["privacy", "icon/lock", tr("Privacy policy")]]
	var layout := UI.side_layout(tabs, _side.help, func(key: String) -> void:
		_side.help = key
		_render("help"))
	_content.add_child(layout[0])
	var box: VBoxContainer = layout[1]
	for tab in tabs:
		if tab[0] == _side.help:
			box.add_child(UI.label(tab[2], UI.HEADING_SIZE))
	match _side.help:
		"run":
			for entry in AlmanacText.entries(LocalData.load_data(), "The run"):
				box.add_child(UI.with_info(UI.label(entry[0]), entry[1]))
			box.add_child(UI.label(tr("In a world, the quest card shows the way, and the almanac explains the rest."), UI.SMALL_SIZE, UI.MUTED))
		"report":
			if not Session.is_logged_in():
				box.add_child(UI.label(tr("Sign in as a guest (Settings, Account) to send a report."), UI.SMALL_SIZE, UI.MUTED))
				return
			var message := TextEdit.new()
			message.placeholder_text = tr("What went wrong?")
			message.custom_minimum_size.y = 220
			message.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			box.add_child(message)
			box.add_child(UI.primary(tr("Send"), func() -> void: _send_report(message.text)))
		"support":
			await _costs(box)
		"privacy":
			box.add_child(UI.label(tr(PRIVACY), UI.SMALL_SIZE))


## This month's server costs and donations, and where to give.
func _costs(box: VBoxContainer) -> void:
	var costs := await Api.get_json("/v1/costs")
	if not is_instance_valid(box) or _page != "help":
		return
	if not costs.ok or not costs.data is Dictionary:
		box.add_child(UI.label(tr("Could not load the server costs."), UI.SMALL_SIZE, UI.MUTED))
		return
	var c: Dictionary = costs.data
	var currency := str(c.get("currency", "EUR"))
	var spent := float(c.get("costs", 0.0))
	var raised := float(c.get("donations", 0.0)) + float(c.get("carryIn", 0.0))
	box.add_child(UI.label(tr("This month (%s): server costs %s, donations %s.") % [
		str(c.get("month", "")), "%s %.2f" % [currency, spent], "%s %.2f" % [currency, raised]], UI.SMALL_SIZE))
	var bar := ProgressBar.new()
	bar.max_value = maxf(spent, 0.01)
	bar.value = minf(raised, spent)
	bar.custom_minimum_size.y = 28
	bar.show_percentage = false
	box.add_child(bar)
	box.add_child(UI.label(tr("Carried to next month: %s") % ("%s %.2f" % [currency, raised - spent]), UI.SMALL_SIZE, UI.MUTED))
	var url := str(c.get("donationUrl", ""))
	if url != "":
		box.add_child(UI.primary(tr("Buy me a coffee"), func() -> void: OS.shell_open(url)))


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


## The studio, the music and sound, and the engine: one side tab each.
func _credits_page() -> void:
	var tabs := [["studio", "brand/seal", "Night Forge"], ["music", "icon/music", tr("Music and sound")], ["engine", "icon/build", tr("Built with")]]
	var layout := UI.side_layout(tabs, _side.credits, func(key: String) -> void:
		_side.credits = key
		_render("credits"))
	_content.add_child(layout[0])
	var box: VBoxContainer = layout[1]
	match _side.credits:
		"studio":
			box.add_child(UI.label("Slavian", UI.TITLE_SIZE))
			box.add_child(UI.label(tr("Version %s") % ProjectSettings.get_setting("application/config/version", ""), UI.SMALL_SIZE, UI.MUTED))
			# The studio: its mark pressed into red wax (tools/art/seal.py), then its name.
			var studio := Art.texture("brand/seal")
			if studio != null:
				var mark := TextureRect.new()
				mark.texture = studio
				mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				mark.custom_minimum_size = Vector2(0, 220)
				box.add_child(mark)
			box.add_child(UI.label(tr("Made by"), UI.SMALL_SIZE, UI.MUTED))
			box.add_child(UI.label("Night Forge"))
		"music":
			box.add_child(UI.label(tr("Music and sound"), UI.HEADING_SIZE))
			for i in CREDITS.size():
				box.add_child(UI.with_info(UI.label(CREDITED[i]), tr(CREDITS[i])))
			box.add_child(UI.label(tr("All under CC0, given freely. Thank you."), UI.SMALL_SIZE, UI.MUTED))
		"engine":
			box.add_child(UI.label(tr("Built with"), UI.HEADING_SIZE))
			box.add_child(UI.label("Godot Engine (godotengine.org)"))


# --- Lobby -------------------------------------------------------------------

func _show_lobby(world: Dictionary) -> void:
	_lobby = world
	# A picker open over the lobby stays open; the lobby shows the news after.
	if _pick_for == "lobby" and _page in ["pick_hero", "pick_clan"]:
		return
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
	_content.add_child(UI.with_info(UI.label(tr("%d of %d players joined") % [world.members.size(), world.maxPlayers], UI.SMALL_SIZE, UI.MUTED),
		tr("Share the code with your group: they join with it from Play with friends.")))
	for member in world.members:
		var host := tr(" (host)") if int(member.accountId) == int(world.hostAccountId) else ""
		var clan := " · %s" % ClanText.title(Game.data, member.get("clan")) if not Game.data.is_empty() else ""
		var hero := " · %s" % tr(HeroText.roster(Game.data, member.get("heroKind")).get("name", "")) if member.get("heroKind") != null and not Game.data.is_empty() else ""
		_content.add_child(UI.label("• %s%s%s%s" % [member.displayName, host, clan, hero]))
	if int(world.hostAccountId) == int(Session.account.id):
		_content.add_child(UI.primary(tr("Start the world"), func() -> void: _start_world(int(world.id)), "icon/play"))
	else:
		_content.add_child(UI.label(tr("Waiting for the host to start…"), UI.SMALL_SIZE, UI.MUTED))
	_lobby_choices(world)
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


## The hero and clan you play in this world, each changeable until the start.
func _lobby_choices(world: Dictionary) -> void:
	if Game.data.is_empty():
		var error := await Game.ensure_data()
		if error == "" and _lobby_world_id == int(world.id):
			_render("lobby")
		return
	_choice = {"hero": null, "clan": null}
	for member in world.members:
		if int(member.accountId) == int(Session.account.id):
			_choice = {"hero": member.get("heroKind"), "clan": member.get("clan")}
	_pick_for = "lobby"
	_choice_buttons(Game.data)


## Heroes another member of the lobby rides with: {kind: their name}.
func _heroes_taken() -> Dictionary:
	var taken := {}
	if _pick_for != "lobby":
		return taken
	for member in _lobby.get("members", []):
		if int(member.accountId) != int(Session.account.id) and member.get("heroKind") != null:
			taken[String(member.heroKind)] = String(member.displayName)
	return taken


# --- Hero and clan pickers ----------------------------------------------------

## Two buttons, each opening its picker: the hero's portrait or the clan's
## emblem, and its name (or a call to choose one).
func _choice_buttons(data: Dictionary) -> void:
	var row := UI.hbox(12)
	var hero_pick := _choice_button(tr("Hero"), HeroText.roster_title(data, _choice.hero) if _choice.hero != null else tr("Choose your hero"),
		"hero/%s" % _choice.hero if _choice.hero != null else "icon/troops", _choice.hero == null, "pick_hero")
	row.add_child(hero_pick)
	var clan_pick := _choice_button(tr("Clan"), ClanText.title(data, _choice.clan) if _choice.clan != null else tr("Choose your clan"),
		"clan/%s" % _choice.clan if _choice.clan != null else "icon/village", _choice.clan == null, "pick_clan")
	row.add_child(clan_pick)
	_content.add_child(row)


func _choice_button(what: String, text: String, icon_id: String, missing: bool, page: String) -> Button:
	var go := func() -> void: _open(page)
	var button := UI.primary("%s\n%s" % [what, text], go, icon_id) if missing else UI.button("%s\n%s" % [what, text], go, icon_id)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 112 * UiTheme.text_scale
	button.add_theme_constant_override("icon_max_width", int(80 * UiTheme.text_scale))
	# A portrait or an emblem in its own colours, not tinted like an icon.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button


## The game's data for the pickers: the app's own for a solo world, the
## server's for co-op (loaded with the form).
func _pick_data() -> Dictionary:
	return LocalData.load_data() if Game.data.is_empty() else Game.data


## Every hero as a portrait tile; the one tapped is shown below with its story,
## strengths and traits, and chosen with the button under it.
func _hero_pick_page() -> void:
	var data := _pick_data()
	var taken := _heroes_taken()
	var tiles := GridContainer.new()
	tiles.columns = 3
	tiles.add_theme_constant_override("h_separation", 10)
	tiles.add_theme_constant_override("v_separation", 10)
	for kind in HeroText.roster_ids(data):
		tiles.add_child(_pick_tile(tr(HeroText.roster(data, kind).get("name", kind)), "hero/%s" % kind, kind, kind == _choice.hero, "pick_hero"))
	_content.add_child(tiles)
	if _pick_preview == null:
		_content.add_child(UI.label(tr("Tap a hero to read about them."), UI.SMALL_SIZE, UI.MUTED))
		return
	var kind: String = _pick_preview
	var def := HeroText.roster(data, kind)
	_content.add_child(UI.label(HeroText.roster_title(data, kind), UI.HEADING_SIZE))
	_content.add_child(UI.label(tr(def.story), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(HeroText.effects(def.effects), UI.SMALL_SIZE))
	for line in HeroText.roster_traits(data, kind):
		_content.add_child(UI.label(line, UI.SMALL_SIZE, UI.MUTED))
	if taken.has(kind):
		_content.add_child(UI.label(tr("Rides with %s") % taken[kind], UI.SMALL_SIZE, UI.ERROR))
		return
	_content.add_child(UI.primary(tr("Choose %s") % tr(def.name), func() -> void: _choose("hero", kind), "icon/play"))


## Every clan as an emblem tile; the one tapped is shown below with its story
## and perks, and chosen with the button under it.
func _clan_pick_page() -> void:
	var data := _pick_data()
	var tiles := GridContainer.new()
	tiles.columns = 3
	tiles.add_theme_constant_override("h_separation", 10)
	tiles.add_theme_constant_override("v_separation", 10)
	for clan in ClanText.ids(data):
		tiles.add_child(_pick_tile(tr(data.clans.clans[clan].animal), "clan/%s" % clan, clan, clan == _choice.clan, "pick_clan"))
	_content.add_child(tiles)
	if _pick_preview == null:
		_content.add_child(UI.label(tr("Tap a clan to read about it."), UI.SMALL_SIZE, UI.MUTED))
		return
	var clan: String = _pick_preview
	var def: Dictionary = data.clans.clans[clan]
	_content.add_child(UI.label(ClanText.title(data, clan), UI.HEADING_SIZE))
	_content.add_child(UI.label(tr(def.story), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(tr("Best at: %s") % tr(def.best), UI.SMALL_SIZE))
	_content.add_child(UI.label(tr("Weakness: %s") % tr(def.weakness), UI.SMALL_SIZE))
	_content.add_child(UI.label(tr("Their own: %s") % ClanText.unique_name(data, clan), UI.SMALL_SIZE))
	_content.add_child(UI.primary(tr("Choose %s") % ClanText.title(data, clan), func() -> void: _choose("clan", clan), "icon/play"))


## A picker tile: the image large over its name; the one on show is lit,
## the one chosen has a tick.
func _pick_tile(text: String, icon_id: String, id: String, chosen: bool, page: String) -> Button:
	var tile := UI.button("", func() -> void:
		_pick_preview = id
		_render(page))
	tile.theme_type_variation = "TabButton"
	tile.disabled = _pick_preview == id
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size.y = 190 * UiTheme.text_scale
	var box := UI.vbox(4)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 8
	box.offset_bottom = -8
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var image := TextureRect.new()
	image.texture = Art.texture(icon_id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(image)
	var caption := UI.label(("✓ " if chosen else "") + text, UI.SMALL_SIZE, UI.ACCENT if chosen else Color.WHITE)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(caption)
	return tile


## Takes the hero or clan: into the form, or straight to the lobby's world.
func _choose(what: String, id: String) -> void:
	_choice[what] = id
	if _pick_for == "lobby":
		var path := "/v1/worlds/%d/%s" % [int(_lobby.id), what]
		var response := await Api.request(HTTPClient.METHOD_PUT, path, {"kind": id} if what == "hero" else {"clan": id})
		if not response.ok:
			_set_status(response.error)
			return
		_lobby = response.data
	_back()


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
