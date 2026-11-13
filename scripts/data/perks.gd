class_name Perks
extends RefCounted
## Slice 2 — perk cards. The pool is data/perks/perk_pool.tres; picks live in GameState.perks
## (id -> stacks, saved). These helpers turn picks into numbers for the systems that use them.
## No static vars here (they keep resources alive at exit); the pool is loaded on demand and cached
## by Godot's resource cache.

const POOL_PATH: String = "res://data/perks/perk_pool.tres"


static func pool() -> Array[PerkData]:
	var list: PerkPool = load(POOL_PATH)
	return list.perks


static func get_perk(id: StringName) -> PerkData:
	for p in pool():
		if p.id == id:
			return p
	return null


static func stacks(id: StringName) -> int:
	return int(GameState.perks.get(id, 0))


## stacks × amount for that perk (0 when not picked).
static func total(id: StringName) -> float:
	var p: PerkData = get_perk(id)
	return 0.0 if p == null else p.amount * stacks(id)


## Up to `count` different perks that can still be picked, in random order.
static func offer(count: int, rng: RandomNumberGenerator = null) -> Array[PerkData]:
	var open: Array[PerkData] = []
	for p in pool():
		if stacks(p.id) < p.max_stacks:
			open.append(p)
	var out: Array[PerkData] = []
	while not open.is_empty() and out.size() < count:
		var i: int = (rng.randi() if rng != null else randi()) % open.size()
		out.append(open[i])
		open.remove_at(i)
	return out


## Multipliers and bonuses used around the code.
static func melee_damage_mult() -> float:
	return 1.0 + total(&"heavy_hands")

static func gun_damage_mult() -> float:
	return 1.0 + total(&"sharpshooter")

static func reload_time_mult() -> float:
	return maxf(0.3, 1.0 - total(&"steady_hands"))

static func search_time_mult() -> float:
	return maxf(0.3, 1.0 - total(&"scavenger"))

static func plank_health_mult() -> float:
	return 1.0 + total(&"carpenter")

static func kill_heal() -> float:
	return total(&"bloodlust")

static func bag_slots_bonus() -> int:
	return roundi(total(&"deep_pockets"))


## Applies the stat perks to a fresh copy of the player's base stats.
static func apply_to_stats(base: PlayerStats) -> PlayerStats:
	var s: PlayerStats = base.duplicate()
	s.run_noise_radius = base.run_noise_radius * maxf(0.2, 1.0 - total(&"quiet_feet"))
	s.max_stamina = base.max_stamina * (1.0 + total(&"iron_lungs"))
	s.regen_per_second = base.regen_per_second * (1.0 + total(&"iron_lungs"))
	s.walk_speed = base.walk_speed * (1.0 + total(&"fleet_foot"))
	s.run_speed = base.run_speed * (1.0 + total(&"fleet_foot"))
	s.max_health = base.max_health + total(&"thick_skin")
	s.flashlight_battery_seconds = base.flashlight_battery_seconds * (1.0 + total(&"night_owl"))
	s.shove_cooldown = base.shove_cooldown * maxf(0.3, 1.0 - total(&"shove_master"))
	s.shove_stagger_time = base.shove_stagger_time * (1.0 + total(&"shove_master"))
	return s


## "Quiet Feet II, Carpenter" for menus.
static func summary() -> String:
	var parts: PackedStringArray = []
	for p in pool():
		var n: int = stacks(p.id)
		if n > 0:
			parts.append(p.title + ("" if n == 1 else " " + "I".repeat(n)))
	return ", ".join(parts) if not parts.is_empty() else "none yet"
