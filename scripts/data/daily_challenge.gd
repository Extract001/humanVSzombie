class_name DailyChallenge
extends RefCounted
## Batch 2 — the daily challenge: everybody playing on the same date gets the same town (seed)
## and the same twist (modifier). One life: the run ends at the first death. Best score per date
## is kept in Settings.daily_best. It has its own save file, so it never touches your main game.

const SAVE_PATH := "user://save_daily.json"

const NONE: StringName = &"none"
## id -> [title, description]
const MODIFIERS: Dictionary = {
	&"swarm": ["Swarm", "Every horde is 50% bigger."],
	&"glass": ["Glass Bones", "You have 60 health. Every point scores x1.5."],
	&"dark": ["Dead Batteries", "Half the flashlight battery, and the safehouse lamp never works."],
	&"brutes": ["Heavy Hitters", "A Brute joins every horde, from night 1."],
	&"short_days": ["Short Days", "Days are 40% shorter. Less time to scavenge."],
}
const ORDER: Array[StringName] = [&"swarm", &"glass", &"dark", &"brutes", &"short_days"]


## "2026-11-13" (local date).
static func today() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


static func seed_for(date: String) -> int:
	return absi(hash("last_signal_daily:" + date)) % 2000000000


static func modifier_for(date: String) -> StringName:
	return ORDER[absi(hash("daily_mod:" + date)) % ORDER.size()]


static func title(mod: StringName) -> String:
	return MODIFIERS[mod][0] if MODIFIERS.has(mod) else ""


static func description(mod: StringName) -> String:
	return MODIFIERS[mod][1] if MODIFIERS.has(mod) else ""


## The active modifier ("none" outside a daily run).
static func active() -> StringName:
	return GameState.modifier if GameState.mode == &"daily" else NONE


static func is_daily() -> bool:
	return GameState.mode == &"daily"


static func best_today() -> int:
	return int(Settings.daily_best.get(today(), 0))


# ---- effects, read by the systems ----

static func horde_mult() -> float:
	return 1.5 if active() == &"swarm" else 1.0


static func score_mult() -> float:
	return 1.5 if active() == &"glass" else 1.0


static func day_length_mult() -> float:
	return 0.6 if active() == &"short_days" else 1.0


static func lamp_dead() -> bool:
	return active() == &"dark"


static func forced_brutes() -> int:
	return 1 if active() == &"brutes" else 0


static func apply_to_stats(s: PlayerStats) -> void:
	match active():
		&"glass":
			s.max_health = 60.0
			s.respawn_health = 60.0
		&"dark":
			s.flashlight_battery_seconds *= 0.5


## Sets GameState up for today's run (the caller changes scene).
static func begin(date: String = "") -> void:
	if date == "":
		date = today()
	GameState.new_game(seed_for(date))
	GameState.mode = &"daily"
	GameState.daily_date = date
	GameState.modifier = modifier_for(date)
	SaveSystem.path = SAVE_PATH
	SaveSystem.pending_player = {}
	SaveSystem.fresh_start = true


## Records a finished daily run. Returns true if it's a new best for that date.
static func record(score: int) -> bool:
	if GameState.records_disabled or not is_daily():
		return false
	var key: String = GameState.daily_date
	var best: int = int(Settings.daily_best.get(key, 0))
	var new_best: bool = score > best
	if new_best:
		Settings.daily_best[key] = score
	# Keep the last 30 days only.
	var keys: Array = Settings.daily_best.keys()
	keys.sort()
	while keys.size() > 30:
		Settings.daily_best.erase(keys.pop_front())
	Settings.save_settings()
	return new_best
