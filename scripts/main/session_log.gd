class_name SessionLog
extends Node
## Batch 2 — playtest log (Settings.playtest_mode, on by default in this early build). Nothing is
## sent anywhere: two local files in the game's user folder
## (Windows: %APPDATA%\Godot\app_userdata\LAST SIGNAL\):
## - playtest_log.csv: one row per event (run start, deaths and what killed you, nights, rescues,
##   ratings...) plus one "minute" row every 60 s of play (kills that minute, metres walked, where).
##   Opens in Excel / Google Sheets.
## - playtest_summary.txt: a short readable block per session (length, deaths, nights reached,
##   quiet minutes = minutes with no kills and little walking, rating).
## See documentation/PLAYTEST_GUIDE.md.

const CSV_PATH := "user://playtest_log.csv"
const SUMMARY_PATH := "user://playtest_summary.txt"
const HEADER := "session,time,clock_s,mode,character,event,day,phase,night_event,score,kills,hp,x,y,detail"
## A minute counts as "quiet" (possibly boring) with no kill and less than this many metres walked.
const QUIET_METRES: float = 40.0

## Tests point these at their own files.
var csv_path: String = CSV_PATH
var summary_path: String = SUMMARY_PATH
var game: Node
var player: Player
var session_id: String = ""
var enabled: bool = false
var _clock: float = 0.0
var _minute_timer: float = 0.0
var _minute_kills: int = 0
var _minute_dist: float = 0.0
var _last_pos: Vector2 = Vector2.INF
var _deaths: Array[String] = []
var _quiet_minutes: int = 0
var _minutes: int = 0
var _rating: int = 0
var _start_score: int = 0
var _start_day: int = 1
var _rescued: int = 0
var _last_damage_source: String = "-"
var _written_summary: bool = false


func setup(game_root: Node, p: Player) -> void:
	game = game_root
	player = p
	enabled = Settings.playtest_mode and not GameState.records_disabled
	add_to_group(&"session_log")
	add_to_group(&"score_listeners")
	if not enabled:
		return
	session_id = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	_start_score = GameState.score
	_start_day = GameState.day
	player.health.damaged.connect(func(_a: float, src: Node) -> void:
		_last_damage_source = _describe(src))
	player.died.connect(_on_died)
	game.day_cycle.phase_changed.connect(func(ph: int) -> void:
		log_event(["day", "dusk", "night"][clampi(ph, 0, 2)], String(GameState.night_event) if ph != 0 else ""))
	game.objectives.objective_completed.connect(func(o: ObjectiveData) -> void: log_event("objective", String(o.id)))
	GameState.perks_changed.connect(func() -> void: log_event("perk", ",".join(GameState.perks.keys().map(func(k): return String(k)))))
	log_event("session_start", "continue" if not SaveSystem.fresh_start else "new_run")


func _describe(src: Node) -> String:
	if src is Zombie:
		var z := src as Zombie
		return String(z.data.id) if z.data != null else "zombie"
	return src.name if src != null else "-"


func _process(delta: float) -> void:
	if not enabled or player == null:
		return
	if get_tree().paused or player.is_dead():
		return
	_clock += delta
	if _last_pos != Vector2.INF:
		_minute_dist += player.global_position.distance_to(_last_pos)
	_last_pos = player.global_position
	_minute_timer += delta
	if _minute_timer >= 60.0:
		_minute_timer = 0.0
		_minutes += 1
		var metres: float = _minute_dist / 16.0
		var quiet: bool = _minute_kills == 0 and metres < QUIET_METRES
		if quiet:
			_quiet_minutes += 1
		log_event("minute", "kills=%d metres=%d%s%s" % [_minute_kills, int(metres),
			" quiet" if quiet else "", " in_safehouse" if game.is_in_safehouse() else ""])
		_minute_kills = 0
		_minute_dist = 0.0


func on_zombie_killed(_z: Zombie) -> void:
	_minute_kills += 1


func _on_died() -> void:
	_deaths.append("day %d %s, by %s" % [GameState.day, ["day", "dusk", "night"][clampi(GameState.phase, 0, 2)], _last_damage_source])
	log_event("death", _last_damage_source)


func rate(stars: int) -> void:
	_rating = clampi(stars, 1, 5)
	log_event("rating", str(_rating))


## One CSV row. Commas in `detail` are replaced so the file stays a clean table.
func log_event(event: String, detail: String = "") -> void:
	if not enabled:
		return
	if event == "survivor_rescued":
		_rescued += 1
	var ok: bool = player != null and is_instance_valid(player)
	var hp: int = int(player.health.current_health) if ok else 0
	var pos: Vector2 = player.global_position if ok else Vector2.ZERO
	var row: PackedStringArray = [session_id, Time.get_time_string_from_system(), str(int(_clock)),
		String(GameState.mode), String(GameState.character), event, str(GameState.day),
		["day", "dusk", "night"][clampi(GameState.phase, 0, 2)], String(GameState.night_event),
		str(GameState.score), str(int(GameState.stats.get("kills", 0))), str(hp),
		str(int(pos.x / 16.0)), str(int(pos.y / 16.0)), detail.replace(",", ";").replace("\n", " ")]
	_append(csv_path, ",".join(row), HEADER)


func _append(path: String, line: String, header: String = "") -> void:
	var exists: bool = FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	if not exists and header != "":
		f.store_line(header)
	f.store_line(line)
	f.close()


## The readable summary block, written once when the session ends (menu, quit, scene change).
func write_summary(reason: String) -> void:
	if not enabled or _written_summary:
		return
	_written_summary = true
	log_event("session_end", reason)
	var lines: PackedStringArray = [
		"=== Session %s (%s) ===" % [session_id, reason],
		"Played: %d min %02d s   Mode: %s%s   Character: %s" % [int(_clock) / 60, int(_clock) % 60, String(GameState.mode),
			(" " + GameState.daily_date + " / " + DailyChallenge.title(GameState.modifier)) if GameState.mode == &"daily" else "",
			Characters.display_name(GameState.character)],
		"Day %d -> %d   Nights survived: %d   Score %d -> %d   Kills: %d   Survivors rescued this session: %d" % [
			_start_day, GameState.day, GameState.nights_survived, _start_score, GameState.score,
			int(GameState.stats.get("kills", 0)), _rescued],
		"Deaths: %d%s" % [_deaths.size(), "" if _deaths.is_empty() else "  (" + "; ".join(_deaths) + ")"],
		"Quiet minutes (no kills, little walking): %d of %d" % [_quiet_minutes, _minutes],
		"Fun rating: %s" % (str(_rating) + "/5" if _rating > 0 else "not given"),
		"",
	]
	_append(summary_path, "\n".join(lines))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		write_summary("closed the game")


func _exit_tree() -> void:
	write_summary("left the game screen")
