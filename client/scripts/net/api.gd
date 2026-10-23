extends Node
## Thin JSON client for the game server's HTTP API. Every call resolves to
## a Response; nothing throws.


class Response:
	extends RefCounted
	var ok := false
	var status := 0
	var data: Variant = null
	var error := ""


func get_json(path: String) -> Response:
	return await request(HTTPClient.METHOD_GET, path)


func post_json(path: String, body: Dictionary = {}, remote := false) -> Response:
	return await request(HTTPClient.METHOD_POST, path, body, remote)


func patch_json(path: String, body: Dictionary) -> Response:
	return await request(HTTPClient.METHOD_PATCH, path, body)


## `remote`: to the server even while a solo world is open (bug reports).
func request(method: HTTPClient.Method, path: String, body: Variant = null, remote := false) -> Response:
	var response := Response.new()
	# A solo world plays on the device (docs/local-engine.md).
	if Local.is_active() and not remote:
		var answer := Local.respond(method, path, body)
		response.status = answer.status
		response.data = answer.data
		response.ok = response.status >= 200 and response.status < 300
		if not response.ok:
			response.error = error_text(answer.data, response.status)
		return response
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json"])
	if body != null:
		headers.append("Content-Type: application/json")
	if Session.token != "":
		headers.append("Authorization: Bearer " + Session.token)
	var payload := "" if body == null else JSON.stringify(body)

	var err := http.request(Session.server_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		response.error = "Could not reach the server (%s)" % error_string(err)
		return response
	var result: Array = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		response.error = "Could not reach the server at %s" % Session.server_url
		return response
	response.status = result[1]
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	response.data = JSON.parse_string(text) if text != "" else null
	response.ok = response.status >= 200 and response.status < 300
	if not response.ok:
		response.error = error_text(response.data, response.status)
	return response


## What went wrong, in words for the player: what is missing rather than
## the server's record of it ("Not enough: 120 more wood, 30 more iron.").
static func error_text(data: Variant, status: int) -> String:
	if not data is Dictionary:
		return UI.t("Server error %d") % status
	if data.get("error") == "insufficient_resources" and data.get("missing") is Dictionary:
		var parts := PackedStringArray()
		for kind in ["wood", "stone", "grain", "iron"]:
			var short := ceili(float(data.missing.get(kind, 0)))
			if short > 0:
				parts.append(UI.t("%d more %s") % [short, UI.resource_name(kind).to_lower()])
		return UI.t("Not enough resources: %s.") % ", ".join(parts)
	if data.has("message"):
		return str(data.message)
	return UI.t("Server error %d") % status
