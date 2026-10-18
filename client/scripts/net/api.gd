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


func post_json(path: String, body: Dictionary = {}) -> Response:
	return await request(HTTPClient.METHOD_POST, path, body)


func patch_json(path: String, body: Dictionary) -> Response:
	return await request(HTTPClient.METHOD_PATCH, path, body)


func request(method: HTTPClient.Method, path: String, body: Variant = null) -> Response:
	var response := Response.new()
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
		if response.data is Dictionary and response.data.has("message"):
			response.error = str(response.data.message)
		else:
			response.error = "Server error %d" % response.status
	return response
