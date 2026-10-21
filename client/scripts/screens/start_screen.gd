extends Control
## First screen: play solo on this device (no sign-in or connection
## needed), or sign in as a guest, then pick, create or join a co-op world
## and wait in its lobby until the host starts it.

const GAME_SCENE := "res://scenes/game.tscn"
const SPEEDS := [1, 2, 10]
const SPEED_LABELS := ["Normal (1×)", "Fast (2×)", "Test (10×)"]  # tr
const WORLD_STATUSES := ["Running", "Won", "Lost"]  # tr
## Languages by their own names, never translated.
const LANGUAGES := [["en", "English"], ["sr_Latn", "Srpski"]]

var _status: Label
var _content: VBoxContainer
var _layout: BoxContainer
var _hero: Control
var _logo: TextureRect
var _tagline: Label
var _frame: PanelContainer
var _lobby_world_id := 0
## A solo world waiting for a second tap to be deleted.
var _delete_solo := 0
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
	sheet_box.add_child(scroll)
	var sheet := UI.vbox(18)
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sheet)
	sheet.add_child(_settings_row())
	_status = UI.label("", UI.SMALL_SIZE, UI.ERROR)
	sheet.add_child(_status)
	_content = UI.vbox(20)
	sheet.add_child(_content)
	get_viewport().size_changed.connect(_arrange)
	_arrange()

	Live.world_updated.connect(_on_live_world)
	Live.connection_changed.connect(_on_live_connection)
	if Session.is_logged_in():
		Push.register()
		_show_home()
	else:
		_show_login()


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


## The language (by its own name) and the text size, on one row.
func _settings_row() -> Control:
	var row := UI.hbox(8)
	for language in LANGUAGES:
		var code: String = language[0]
		var pick := UI.button(language[1], func() -> void:
			Session.set_language(code)
			get_tree().reload_current_scene())
		pick.theme_type_variation = "TabButton"
		pick.disabled = Session.language == code
		pick.custom_minimum_size.x = 150
		row.add_child(pick)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	# Text size for accessibility: the same letter at three sizes.
	for entry in [["small", 22, tr("Small")], ["normal", 28, tr("Normal")], ["large", 36, tr("Large")]]:
		var size_code: String = entry[0]
		var size_pick := UI.button("A", func() -> void:
			Session.set_text_size(size_code)
			get_tree().reload_current_scene())
		size_pick.theme_type_variation = "TabButton"
		size_pick.add_theme_font_size_override("font_size", int(entry[1]))
		size_pick.tooltip_text = tr("Text size: %s") % entry[2]
		size_pick.disabled = Session.text_size == size_code
		size_pick.custom_minimum_size = Vector2(64, 76)
		row.add_child(size_pick)
	return row


func _exit_tree() -> void:
	Live.world_updated.disconnect(_on_live_world)
	Live.connection_changed.disconnect(_on_live_connection)


func _set_status(text: String) -> void:
	_status.text = text


# --- Sign in ---------------------------------------------------------------

func _show_login() -> void:
	UI.clear(_content)
	_content.add_child(UI.label(tr("Your name"), UI.SMALL_SIZE, UI.MUTED))
	var name_edit := UI.line_edit(tr("e.g. Vesna"))
	_content.add_child(name_edit)
	_content.add_child(UI.primary(tr("Play as guest"), func() -> void:
		_login(name_edit.text)))
	_content.add_child(_solo_section(name_edit))


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
	_show_home()


# --- Worlds ----------------------------------------------------------------

func _show_home() -> void:
	Live.stop()
	_lobby_world_id = 0
	UI.clear(_content)
	_content.add_child(UI.label(tr("Loading…"), UI.SMALL_SIZE, UI.MUTED))
	var response := await Api.get_json("/v1/me")
	if response.status == 401:
		Session.log_out()
		_show_login()
		return
	if not response.ok:
		UI.clear(_content)
		_set_status(response.error)
		_content.add_child(UI.button(tr("Retry"), _show_home))
		# No server: solo worlds play on all the same.
		_content.add_child(_solo_section())
		return
	_set_status("")
	Session.account = response.data.account
	UI.clear(_content)

	var who := UI.hbox()
	var signed_in := UI.label(tr("Signed in as %s") % Session.account.displayName, UI.SMALL_SIZE, UI.MUTED)
	signed_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(signed_in)
	who.add_child(UI.button(tr("Sign out"), func() -> void:
		Session.log_out()
		_show_login()))
	_content.add_child(who)

	_content.add_child(_solo_section())

	_content.add_child(UI.label(tr("Your worlds"), UI.HEADING_SIZE))
	if response.data.worlds.is_empty():
		_content.add_child(UI.label(tr("None yet. Create one or join with a code."), UI.SMALL_SIZE, UI.MUTED))
	for world in response.data.worlds:
		var text := "%s  ·  %s" % [world.name, tr("in lobby") if world.status == "lobby" else tr(String(world.status).capitalize())]
		var world_id := int(world.id)
		_content.add_child(UI.button(text, func() -> void: _open_world(world_id)))

	_content.add_child(UI.label(tr("New world"), UI.HEADING_SIZE))
	var world_name := UI.line_edit(tr("World name"), tr("%s's world") % Session.account.displayName)
	_content.add_child(world_name)
	var row := UI.hbox()
	var players := UI.options(range(1, 7).map(func(n: int) -> String: return tr_n("%d player", "%d players", n) % n), 1)
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(players)
	var speed := UI.options(SPEED_LABELS.map(tr), 0)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	_content.add_child(row)
	var difficulty := UI.options(GroupText.DIFFICULTY_LABELS.map(tr), 1)
	_content.add_child(difficulty)
	_content.add_child(UI.primary(tr("Create world"), func() -> void:
		_create_world(world_name.text, players.selected + 1, SPEEDS[speed.selected], GroupText.DIFFICULTIES[difficulty.selected])))

	_content.add_child(UI.label(tr("Join a world"), UI.HEADING_SIZE))
	var code := UI.line_edit(tr("Invite code"))
	_content.add_child(code)
	_content.add_child(UI.button(tr("Join"), func() -> void: _join_world(code.text)))

	# Support and privacy: donations, server costs, your data, and the bug report.
	_content.add_child(UI.label(tr("Support and privacy"), UI.HEADING_SIZE))
	_content.add_child(UI.button(tr("Support and privacy"), _show_support))


## The privacy policy, in short (docs/privacy.md has the long version).
const PRIVACY := "Slavian keeps as little as it can: the name you choose (or a guest name), your sign-in sessions, and the state of the worlds you play in. There is no advertising, no tracking and no sharing with third parties. Push notifications use your device token only to reach you. You can download what is kept about you and delete your account at any time from this screen. Deletion removes the account, its sessions, memberships and device tokens."  # tr

var _delete_armed := false


## Donations, this month's server costs, the privacy policy, exporting your
## data and deleting your account.
func _show_support() -> void:
	_set_status("")
	_delete_armed = false
	UI.clear(_content)
	_content.add_child(UI.label(tr("Support and privacy"), UI.HEADING_SIZE))
	var costs := await Api.get_json("/v1/costs")
	if not costs.ok or not costs.data is Dictionary:
		_content.add_child(UI.label(tr("Could not load the server costs."), UI.SMALL_SIZE, UI.MUTED))
	else:
		var c: Dictionary = costs.data
		var currency := str(c.get("currency", "EUR"))
		var spent := float(c.get("costs", 0.0))
		var raised := float(c.get("donations", 0.0)) + float(c.get("carryIn", 0.0))
		_content.add_child(UI.label(tr("This month (%s): server costs %s, donations %s.") % [
			str(c.get("month", "")), "%s %.2f" % [currency, spent], "%s %.2f" % [currency, raised]], UI.SMALL_SIZE, UI.MUTED))
		var bar := ProgressBar.new()
		bar.max_value = maxf(spent, 0.01)
		bar.value = minf(raised, spent)
		bar.custom_minimum_size.y = 28
		bar.show_percentage = false
		_content.add_child(bar)
		var surplus := raised - spent
		_content.add_child(UI.label(tr("Carried to next month: %s") % ("%s %.2f" % [currency, surplus]), UI.SMALL_SIZE, UI.MUTED))
		var url := str(c.get("donationUrl", ""))
		if url != "":
			_content.add_child(UI.primary(tr("Buy me a coffee"), func() -> void: OS.shell_open(url)))
	_content.add_child(UI.label(tr("Privacy policy"), UI.SMALL_SIZE))
	_content.add_child(UI.label(tr(PRIVACY), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.button(tr("Export my data"), _export_data))
	_content.add_child(UI.button(tr("Delete my account"), _confirm_delete))
	_content.add_child(UI.button(tr("Back"), _show_home))


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
	_show_login()


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


# --- Solo ------------------------------------------------------------------

## Solo worlds on this device: continue one, start one, or delete one. They
## need neither an account nor a connection (docs/local-engine.md).
## `name_edit`: the sign-in name field, for the player's name when not
## signed in.
func _solo_section(name_edit: LineEdit = null) -> Control:
	var box := UI.vbox(12)
	box.add_child(UI.label(tr("Play solo"), UI.HEADING_SIZE))
	box.add_child(UI.label(tr("On this device, alone against the hordes. No connection needed."), UI.SMALL_SIZE, UI.MUTED))
	for world in Local.list_worlds():
		var row := UI.hbox()
		var id := int(world.id)
		var status := tr(String(world.status).capitalize())
		var open := UI.button(world.name, func() -> void: _open_solo(id))
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(open)
		var about := UI.label("%s\n%s" % [status, tr(GroupText.DIFFICULTY_LABELS[maxi(0, GroupText.DIFFICULTIES.find(world.difficulty))])], UI.SMALL_SIZE, UI.MUTED)
		row.add_child(about)
		var armed := _delete_solo == id
		row.add_child(UI.button(tr("Sure? Delete") if armed else tr("Delete"), func() -> void:
			if _delete_solo == id:
				Local.delete_world(id)
				_delete_solo = 0
			else:
				_delete_solo = id
			_refresh_solo(box, name_edit)))
		box.add_child(row)

	var data := LocalData.load_data()
	var world_name := UI.line_edit(tr("World name"), tr("A solo world"))
	box.add_child(world_name)
	var row := UI.hbox()
	var speed := UI.options(SPEED_LABELS.map(tr), 0)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	var difficulty := UI.options(GroupText.DIFFICULTY_LABELS.map(tr), 1)
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(difficulty)
	box.add_child(row)
	var kinds := HeroText.roster_ids(data)
	var hero := UI.options(kinds.map(func(kind: String) -> String: return HeroText.roster_title(data, kind)), 0)
	box.add_child(hero)
	box.add_child(UI.primary(tr("Start a solo world"), func() -> void:
		var who := String(Session.account.get("displayName", "")) if Session.is_logged_in() else ""
		if who == "" and name_edit != null:
			who = name_edit.text.strip_edges()
		_start_solo({"name": world_name.text.strip_edges() if world_name.text.strip_edges() != "" else tr("A solo world"),
			"displayName": who if who != "" else tr("You"), "speed": SPEEDS[speed.selected],
			"difficulty": GroupText.DIFFICULTIES[difficulty.selected], "heroKind": kinds[hero.selected] if not kinds.is_empty() else null})))
	return box


## Rebuilds the solo section in place (after a delete).
func _refresh_solo(box: Control, name_edit: LineEdit) -> void:
	var parent := box.get_parent()
	var at := box.get_index()
	box.queue_free()
	var fresh := _solo_section(name_edit)
	parent.add_child(fresh)
	parent.move_child(fresh, at)


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


# --- Lobby -----------------------------------------------------------------

func _show_lobby(world: Dictionary) -> void:
	if _lobby_world_id != int(world.id):
		_lobby_world_id = int(world.id)
		Live.watch(_lobby_world_id)
	UI.clear(_content)
	_content.add_child(UI.label(world.name, UI.HEADING_SIZE))
	_content.add_child(UI.label(tr("Invite code"), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(world.inviteCode, UI.TITLE_SIZE))
	_content.add_child(UI.label(tr("Share it with your group. %d of %d players joined.") % [world.members.size(), world.maxPlayers], UI.SMALL_SIZE, UI.MUTED))
	for member in world.members:
		var host := tr(" (host)") if int(member.accountId) == int(world.hostAccountId) else ""
		var clan := " · %s" % ClanText.title(Game.data, member.get("clan")) if not Game.data.is_empty() else ""
		var hero := " · %s" % tr(HeroText.roster(Game.data, member.get("heroKind")).get("name", "")) if member.get("heroKind") != null and not Game.data.is_empty() else ""
		_content.add_child(UI.label("• %s%s%s%s" % [member.displayName, host, clan, hero]))
	if int(world.hostAccountId) == int(Session.account.id):
		_content.add_child(UI.primary(tr("Start the world"), func() -> void: _start_world(int(world.id))))
	else:
		_content.add_child(UI.label(tr("Waiting for the host to start…"), UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.button(tr("Back"), _show_home))
	_clan_picker(world)
	_hero_picker(world)


## Each member picks their clan in the lobby (and may change it until the start).
func _clan_picker(world: Dictionary) -> void:
	if Game.data.is_empty():
		var error := await Game.ensure_data()
		if error == "" and _lobby_world_id == int(world.id):
			_show_lobby(world)
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
	get_tree().change_scene_to_file(GAME_SCENE)
