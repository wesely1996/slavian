extends Node
## The server address and login token, persisted on the device.

const PATH := "user://session.cfg"
const DEFAULT_SERVER_URL := "http://127.0.0.1:8080"

var server_url := DEFAULT_SERVER_URL
var token := ""
var account: Dictionary = {}


func _ready() -> void:
	UiTheme.apply()
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		server_url = config.get_value("session", "server_url", DEFAULT_SERVER_URL)
		token = config.get_value("session", "token", "")


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("session", "server_url", server_url)
	config.set_value("session", "token", token)
	config.save(PATH)


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
