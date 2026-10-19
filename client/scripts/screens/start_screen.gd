extends Control
## First screen: sign in as a guest, then pick, create or join a world and
## wait in its lobby until the host starts it.

const GAME_SCENE := "res://scenes/game.tscn"
const SPEEDS := [1, 2, 10]
const SPEED_LABELS := ["Normal (1×)", "Fast (2×)", "Test (10×)"]

var _status: Label
var _content: VBoxContainer
var _lobby_world_id := 0
## Both the start request and the live "world started" push lead here.
var _entering := false


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var root := UI.vbox(24)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	root.add_child(UI.label("Slavian", UI.TITLE_SIZE))
	root.add_child(UI.label("Defend the Holy City. Build the Kalinov Bridge.", UI.SMALL_SIZE, UI.MUTED))
	_status = UI.label("", UI.SMALL_SIZE, UI.ERROR)
	root.add_child(_status)
	_content = UI.vbox(20)
	root.add_child(_content)

	Live.world_updated.connect(_on_live_world)
	Live.connection_changed.connect(_on_live_connection)
	if Session.is_logged_in():
		Push.register()
		_show_home()
	else:
		_show_login()


func _exit_tree() -> void:
	Live.world_updated.disconnect(_on_live_world)
	Live.connection_changed.disconnect(_on_live_connection)


func _set_status(text: String) -> void:
	_status.text = text


# --- Sign in ---------------------------------------------------------------

func _show_login() -> void:
	UI.clear(_content)
	_content.add_child(UI.label("Server address", UI.SMALL_SIZE, UI.MUTED))
	var server := UI.line_edit("http://192.168.1.10:8080", Session.server_url)
	_content.add_child(server)
	_content.add_child(UI.label("Your name", UI.SMALL_SIZE, UI.MUTED))
	var name_edit := UI.line_edit("e.g. Vesna")
	_content.add_child(name_edit)
	_content.add_child(UI.button("Play as guest", func() -> void:
		_login(server.text, name_edit.text)))


func _login(server_url: String, display_name: String) -> void:
	_set_status("")
	Session.set_server_url(server_url)
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
	Push.register()
	_show_home()


# --- Worlds ----------------------------------------------------------------

func _show_home() -> void:
	Live.stop()
	_lobby_world_id = 0
	UI.clear(_content)
	_content.add_child(UI.label("Loading…", UI.SMALL_SIZE, UI.MUTED))
	var response := await Api.get_json("/v1/me")
	if response.status == 401:
		Session.log_out()
		_show_login()
		return
	if not response.ok:
		UI.clear(_content)
		_set_status(response.error)
		_content.add_child(UI.label("Server: %s" % Session.server_url, UI.SMALL_SIZE, UI.MUTED))
		_content.add_child(UI.button("Retry", _show_home))
		_content.add_child(UI.button("Change server address", _show_server_editor))
		return
	_set_status("")
	Session.account = response.data.account
	UI.clear(_content)

	var who := UI.hbox()
	var signed_in := UI.label("Signed in as %s" % Session.account.displayName, UI.SMALL_SIZE, UI.MUTED)
	signed_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(signed_in)
	who.add_child(UI.button("Sign out", func() -> void:
		Session.log_out()
		_show_login()))
	_content.add_child(who)
	var server := UI.hbox()
	var server_label := UI.label("Server: %s" % Session.server_url, UI.SMALL_SIZE, UI.MUTED)
	server_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server.add_child(server_label)
	server.add_child(UI.button("Change", _show_server_editor))
	_content.add_child(server)

	_content.add_child(UI.label("Your worlds", UI.HEADING_SIZE))
	if response.data.worlds.is_empty():
		_content.add_child(UI.label("None yet. Create one or join with a code.", UI.SMALL_SIZE, UI.MUTED))
	for world in response.data.worlds:
		var text := "%s  ·  %s" % [world.name, "in lobby" if world.status == "lobby" else world.status]
		var world_id := int(world.id)
		_content.add_child(UI.button(text, func() -> void: _open_world(world_id)))

	_content.add_child(UI.label("New world", UI.HEADING_SIZE))
	var world_name := UI.line_edit("World name", "%s's world" % Session.account.displayName)
	_content.add_child(world_name)
	var row := UI.hbox()
	var players := UI.options(["1 player", "2 players", "3 players", "4 players", "5 players", "6 players"], 1)
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(players)
	var speed := UI.options(SPEED_LABELS, 0)
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speed)
	_content.add_child(row)
	var difficulty := UI.options(GroupText.DIFFICULTY_LABELS, 1)
	_content.add_child(difficulty)
	_content.add_child(UI.button("Create world", func() -> void:
		_create_world(world_name.text, players.selected + 1, SPEEDS[speed.selected], GroupText.DIFFICULTIES[difficulty.selected])))

	_content.add_child(UI.label("Join a world", UI.HEADING_SIZE))
	var code := UI.line_edit("Invite code")
	_content.add_child(code)
	_content.add_child(UI.button("Join", func() -> void: _join_world(code.text)))


## Changes the server address but stays signed in: a playtest server behind
## a quick tunnel gets a new address on every restart, while the account
## lives in its database.
func _show_server_editor() -> void:
	_set_status("")
	UI.clear(_content)
	_content.add_child(UI.label("Server address", UI.HEADING_SIZE))
	_content.add_child(UI.label("You stay signed in; your account lives on the server.", UI.SMALL_SIZE, UI.MUTED))
	var address := UI.line_edit("https://example.trycloudflare.com", Session.server_url)
	_content.add_child(address)
	_content.add_child(UI.button("Save", func() -> void:
		Session.set_server_url(address.text)
		Session.save()
		_show_home()))
	_content.add_child(UI.button("Cancel", _show_home))


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


# --- Lobby -----------------------------------------------------------------

func _show_lobby(world: Dictionary) -> void:
	if _lobby_world_id != int(world.id):
		_lobby_world_id = int(world.id)
		Live.watch(_lobby_world_id)
	UI.clear(_content)
	_content.add_child(UI.label(world.name, UI.HEADING_SIZE))
	_content.add_child(UI.label("Invite code", UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.label(world.inviteCode, UI.TITLE_SIZE))
	_content.add_child(UI.label("Share it with your group. %d of %d players joined." % [world.members.size(), world.maxPlayers], UI.SMALL_SIZE, UI.MUTED))
	for member in world.members:
		var host := " (host)" if int(member.accountId) == int(world.hostAccountId) else ""
		var clan := " · %s" % ClanText.title(Game.data, member.get("clan")) if not Game.data.is_empty() else ""
		_content.add_child(UI.label("• %s%s%s" % [member.displayName, host, clan]))
	if int(world.hostAccountId) == int(Session.account.id):
		_content.add_child(UI.button("Start the world", func() -> void: _start_world(int(world.id))))
	else:
		_content.add_child(UI.label("Waiting for the host to start…", UI.SMALL_SIZE, UI.MUTED))
	_content.add_child(UI.button("Back", _show_home))
	_clan_picker(world)


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
	_content.add_child(UI.label("Your clan: %s" % ClanText.title(Game.data, mine), UI.HEADING_SIZE))
	for clan in ClanText.ids(Game.data):
		var def: Dictionary = Game.data.clans.clans[clan]
		var pick := UI.button(("✓ " if clan == mine else "") + ClanText.title(Game.data, clan), func() -> void: _pick_clan(int(world.id), clan))
		_content.add_child(pick)
		_content.add_child(UI.label(def.story, UI.SMALL_SIZE, UI.MUTED))
		_content.add_child(UI.label(ClanText.perks(Game.data, clan), UI.SMALL_SIZE, UI.MUTED))


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
