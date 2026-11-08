extends Node
## SaveSystem (autoload): one save slot, JSON, `user://save_v1.json`
## (Windows: %APPDATA%\Godot\app_userdata\LAST SIGNAL\; browser: the site's storage, kept by Godot).
##
## Save points (GDD §3, TECHNICAL_ARCHITECTURE §4.10): sleeping in the bed, walking into the safehouse,
## quitting to the menu from inside the safehouse, and immediately on death (so quitting can't undo a death).
## No saving mid-expedition.
##
## Safety: written to a .tmp file first, then swapped in (the previous save is kept as .bak until the swap
## succeeded). A broken file is never deleted: it is renamed to .broken and the game starts fresh with a message.

signal saved(reason: String)

const VERSION: int = 1
const DEFAULT_PATH := "user://save_v1.json"

var path: String = DEFAULT_PATH
## Player data from the last load, applied by game.gd when the game scene starts (then cleared).
var pending_player: Dictionary = {}
## Set by the main menu's New game: the game scene saves right away, replacing an older save.
var fresh_start: bool = false
var last_save_reason: String = ""
var last_save_unix: int = 0


# ---------------- writing ----------------

## Writes the save. `data` = {"player": {...}, "world": GameState.to_dict(), "game": {...}}.
## Returns OK or an error code (and keeps the previous save if anything fails).
func save_game(data: Dictionary, reason: String) -> Error:
	var doc := data.duplicate(true)
	doc["version"] = VERSION
	doc["saved_at"] = int(Time.get_unix_time_from_system())
	doc["reason"] = reason
	var text: String = JSON.stringify(doc, "\t")
	if OS.has_feature("web"):
		return _save_web(text, reason, int(doc["saved_at"]))
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save failed: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	# Check the temp file really holds what we wrote before replacing the old save.
	if FileAccess.get_file_as_string(tmp) != text:
		push_warning("Save failed: temp file didn't verify")
		return ERR_FILE_CORRUPT
	var bak: String = path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(_abs(bak))
		DirAccess.rename_absolute(_abs(path), _abs(bak))
	var err: Error = DirAccess.rename_absolute(_abs(tmp), _abs(path))
	if err != OK:
		if FileAccess.file_exists(bak):   # put the previous save back
			DirAccess.rename_absolute(_abs(bak), _abs(path))
		push_warning("Save failed: couldn't move the temp file into place (%s)" % error_string(err))
		return err
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(_abs(bak))
	last_save_reason = reason
	last_save_unix = int(doc["saved_at"])
	saved.emit(reason)
	return OK


## In the browser, user:// lives in memory and Godot copies it to the site's storage (IndexedDB) shortly
## after a file is closed. A write in memory can't be half-done by a crash, so one direct write is the safest
## and fastest way there (renames would need extra copy rounds before the save is really stored).
func _save_web(text: String, reason: String, at: int) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	last_save_reason = reason
	last_save_unix = at
	saved.emit(reason)
	return OK


# ---------------- reading ----------------

func has_save() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


## Reads and checks the save. Returns {"ok": bool, "data": Dictionary, "message": String}.
## ok = false with an empty message means "no save". A broken or unusable file gets a message.
func read_save() -> Dictionary:
	var file: String = path
	if not FileAccess.file_exists(file):
		if FileAccess.file_exists(path + ".bak"):  # a save was interrupted after the old one was moved aside
			file = path + ".bak"
		else:
			return {"ok": false, "data": {}, "message": ""}
	var text: String = FileAccess.get_file_as_string(file)
	var parsed: Variant = null
	var json := JSON.new()   # (JSON.parse_string would print an engine error for a damaged file)
	if text.strip_edges() != "" and json.parse(text) == OK:
		parsed = json.data
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("version"):
		return {"ok": false, "data": {}, "message": "The saved game couldn't be read (the file is damaged or empty).", "broken": true}
	var data: Dictionary = parsed
	var version: int = int(data.get("version", 0))
	if version > VERSION:
		return {"ok": false, "data": {}, "message": "This save was made by a newer version of the game (save version %d)." % version,
			"newer": true}
	data = migrate(data)
	if not (data.get("world") is Dictionary) or not (data.get("player") is Dictionary):
		return {"ok": false, "data": {}, "message": "The saved game is incomplete and couldn't be loaded.", "broken": true}
	return {"ok": true, "data": data, "message": ""}


## Upgrades older save formats step by step to the current VERSION.
## Version 0 (pre-release test format): no "day", no "flashlight_charge", world fields at the top level.
static func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	if int(d.get("version", 0)) == 0:
		if not d.has("world"):
			var world := {}
			for k in ["world_seed", "containers", "piles", "stats", "stash", "unlocks", "objectives_completed", "taken_log"]:
				if d.has(k):
					world[k] = d[k]
					d.erase(k)
			d["world"] = world
		d["world"]["day"] = int(d["world"].get("day", 1))
		d["world"]["flashlight_charge"] = float(d["world"].get("flashlight_charge", -1.0))
		d["version"] = 1
	return d


## Loads the save into GameState and keeps the player part for game.gd. Returns read_save()'s result.
## A damaged file is renamed to .broken (kept for inspection) so the menu doesn't offer it again.
func load_game() -> Dictionary:
	var r: Dictionary = read_save()
	if not r.ok:
		if r.get("broken", false):
			set_aside_broken()
		return r
	GameState.from_dict(r.data.world)
	pending_player = r.data.player.duplicate(true)
	pending_player["game"] = r.data.get("game", {})
	return r


func set_aside_broken() -> void:
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			var target: String = f + ".broken"
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(_abs(target))
			DirAccess.rename_absolute(_abs(f), _abs(target))


## Short description for the menu, e.g. "Day 3 - saved in the safehouse".
func describe() -> String:
	var r: Dictionary = read_save()
	if not r.ok:
		return ""
	var where: String = {"death": "after dying", "bed": "after sleeping", "safehouse": "in the safehouse",
		"menu": "in the safehouse"}.get(String(r.data.get("reason", "")), "")
	return "Day %d%s" % [int(r.data.world.get("day", 1)), (" - saved " + where) if where != "" else ""]


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)
