extends Node
## GameState (autoload): the run's world memory, separate from scenes so it survives respawns
## (and, from Phase 10, saves). Phase 5 holds:
## - container contents: rolled once on first search, then remembered (no duplication)
## - item piles in the world: dropped items and death backpacks (they stay until emptied)
## - stats (kills, deaths)

signal container_changed(container_id: StringName)
## A pile appeared or disappeared (the map spawns/removes pile nodes).
signal piles_changed
## Phase 7
signal stash_changed
signal unlocks_changed(unlock_id: StringName)
## Items moved from a container/pile into the bag (objectives like "find 2 medical items in the pharmacy").
signal item_taken(container_id: StringName, item_id: StringName, quantity: int)

var world_seed: int = 0
## False until the first new_game() of this session (the game scene starts one if needed).
var started: bool = false
## container_id -> Array of {"id": StringName, "qty": int}
var containers: Dictionary = {}
## pile_id -> {"position": Vector2, "backpack": bool}
var piles: Dictionary = {}
var stats: Dictionary = {"kills": 0, "deaths": 0}
## Seconds left in the flashlight's battery; -1 = not set yet (the player fills it from PlayerStats).
var flashlight_charge: float = -1.0
## Safehouse stash: item_id -> quantity. Unlimited, never touched by death (GDD §3).
var stash: Dictionary = {}
## Permanent world changes, e.g. &"warehouse_gate", &"radio_repaired". Kept on death.
var unlocks: Array[StringName] = []
## Objective ids completed, in order. Kept on death.
var objectives_completed: Array[StringName] = []
## container_id -> {item_id: quantity taken}. Lets objectives count loot found before they became active.
var taken_log: Dictionary = {}
var day: int = 1

# ---- Night siege (Slice 1) ----
enum Phase { DAY, DUSK, NIGHT }
signal heat_changed(heat: float)
## Where in the day/night cycle we are, and how many seconds into that phase.
var phase: int = Phase.DAY
var phase_time: float = 0.0
## "The town listens": loud noises today raise Heat; tonight's horde grows with it. Resets at dawn.
var heat: float = 0.0
var nights_survived: int = 0
## barricade_id -> remaining health (all planks together). Missing = the start value.
var barricades: Dictionary = {}
## container_id -> how many times it was restocked at dawn (gives each refill its own roll).
var restocks: Dictionary = {}
## Fun pass: this run's score (kills × streak, loot, nights, objectives).
signal score_changed(score: int)
var score: int = 0
## Survivor upgrades/perks crafted at the safehouse workbench using scrap metal.
signal upgrades_changed
var upgrades: Array[StringName] = []
## Tests, bots and tools: no random street spawns, never write your best score.
var street_spawns_disabled: bool = false
var records_disabled: bool = false

var _next_pile: int = 1


func new_game(seed_value: int = -1) -> void:
	world_seed = seed_value if seed_value >= 0 else randi()
	started = true
	containers.clear()
	piles.clear()
	stats = {"kills": 0, "deaths": 0}
	flashlight_charge = -1.0
	stash = {}
	unlocks = []
	objectives_completed = []
	taken_log = {}
	day = 1
	phase = Phase.DAY
	phase_time = 0.0
	heat = 0.0
	nights_survived = 0
	barricades = {}
	restocks = {}
	score = 0
	upgrades.clear()
	_next_pile = 1
	piles_changed.emit()


func is_rolled(container_id: StringName) -> bool:
	return containers.has(container_id)


func get_contents(container_id: StringName) -> Array:
	return containers.get(container_id, [])


## First search: roll the loot table + add guaranteed items, and remember the result.
## Later calls return the remembered contents (never re-rolled).
func roll_container(container_id: StringName, type: StringName, guaranteed: Dictionary) -> Array:
	if containers.has(container_id):
		return containers[container_id]
	var rng := RandomNumberGenerator.new()
	var key: String = str(world_seed) + ":" + String(container_id)
	if restocks.has(container_id):
		key += ":restock%d" % int(restocks[container_id])  # each morning's refill is its own roll
	rng.seed = hash(key)
	var items: Array = []
	var table: LootTable = LootTableRegistry.get_table(type)
	if table != null:
		items = table.roll(rng)
	for id in guaranteed:
		_add_to(items, StringName(id), int(guaranteed[id]))
	containers[container_id] = items
	container_changed.emit(container_id)
	return items


## Moves up to qty of item_id from a container into an inventory. Returns how many moved.
## Whatever doesn't fit stays in the container.
func take_from(container_id: StringName, item_id: StringName, qty: int, inventory: Inventory) -> int:
	var items: Array = get_contents(container_id)
	var available := 0
	for e in items:
		if e.id == item_id:
			available += int(e.qty)
	var want: int = mini(qty, available)
	if want <= 0:
		return 0
	var leftover: int = inventory.add_item(item_id, want)
	var moved: int = want - leftover
	_remove_from(items, item_id, moved)
	if moved > 0:
		var taken: Dictionary = taken_log.get(container_id, {})
		taken[item_id] = int(taken.get(item_id, 0)) + moved
		taken_log[container_id] = taken
	_after_change(container_id)
	if moved > 0:
		item_taken.emit(container_id, item_id, moved)
	return moved


## Takes everything that fits. Returns true if the container is now empty.
func take_all(container_id: StringName, inventory: Inventory) -> bool:
	for e in get_contents(container_id).duplicate():
		take_from(container_id, e.id, int(e.qty), inventory)
	return get_contents(container_id).is_empty()


## Creates a pile (dropped items or a death backpack) and returns its id.
func create_pile(position: Vector2, items: Array, backpack: bool) -> StringName:
	var id := StringName("pile_%d" % _next_pile)
	_next_pile += 1
	var copy: Array = []
	for e in items:
		_add_to(copy, e.id, int(e.qty))
	containers[id] = copy
	piles[id] = {"position": position, "backpack": backpack}
	piles_changed.emit()
	return id


## Adds items to an existing pile/container.
func put_into(container_id: StringName, item_id: StringName, qty: int) -> void:
	var items: Array = containers.get(container_id, [])
	_add_to(items, item_id, qty)
	containers[container_id] = items
	container_changed.emit(container_id)


# ---------------- night siege (Slice 1) ----------------

func add_heat(amount: float) -> void:
	if amount <= 0.0:
		return
	heat += amount
	heat_changed.emit(heat)


func add_score(points: int) -> void:
	if points == 0:
		return
	score += points
	score_changed.emit(score)


func reset_heat() -> void:
	heat = 0.0
	heat_changed.emit(heat)


## Morning refill: these containers forget their (emptied) contents and roll fresh loot when
## searched again. Callers must never pass quest containers (they'd hand out quest items twice).
func restock(container_ids: Array) -> void:
	for id in container_ids:
		var cid := StringName(id)
		if piles.has(cid):
			continue
		restocks[cid] = int(restocks.get(cid, 0)) + 1
		containers.erase(cid)
		container_changed.emit(cid)


# ---------------- stash & unlocks (Phase 7) ----------------

func stash_count(item_id: StringName) -> int:
	return int(stash.get(item_id, 0))


func stash_add(item_id: StringName, qty: int) -> void:
	if qty <= 0:
		return
	stash[item_id] = stash_count(item_id) + qty
	stash_changed.emit()


## Removes up to qty from the stash. Returns how many were removed.
func stash_remove(item_id: StringName, qty: int) -> int:
	var removed: int = mini(qty, stash_count(item_id))
	if removed <= 0:
		return 0
	if removed == stash_count(item_id):
		stash.erase(item_id)
	else:
		stash[item_id] = stash_count(item_id) - removed
	stash_changed.emit()
	return removed


## Bag -> stash. Returns how many moved.
func store_in_stash(inventory: Inventory, item_id: StringName, qty: int) -> int:
	var moved: int = inventory.remove_item(item_id, qty)
	stash_add(item_id, moved)
	return moved


## Stash -> bag; whatever doesn't fit stays in the stash. Returns how many moved.
func take_from_stash(inventory: Inventory, item_id: StringName, qty: int) -> int:
	var want: int = mini(qty, stash_count(item_id))
	if want <= 0:
		return 0
	var moved: int = want - inventory.add_item(item_id, want)
	if moved > 0:
		stash_remove(item_id, moved)
	return moved


func has_unlock(unlock_id: StringName) -> bool:
	return unlocks.has(unlock_id)


func add_unlock(unlock_id: StringName) -> void:
	if unlocks.has(unlock_id):
		return
	unlocks.append(unlock_id)
	unlocks_changed.emit(unlock_id)


## Total of item_id in every container, pile and backpack in the world (not the bag or the stash).
func world_count(item_id: StringName) -> int:
	var total := 0
	for id in containers:
		for e in containers[id]:
			if e.id == item_id:
				total += int(e.qty)
	return total


func backpack_ids() -> Array:
	return piles.keys().filter(func(k: StringName) -> bool: return piles[k].backpack)


func _after_change(container_id: StringName) -> void:
	container_changed.emit(container_id)
	if piles.has(container_id) and get_contents(container_id).is_empty():
		piles.erase(container_id)
		containers.erase(container_id)
		piles_changed.emit()


static func _add_to(items: Array, item_id: StringName, qty: int) -> void:
	if qty <= 0:
		return
	for e in items:
		if e.id == item_id:
			e.qty += qty
			return
	items.append({"id": item_id, "qty": qty})


static func _remove_from(items: Array, item_id: StringName, qty: int) -> void:
	for i in range(items.size() - 1, -1, -1):
		if qty <= 0:
			return
		if items[i].id == item_id:
			var take: int = mini(qty, int(items[i].qty))
			items[i].qty -= take
			qty -= take
			if items[i].qty == 0:
				items.remove_at(i)


# ---------------- saving (Phase 10) ----------------

## Everything in the run's world memory as plain JSON-friendly data (strings, numbers, arrays, dicts).
func to_dict() -> Dictionary:
	var cont := {}
	for id in containers:
		cont[String(id)] = _items_out(containers[id])
	var pl := {}
	for id in piles:
		pl[String(id)] = {"x": piles[id].position.x, "y": piles[id].position.y, "backpack": piles[id].backpack}
	var taken := {}
	for cid in taken_log:
		var row := {}
		for item in taken_log[cid]:
			row[String(item)] = int(taken_log[cid][item])
		taken[String(cid)] = row
	var st := {}
	for id in stash:
		st[String(id)] = int(stash[id])
	return {
		"world_seed": world_seed,
		"containers": cont,
		"piles": pl,
		"next_pile": _next_pile,
		"stats": stats.duplicate(),
		"flashlight_charge": flashlight_charge,
		"stash": st,
		"unlocks": unlocks.map(func(u: StringName) -> String: return String(u)),
		"objectives_completed": objectives_completed.map(func(o: StringName) -> String: return String(o)),
		"taken_log": taken,
		"day": day,
		"phase": phase,
		"phase_time": phase_time,
		"heat": heat,
		"nights_survived": nights_survived,
		"barricades": _string_keys(barricades),
		"restocks": _string_keys(restocks),
		"score": score,
		"upgrades": upgrades.map(func(u: StringName) -> String: return String(u)),
	}


## Restores the world memory from to_dict() data (numbers may come back as floats from JSON).
func from_dict(d: Dictionary) -> void:
	world_seed = int(d.get("world_seed", 0))
	started = true
	containers.clear()
	var cont: Dictionary = d.get("containers", {})
	for id in cont:
		containers[StringName(id)] = _items_in(cont[id])
	piles.clear()
	var pl: Dictionary = d.get("piles", {})
	for id in pl:
		piles[StringName(id)] = {"position": Vector2(float(pl[id].x), float(pl[id].y)), "backpack": bool(pl[id].backpack)}
	_next_pile = int(d.get("next_pile", piles.size() + 1))
	stats = {}
	var st_in: Dictionary = d.get("stats", {})
	for k in st_in:
		stats[k] = st_in[k]
	stats["kills"] = int(stats.get("kills", 0))
	stats["deaths"] = int(stats.get("deaths", 0))
	flashlight_charge = float(d.get("flashlight_charge", -1.0))
	stash.clear()
	var sd: Dictionary = d.get("stash", {})
	for id in sd:
		stash[StringName(id)] = int(sd[id])
	unlocks.clear()
	for u in d.get("unlocks", []):
		unlocks.append(StringName(u))
	objectives_completed.clear()
	for o in d.get("objectives_completed", []):
		objectives_completed.append(StringName(o))
	taken_log.clear()
	var taken_in: Dictionary = d.get("taken_log", {})
	for cid in taken_in:
		var row := {}
		for item in taken_in[cid]:
			row[StringName(item)] = int(taken_in[cid][item])
		taken_log[StringName(cid)] = row
	day = int(d.get("day", 1))
	phase = int(d.get("phase", Phase.DAY))
	phase_time = float(d.get("phase_time", 0.0))
	heat = float(d.get("heat", 0.0))
	nights_survived = int(d.get("nights_survived", maxi(0, day - 1)))
	barricades.clear()
	var bd: Dictionary = d.get("barricades", {})
	for id in bd:
		barricades[StringName(id)] = float(bd[id])
	score = int(d.get("score", 0))
	restocks.clear()
	var rs: Dictionary = d.get("restocks", {})
	for id in rs:
		restocks[StringName(id)] = int(rs[id])
	upgrades.clear()
	for u in d.get("upgrades", []):
		upgrades.append(StringName(u))
	piles_changed.emit()
	stash_changed.emit()
	upgrades_changed.emit()


func has_upgrade(id: StringName) -> bool:
	return upgrades.has(id)


func add_upgrade(id: StringName) -> void:
	if upgrades.has(id):
		return
	upgrades.append(id)
	upgrades_changed.emit()


static func _string_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out


static func _items_out(items: Array) -> Array:
	return items.map(func(e: Dictionary) -> Dictionary: return {"id": String(e.id), "qty": int(e.qty)})


static func _items_in(items: Array) -> Array:
	var out: Array = []
	for e in items:
		if int(e.get("qty", 0)) > 0:
			out.append({"id": StringName(e.id), "qty": int(e.qty)})
	return out


func _exit_tree() -> void:
	# Static data caches hold Resources; release them so shutdown is clean.
	ItemRegistry.clear_cache()
	ObjectiveChain.clear_cache()
	LootTableRegistry.clear_cache()
	QuestGuarantees.clear_cache()
