class_name Survivors
extends Node
## Batch 2 — survivors with jobs. One new survivor gets on the radio each morning from day 2
## (a banner, a green SURVIVOR arrow, a few zombies nearby). Find them, press E, walk them home.
## At home they work:
## - Tomas, Mechanic: at dusk nails one free plank on every window that isn't full; planks +25%.
## - Amara, Doctor: every dawn heals you fully and leaves a bandage in the stash.
## - Pip, Scavenger: every dawn brings 3 things back to the stash.
## - Hale, Guard: at night shoots zombies near the safehouse (every few seconds).
## They can die: each window broken during the night gives a 30% chance (15% with Hale) that the
## horde gets someone (at most one a night). GameState.survivors: id -> "home" / "dead" (saved).

signal changed

const NPC_SCRIPT: Script = preload("res://scripts/world/survivor_npc.gd")
const WALKER: PackedScene = preload("res://scenes/zombies/walker.tscn")
const GUN: AudioStream = preload("res://assets/audio/sfx/pistol_shot.wav")
const RESCUE_POINTS: int = 150
const GUARD_RANGE: float = 210.0
const GUARD_INTERVAL: float = 2.6
const GUARD_DAMAGE: float = 30.0
const LOSS_CHANCE: float = 0.3
## Tiles inside the safehouse: x 71-85, y 65-77.
const SAFEHOUSE_CENTRE := Vector2(78.5, 71.5) * 16.0
const SAFEHOUSE_RECT := Rect2(71 * 16, 65 * 16, 15 * 16, 13 * 16)

## id -> data. day = first morning they're on the radio; site / home in tiles.
const LIST: Dictionary = {
	&"tomas": {"name": "Tomas", "job": "Mechanic", "day": 2, "site": Vector2(118, 70), "home": Vector2(73, 74),
		"where": "a house on the east side", "tint": Color(0.82, 0.9, 1.0), "scale": 1.0,
		"short": "one free plank per window at dusk, planks +25%",
		"line_call": "Hey! Over here!", "line_join": "Let's go. Quietly.", "line_home": "Windows hold. Mostly."},
	&"amara": {"name": "Amara", "job": "Doctor", "day": 3, "site": Vector2(17, 40), "home": Vector2(81, 68),
		"where": "the pharmacy, west", "tint": Color(1.0, 0.92, 0.95), "scale": 0.95,
		"short": "full heal and a bandage every dawn",
		"line_call": "I'm a doctor! Get me out!", "line_join": "Right behind you.", "line_home": "Sit. Let me look at that."},
	&"pip": {"name": "Pip", "job": "Scavenger", "day": 4, "site": Vector2(62, 42), "home": Vector2(75, 76),
		"where": "the grocery store", "tint": Color(1.0, 1.0, 0.82), "scale": 0.8,
		"short": "brings 3 finds to the stash every dawn",
		"line_call": "Psst! Mister! Up here!", "line_join": "I know shortcuts!", "line_home": "Found you something!"},
	&"hale": {"name": "Hale", "job": "Guard", "day": 5, "site": Vector2(114, 9), "home": Vector2(83, 72),
		"where": "the checkpoint booth, north-east", "tint": Color(0.88, 1.0, 0.86), "scale": 1.05,
		"short": "shoots zombies near the safehouse at night",
		"line_call": "Took you long enough.", "line_join": "Move. I'll cover you.", "line_home": "I've got the windows."},
}
const ORDER: Array[StringName] = [&"tomas", &"amara", &"pip", &"hale"]
## What Pip brings back (item, quantity), drawn 3 times every dawn.
const FINDS: Array = [[&"scrap", 2], [&"ammo_pistol", 6], [&"bandage", 1], [&"battery", 1], [&"food_can", 1],
	[&"scrap", 1], [&"ammo_shotgun", 2], [&"water_bottle", 1]]

var game: Node
var player: Player
var actors: Node2D
var npcs: Dictionary = {}
var _guard_cd: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(game_root: Node, p: Player, actors_root: Node2D) -> void:
	game = game_root
	player = p
	actors = actors_root
	game.day_cycle.phase_changed.connect(_on_phase_changed)
	player.died.connect(func() -> void:
		for n in npcs.values():
			(n as SurvivorNPC).stop_following())
	_spawn_known()


static func info(id: StringName) -> Dictionary:
	return LIST.get(id, {})


static func is_home(id: StringName) -> bool:
	return GameState.survivors.get(id, "") == "home"


static func home_count() -> int:
	var n := 0
	for id in GameState.survivors:
		if GameState.survivors[id] == "home":
			n += 1
	return n


## Barricade planks (Tomas).
static func plank_health_mult() -> float:
	return 1.25 if is_home(&"tomas") else 1.0


## Survivors who are on the radio by now and not rescued or dead yet.
static func waiting_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ORDER:
		if int(LIST[id].day) <= GameState.day and not GameState.survivors.has(id):
			out.append(id)
	return out


## Puts the NPCs in the world: waiting ones at their site, rescued ones at home.
func _spawn_known() -> void:
	for id in ORDER:
		var st: String = GameState.survivors.get(id, "")
		if st == "home":
			_make_npc(id, SurvivorNPC.Mode.HOME, (LIST[id].home + Vector2(0.5, 0.5)) * 16.0)
		elif st == "" and int(LIST[id].day) <= GameState.day:
			_make_npc(id, SurvivorNPC.Mode.WAITING, _site(id))


func _make_npc(id: StringName, mode: int, at: Vector2) -> SurvivorNPC:
	if npcs.has(id) and is_instance_valid(npcs[id]):
		return npcs[id]
	var npc := SurvivorNPC.new()
	npc.setup(id, LIST[id], player, mode)
	npc.position = at
	actors.add_child(npc)
	npcs[id] = npc
	return npc


func _site(id: StringName) -> Vector2:
	var at: Vector2 = (LIST[id].site + Vector2(0.5, 0.5)) * 16.0
	var map: RID = player.get_world_2d().navigation_map
	return _on_mesh(map, at)


## The closest walkable point (or the point itself while the navigation mesh isn't ready).
static func _on_mesh(map: RID, at: Vector2) -> Vector2:
	if NavigationServer2D.map_get_iteration_id(map) > 0:
		var p: Vector2 = NavigationServer2D.map_get_closest_point(map, at)
		if p != Vector2.ZERO and p.distance_to(at) < 120.0:
			return p
	return at


func _physics_process(delta: float) -> void:
	for id in npcs.keys():
		var npc: SurvivorNPC = npcs[id]
		if not is_instance_valid(npc):
			npcs.erase(id)
			continue
		if npc.mode == SurvivorNPC.Mode.FOLLOWING and SAFEHOUSE_RECT.has_point(npc.global_position) \
				and SAFEHOUSE_RECT.has_point(player.global_position):
			rescue(id)
	if GameState.phase == GameState.Phase.NIGHT and is_home(&"hale"):
		_guard_cd -= delta
		if _guard_cd <= 0.0:
			_guard_cd = GUARD_INTERVAL
			guard_shoot()


## Walks a following survivor into the safehouse for good.
func rescue(id: StringName) -> void:
	if GameState.survivors.has(id):
		return
	GameState.survivors[id] = "home"
	var npc: SurvivorNPC = npcs.get(id)
	if npc != null:
		npc.go_home()
	GameState.add_score(RESCUE_POINTS)
	Juice.popup(game.world, player.global_position + Vector2(0, -14), "+%d RESCUED" % RESCUE_POINTS, Color(0.6, 1.0, 0.7), 10)
	AudioManager.play_ui(preload("res://assets/audio/sfx/streak.wav"), -2.0)
	get_tree().call_group(&"hud", &"show_banner", "%s IS SAFE" % String(LIST[id].name).to_upper(),
		"%s: %s." % [LIST[id].job, LIST[id].short])
	if not GameState.records_disabled:
		Settings.lifetime_rescued += 1
		Settings.save_settings()
	get_tree().call_group(&"session_log", &"log_event", "survivor_rescued", String(id))
	GameState.survivors_changed.emit()
	changed.emit()
	if game.has_method(&"save_now"):
		game.save_now("rescue")


## HUD: the green arrow to the nearest waiting survivor (or home while one is following you).
func target() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for id in npcs:
		var npc: SurvivorNPC = npcs[id]
		if not is_instance_valid(npc):
			continue
		if npc.mode == SurvivorNPC.Mode.FOLLOWING:
			return {"pos": Vector2(78.5, 66.5) * 16.0, "label": "BRING %s HOME" % String(npc.info.name).to_upper()}
		if npc.mode == SurvivorNPC.Mode.WAITING:
			var d: float = npc.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = {"pos": npc.global_position, "label": "SURVIVOR"}
	return best


func following() -> SurvivorNPC:
	for npc in npcs.values():
		if is_instance_valid(npc) and npc.mode == SurvivorNPC.Mode.FOLLOWING:
			return npc
	return null


# ---------------- the jobs ----------------

func _on_phase_changed(phase: int) -> void:
	if phase == GameState.Phase.DUSK and is_home(&"tomas"):
		var fixed := 0
		for b in get_tree().get_nodes_in_group(&"barricades"):
			if (b as Barricade).add_plank():
				fixed += 1
		if fixed > 0:
			get_tree().call_group(&"hud", &"show_toast", "Tomas nailed %d more plank%s up." % [fixed, "" if fixed == 1 else "s"])
	if phase == GameState.Phase.NIGHT:
		_guard_cd = GUARD_INTERVAL


## Hale: one shot at the nearest zombie close to the safehouse. Returns the zombie hit (or null).
func guard_shoot() -> Zombie:
	var npc: SurvivorNPC = npcs.get(&"hale")
	var from: Vector2 = npc.global_position if npc != null and is_instance_valid(npc) else SAFEHOUSE_CENTRE
	var target_z: Zombie = null
	var best: float = GUARD_RANGE
	for z in get_tree().get_nodes_in_group(&"zombies"):
		var zz := z as Zombie
		if zz == null or zz.state == Zombie.State.DEAD:
			continue
		var d: float = zz.global_position.distance_to(SAFEHOUSE_CENTRE)
		if d < best:
			best = d
			target_z = zz
	if target_z == null:
		return null
	var hb: Hurtbox = target_z.get_node_or_null("Hurtbox")
	if hb == null:
		return null
	AudioManager.play_at(GUN, from, -6.0, 0.08)
	Fx.burst(game.world, from + from.direction_to(target_z.global_position) * 8.0 + Vector2(0, -10),
		Color(1.0, 0.85, 0.4), 4, 60.0, from.direction_to(target_z.global_position))
	hb.receive_hit(GUARD_DAMAGE, npc if npc != null else null, from.direction_to(target_z.global_position) * 80.0, 0.2)
	return target_z


## Called by the game at dawn (before the summary): losses first, then the morning jobs.
## Returns lines for the dawn summary.
func on_dawn(summary: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	_rng.seed = hash("%d:losses%d" % [GameState.world_seed, GameState.nights_survived])
	var breaches: int = int(summary.get("breaches", 0))
	var home: Array[StringName] = []
	for id in ORDER:
		if is_home(id):
			home.append(id)
	if breaches > 0 and not home.is_empty():
		var chance: float = minf(0.75, LOSS_CHANCE * breaches) * (0.5 if is_home(&"hale") else 1.0)
		if _rng.randf() < chance:
			var lost: StringName = home[_rng.randi() % home.size()]
			GameState.survivors[lost] = "dead"
			home.erase(lost)
			lines.append("They broke in. %s the %s didn't make it." % [LIST[lost].name, String(LIST[lost].job).to_lower()])
			var npc: SurvivorNPC = npcs.get(lost)
			if npc != null and is_instance_valid(npc):
				npc.queue_free()
			npcs.erase(lost)
			get_tree().call_group(&"session_log", &"log_event", "survivor_lost", String(lost))
	if is_home(&"amara") and player != null and not player.is_dead():
		player.health.heal(player.health.max_health)
		GameState.stash_add(&"bandage", 1)
		lines.append("Amara patched you up (full health, +1 bandage in the stash).")
	if is_home(&"pip"):
		var got: PackedStringArray = []
		for i in 3:
			var f: Array = FINDS[_rng.randi() % FINDS.size()]
			GameState.stash_add(f[0], int(f[1]))
			var item: ItemData = ItemRegistry.get_item(f[0])
			got.append("%d %s" % [int(f[1]), item.display_name if item != null else String(f[0])])
		lines.append("Pip brought back: %s (in the stash)." % ", ".join(got))
	# Who's on the radio this morning?
	for id in ORDER:
		if int(LIST[id].day) == GameState.day and not GameState.survivors.has(id):
			_announce(id)
			lines.append("On the radio: %s, a %s, is trapped in %s." % [LIST[id].name, String(LIST[id].job).to_lower(), LIST[id].where])
	GameState.survivors_changed.emit()
	changed.emit()
	return lines


func _announce(id: StringName) -> void:
	var at: Vector2 = _site(id)
	_make_npc(id, SurvivorNPC.Mode.WAITING, at)
	# A few of them already sniffing around.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:surv%s" % [GameState.world_seed, String(id)])
	var map: RID = player.get_world_2d().navigation_map
	for i in 2 + mini(2, GameState.day / 3):
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 110.0)
		var pos: Vector2 = at + off
		pos = _on_mesh(map, pos)
		var z: Zombie = WALKER.instantiate()
		z.position = pos
		actors.add_child(z)
		z.add_to_group(&"population")
	# The banner waits for the morning's other news (the HUD queues banners).
	get_tree().call_group(&"hud", &"show_banner", "SURVIVOR ON THE RADIO",
		"%s the %s is trapped in %s. Follow the green arrow." % [LIST[id].name, String(LIST[id].job).to_lower(), LIST[id].where])
