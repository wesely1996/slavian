extends Node
## Updates the app in place (autoload `Updater`): downloads the newer
## release's own file (GET /v1/release `assets`) into user://updates, then
## - Android: hands the APK to the system installer (one tap on Install;
##   the first time Android asks to allow installs from Slavian);
## - Windows: unpacks Slavian.exe beside the running one, quits, and a
##   hidden PowerShell swaps the new exe in and starts it.
## On every start it clears what earlier updates left behind: downloads in
## user://updates, a half-swapped exe, and old Slavian APKs and Windows zips
## in the Downloads folder (where the system lets it).

signal progress(done: int, total: int)

const DIR := "user://updates"
## The Windows build's zip holds this file (ops/export-windows.sh).
const EXE_IN_ZIP := "Slavian.exe"

var busy := false


func _ready() -> void:
	clean_up()


## Whether this build can update itself (an exported Android or Windows app).
func can_update() -> bool:
	if OS.has_feature("editor"):
		return false
	return OS.has_feature("android") or OS.has_feature("windows")


## The file of `release` (GET /v1/release) for this platform, or "".
func asset_url(release: Dictionary) -> String:
	var assets: Variant = release.get("assets")
	if not assets is Dictionary:
		return ""
	if OS.has_feature("android"):
		return String(assets.get("android", ""))
	if OS.has_feature("windows"):
		return String(assets.get("windows", ""))
	return ""


## Downloads and installs `release`: "" once the installer is open or the
## app restarts, else what went wrong.
func update(release: Dictionary) -> String:
	if busy:
		return tr("An update is already on its way.")
	var url := asset_url(release)
	if not can_update() or url == "":
		return tr("This app can't update itself; download the new version instead.")
	busy = true
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join(url.get_file())
	var error := await _download(url, path)
	if error == "":
		error = _install_android(path) if OS.has_feature("android") else _install_windows(path)
	busy = false
	return error


func _download(url: String, path: String) -> String:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.download_chunk_size = 1 << 16
	request.max_redirects = 8
	request.download_file = path + ".part"
	add_child(request)
	var watch := Timer.new()
	watch.wait_time = 0.25
	watch.timeout.connect(func() -> void: progress.emit(request.get_downloaded_bytes(), request.get_body_size()))
	add_child(watch)
	watch.start()
	if request.request(url) != OK:
		watch.queue_free()
		request.queue_free()
		return tr("The download could not start.")
	var answer: Array = await request.request_completed
	watch.queue_free()
	request.queue_free()
	var result := int(answer[0])
	var code := int(answer[1])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(path + ".part")
		return tr("The download failed (%s). Check the connection and try again.") % (str(code) if code != 0 else str(result))
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path + ".part", path)
	progress.emit(1, 1)
	return ""


## The system installer takes the APK from the app's own files (Godot's
## FileProvider); the APK is cleared on the next start.
func _install_android(path: String) -> String:
	if OS.shell_open(ProjectSettings.globalize_path(path)) != OK:
		return tr("The installer did not open. Allow Slavian to install apps in the phone's settings, then try again.")
	return ""


## Slavian.exe from the zip goes beside the running one as Slavian.new.exe;
## once this app has quit, PowerShell moves it over the old one and starts it.
func _install_windows(path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return tr("The download is damaged; try again.")
	var bytes := zip.read_file(EXE_IN_ZIP)
	zip.close()
	if bytes.is_empty():
		return tr("The download is damaged; try again.")
	var exe := OS.get_executable_path()
	var fresh := _new_exe(exe)
	var file := FileAccess.open(fresh, FileAccess.WRITE)
	if file == null:
		return tr("The game's folder can't be written to; download the new version instead.")
	file.store_buffer(bytes)
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var quote := func(text: String) -> String: return "'" + text.replace("'", "''") + "'"
	var script := "Wait-Process -Id %d -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500; Move-Item -Force -LiteralPath %s -Destination %s; Start-Process -FilePath %s" % [
		OS.get_process_id(), quote.call(fresh), quote.call(exe), quote.call(exe)]
	if OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", script]) <= 0:
		DirAccess.remove_absolute(fresh)
		return tr("The update could not be started; download the new version instead.")
	get_tree().quit()
	return ""


static func _new_exe(exe: String) -> String:
	return exe.get_base_dir().path_join(exe.get_file().get_basename() + ".new.exe")


## What earlier updates and downloads left behind.
func clean_up() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for file in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(file))
	if OS.has_feature("editor"):
		return
	if OS.has_feature("windows"):
		var fresh := _new_exe(OS.get_executable_path())
		if FileAccess.file_exists(fresh):
			DirAccess.remove_absolute(fresh)
	var current := String(ProjectSettings.get_setting("application/config/version", ""))
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads == "" or not DirAccess.dir_exists_absolute(downloads):
		return
	for file in DirAccess.get_files_at(downloads):
		var version := old_download_version(file)
		if version != "" and not _newer(version, current):
			DirAccess.remove_absolute(downloads.path_join(file))


## The version of an old Slavian download ("slavian-0.23.2.apk",
## "slavian-0.23.2-windows.zip", and the browser's "slavian-0.23.2 (1).apk"),
## or "" for any other file.
static func old_download_version(file: String) -> String:
	var pattern := RegEx.create_from_string("^slavian-(\\d+\\.\\d+\\.\\d+)(-windows)?( \\(\\d+\\))?\\.(apk|zip)$")
	var found := pattern.search(file.to_lower())
	if found == null:
		return ""
	var zip := found.get_string(4) == "zip"
	var windows := found.get_string(2) != ""
	return found.get_string(1) if zip == windows else ""


## Whether version `a` comes after `b`, part by part.
static func _newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false
