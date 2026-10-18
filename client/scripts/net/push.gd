extends Node
## Push notifications on Android: asks for permission, gets the Firebase
## Cloud Messaging token and registers it with the server so it can notify
## this phone. The Firebase plugin only exists in Android exports (see
## ops/ci/setup-firebase-android.sh); everywhere else this does nothing.

const CORE := "GodotxFirebaseCore"
const MESSAGING := "GodotxFirebaseMessaging"

var _messaging: Object = null
var _token := ""
var _registered_token := ""
var _registering := false


func _ready() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton(CORE) or not Engine.has_singleton(MESSAGING):
		return
	var core := Engine.get_singleton(CORE)
	_messaging = Engine.get_singleton(MESSAGING)
	core.core_initialized.connect(_on_core_initialized)
	_messaging.messaging_permission_granted.connect(_on_permission_granted)
	_messaging.messaging_permission_denied.connect(_on_permission_denied)
	_messaging.messaging_token_received.connect(_on_token_received)
	_messaging.messaging_error.connect(_on_error)
	core.initialize()


## Sends the token to the server once there is both a token and a login.
## Safe to call any time; it is a no-op until both exist.
func register() -> void:
	if _registering or _token == "" or _token == _registered_token or not Session.is_logged_in():
		return
	_registering = true
	var token := _token
	var response := await Api.post_json("/v1/me/devices", {"token": token, "platform": "android"})
	_registering = false
	if response.ok:
		_registered_token = token
	else:
		push_warning("Push: could not register the device token: %s" % response.error)


func _on_core_initialized(success: bool) -> void:
	if not success:
		push_warning("Push: Firebase failed to initialise")
		return
	_messaging.initialize()
	_messaging.request_permission()


func _on_permission_granted() -> void:
	_messaging.get_token()


func _on_permission_denied() -> void:
	print("Push: notification permission denied")


func _on_token_received(token: String) -> void:
	_token = token
	register()


func _on_error(message: String) -> void:
	push_warning("Push: %s" % message)
