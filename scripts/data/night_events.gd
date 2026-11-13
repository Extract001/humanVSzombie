class_name NightEvents
extends RefCounted
## Batch 1 — a special event most nights, announced at dusk ("TONIGHT: BRUTE NIGHT").
## Night 1 is always calm; from night 2 one is drawn at dusk, never the same as last night's.
## GameState.night_event holds tonight's id (saved).

const NONE := &"none"
const BRUTES := &"brutes"
const SCREAMERS := &"screamers"
const FOG := &"fog"
const BLACKOUT := &"blackout"
const BLOOD_MOON := &"blood_moon"

## id: [title, what it means, weight]
const INFO: Dictionary = {
	&"brutes": ["BRUTE NIGHT", "Brutes smash planks in one hit and burst doors open.", 3.0],
	&"screamers": ["SCREAMERS", "When a Screamer sees you, every zombie nearby comes running.", 3.0],
	&"fog": ["FOG", "Thick fog. More of them, and the fast ones lead.", 2.0],
	&"blackout": ["BLACKOUT", "The safehouse lamp is dead. Keep your flashlight charged.", 2.0],
	&"blood_moon": ["BLOOD MOON", "A bigger horde. Every kill tonight scores double.", 1.5],
	&"none": ["A QUIET NIGHT", "Just the usual horde.", 1.0],
}


static func title(id: StringName) -> String:
	return INFO[id][0] if INFO.has(id) else ""


static func description(id: StringName) -> String:
	return INFO[id][1] if INFO.has(id) else ""


## Draws tonight's event (deterministic per world seed and night, so a daily run is the same for everyone).
static func pick(night: int, last: StringName, world_seed: int) -> StringName:
	if night <= 1:
		return NONE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:night%d" % [world_seed, night])
	var ids: Array = []
	var total := 0.0
	for id in INFO:
		if id == last or (night == 2 and id == NONE):
			continue
		ids.append(id)
		total += float(INFO[id][2])
	var r: float = rng.randf() * total
	for id in ids:
		r -= float(INFO[id][2])
		if r <= 0.0:
			return id
	return ids[-1]


## Horde size multiplier for the event.
static func horde_mult(id: StringName) -> float:
	match id:
		FOG: return 1.25
		BLOOD_MOON: return 1.5
	return 1.0


## Night colour override (null-free: returns `normal` when the event doesn't change it).
static func night_tint(id: StringName, normal: Color) -> Color:
	match id:
		FOG: return Color(0.42, 0.44, 0.48)
		BLACKOUT: return Color(0.17, 0.19, 0.3)
		BLOOD_MOON: return Color(0.55, 0.22, 0.22)
	return normal
