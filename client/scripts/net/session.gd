extends Node
## The login token and language, persisted on the device, and the server
## the game talks to.

const PATH := "user://session.cfg"
## The game's server (docs/production.md). Exported builds always use it.
const REMOTE_SERVER_URL := "https://2-31-39-17.sslip.io"
## A server on this computer, for running the game from the editor.
const LOCAL_SERVER_URL := "http://127.0.0.1:8080"

## SLAVIAN_SERVER_URL overrides both, e.g. to try a branch's server.
var server_url := _pick_server_url()
var token := ""
var account: Dictionary = {}
## The game's language: "en" or "sr_Latn" (docs/localization.md).
var language := ""
## Text size for accessibility: "small", "normal" or "large" (M5 15).
var text_size := "normal"
## The tutorial on this device, per world: {world id: {"welcomed": bool, "hidden": bool}}.
var tutorial: Dictionary = {}
## The world played last, for the menu's Continue: {"id", "name"} (solo ids
## are negative).
var last_world: Dictionary = {}
## Music and effects volumes, 0 to 1 (M5 26).
var music_volume := 0.6
var effects_volume := 0.8


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		token = config.get_value("session", "token", "")
		account = config.get_value("session", "account", {})
		language = config.get_value("session", "language", "")
		text_size = config.get_value("session", "text_size", "normal")
		tutorial = config.get_value("session", "tutorial", {})
		last_world = config.get_value("session", "last_world", {})
		music_volume = config.get_value("session", "music_volume", 0.6)
		effects_volume = config.get_value("session", "effects_volume", 0.8)
	# First run: Serbian for a Serbian device, English otherwise.
	if language == "":
		language = "sr_Latn" if OS.get_locale_language() in ["sr", "bs", "hr", "me"] else "en"
	UiTheme.set_text_size(text_size)
	UiTheme.apply()
	var window := get_tree().root
	UiTheme.fit(window)
	window.size_changed.connect(func() -> void: UiTheme.fit(window))
	TranslationServer.set_locale(language)
	# Players who signed in before the server kept languages tell it now.
	if token != "":
		report_language.call_deferred()
	# Only strings marked with tr() are translated, never names players chose.
	get_tree().root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("session", "token", token)
	# Who is signed in (id and name), so the menu can say so offline too.
	config.set_value("session", "account", account)
	config.set_value("session", "language", language)
	config.set_value("session", "text_size", text_size)
	config.set_value("session", "tutorial", tutorial)
	config.set_value("session", "last_world", last_world)
	config.set_value("session", "music_volume", music_volume)
	config.set_value("session", "effects_volume", effects_volume)
	config.save(PATH)


func set_language(code: String) -> void:
	language = code
	TranslationServer.set_locale(code)
	save()
	report_language()


## Tells the server which language to write notices (push and inbox) in.
func report_language() -> void:
	if token != "":
		Api.request(HTTPClient.METHOD_PATCH, "/v1/me", {"language": language})


## How far the tutorial got in a world on this device ("welcomed", "hidden").
func tutorial_flag(world_id: int, key: String) -> bool:
	return bool(tutorial.get(str(world_id), {}).get(key, false))


func set_tutorial_flag(world_id: int, key: String, value: bool) -> void:
	var state: Dictionary = tutorial.get(str(world_id), {})
	state[key] = value
	tutorial[str(world_id)] = state
	save()


func set_text_size(size: String) -> void:
	text_size = size
	UiTheme.set_text_size(size)
	# Rebuild the theme: its default and button font sizes follow the scale.
	UiTheme.apply()
	save()


func is_logged_in() -> bool:
	return token != ""


func log_out() -> void:
	token = ""
	account = {}
	save()


static func _pick_server_url() -> String:
	var override := OS.get_environment("SLAVIAN_SERVER_URL").strip_edges().trim_suffix("/")
	if override != "":
		return override
	return LOCAL_SERVER_URL if OS.has_feature("editor") else REMOTE_SERVER_URL


func live_url() -> String:
	return server_url.replace("https://", "wss://").replace("http://", "ws://") + "/v1/live"
