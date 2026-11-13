class_name Characters
extends RefCounted
## Batch 2 — playable characters, unlocked between runs (kept in Settings, not in the save).
## Each one changes a few PlayerStats numbers, starts with a little gear and has its own colours.
## GameState.character holds the pick for the current run (saved); Settings.selected_character is
## the menu choice for the next run.
## No static vars here (see Perks): the table is a const.

const ROOK: StringName = &"rook"

## id -> {name, role, blurb, tint, unlock (text), gear {item: qty}}
const LIST: Dictionary = {
	&"rook": {
		"name": "Rook", "role": "Courier",
		"blurb": "Steady all-rounder. No weak spots, no tricks.",
		"tint": Color(1, 1, 1), "unlock": "", "gear": {},
	},
	&"mara": {
		"name": "Mara", "role": "Nurse",
		"blurb": "Starts with a medkit and 2 bandages. Wakes up at full health after a death.",
		"tint": Color(1.0, 0.86, 0.9), "unlock": "Survive 3 nights in one run",
		"gear": {&"medkit": 1, &"bandage": 2},
	},
	&"dex": {
		"name": "Dex", "role": "Bouncer",
		"blurb": "+30 health, shoves hit harder and recover faster. A little slower on his feet.",
		"tint": Color(0.86, 0.93, 1.0), "unlock": "Kill 150 zombies (all runs together)",
		"gear": {},
	},
	&"kit": {
		"name": "Kit", "role": "Runner",
		"blurb": "Fast and quiet, more stamina. Only 80 health.",
		"tint": Color(0.9, 1.0, 0.86), "unlock": "Score 2500 in one run",
		"gear": {&"water_bottle": 1},
	},
	&"sol": {
		"name": "Sol", "role": "Carpenter",
		"blurb": "Planks he nails are 30% tougher. Starts with 4 scrap.",
		"tint": Color(1.0, 0.94, 0.8), "unlock": "Rescue 3 survivors (all runs together)",
		"gear": {&"scrap": 4},
	},
}

const ORDER: Array[StringName] = [&"rook", &"mara", &"dex", &"kit", &"sol"]


static func info(id: StringName) -> Dictionary:
	return LIST.get(id, LIST[ROOK])


static func display_name(id: StringName) -> String:
	return "%s the %s" % [info(id).name, info(id).role]


static func tint(id: StringName) -> Color:
	return info(id).tint


## Is this character playable? Reads the lifetime records in Settings.
static func is_unlocked(id: StringName) -> bool:
	match id:
		&"rook":
			return true
		&"mara":
			return Settings.best_nights >= 3
		&"dex":
			return Settings.lifetime_kills >= 150
		&"kit":
			return Settings.best_score >= 2500
		&"sol":
			return Settings.lifetime_rescued >= 3
	return false


static func unlocked_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ORDER:
		if is_unlocked(id):
			out.append(id)
	return out


## "Survive 3 nights in one run (best 1)": what's still needed, for the menu.
static func progress_text(id: StringName) -> String:
	match id:
		&"mara":
			return "%s (best %d)" % [info(id).unlock, Settings.best_nights]
		&"dex":
			return "%s (%d so far)" % [info(id).unlock, Settings.lifetime_kills]
		&"kit":
			return "%s (best %d)" % [info(id).unlock, Settings.best_score]
		&"sol":
			return "%s (%d so far)" % [info(id).unlock, Settings.lifetime_rescued]
	return ""


## The character's changes to a copy of the base stats (perks are applied on top).
static func apply(id: StringName, base: PlayerStats) -> PlayerStats:
	var s: PlayerStats = base.duplicate()
	match id:
		&"mara":
			s.respawn_health = s.max_health
		&"dex":
			s.max_health = base.max_health + 30.0
			s.shove_knockback_speed = base.shove_knockback_speed * 1.4
			s.shove_cooldown = base.shove_cooldown * 0.75
			s.shove_damage = base.shove_damage * 3.0
			s.walk_speed = base.walk_speed * 0.92
			s.run_speed = base.run_speed * 0.92
		&"kit":
			s.max_health = base.max_health - 20.0
			s.respawn_health = minf(base.respawn_health, s.max_health)
			s.walk_speed = base.walk_speed * 1.12
			s.run_speed = base.run_speed * 1.12
			s.run_noise_radius = base.run_noise_radius * 0.7
			s.max_stamina = base.max_stamina * 1.25
	return s


## Barricade planks (Sol).
static func plank_health_mult(id: StringName) -> float:
	return 1.3 if id == &"sol" else 1.0
