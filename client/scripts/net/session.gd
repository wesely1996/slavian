extends Node
## The server address, login token and language, persisted on the device.

const PATH := "user://session.cfg"
const DEFAULT_SERVER_URL := "http://127.0.0.1:8080"

var server_url := DEFAULT_SERVER_URL
var token := ""
var account: Dictionary = {}
## The game's language: "en" or "sr_Latn" (docs/localization.md).
var language := ""


func _ready() -> void:
	UiTheme.apply()
	var window := get_tree().root
	UiTheme.fit(window)
	window.size_changed.connect(func() -> void: UiTheme.fit(window))
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		server_url = config.get_value("session", "server_url", DEFAULT_SERVER_URL)
		token = config.get_value("session", "token", "")
		language = config.get_value("session", "language", "")
	# First run: Serbian for a Serbian device, English otherwise.
	if language == "":
		language = "sr_Latn" if OS.get_locale_language() in ["sr", "bs", "hr", "me"] else "en"
	TranslationServer.set_locale(language)
	# Only strings marked with tr() are translated, never names players chose.
	get_tree().root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("session", "server_url", server_url)
	config.set_value("session", "token", token)
	config.set_value("session", "language", language)
	config.save(PATH)


func set_language(code: String) -> void:
	language = code
	TranslationServer.set_locale(code)
	save()


func is_logged_in() -> bool:
	return token != ""


func log_out() -> void:
	token = ""
	account = {}
	save()


func set_server_url(url: String) -> void:
	server_url = normalize_url(url)


## Adds a scheme when missing: http for IPs and localhost (a server on your
## Wi-Fi), https for domain names (e.g. a trycloudflare.com tunnel).
static func normalize_url(url: String) -> String:
	var clean := url.strip_edges().trim_suffix("/")
	if clean.contains("://"):
		return clean
	var host := clean.split("/")[0].split(":")[0]
	var local := host == "localhost" or host.is_valid_ip_address()
	return ("http://" if local else "https://") + clean


func live_url() -> String:
	return server_url.replace("https://", "wss://").replace("http://", "ws://") + "/v1/live"
