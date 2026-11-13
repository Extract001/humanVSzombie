class_name SupplyDrops
extends Node
## Batch 1 — a supply crate comes down somewhere in town every morning from day 2: a red flare and
## smoke mark it, a yellow DROP arrow points to it, and a few zombies have already gathered around.
## Good loot (ammo, shells, medkit, scrap, batteries). The next morning's drop replaces it.
## GameState.supply_drop = {"id", "x", "y", "day"} (saved); the crate's contents are a normal
## container in GameState (id "drop_dN").

signal dropped(at: Vector2)

const CONTAINER: PackedScene = preload("res://scenes/world/loot_container.tscn")
const WALKER: PackedScene = preload("res://scenes/zombies/walker.tscn")
const LURCHER: ZombieData = preload("res://data/zombies/lurcher.tres")
const BRUTE: ZombieData = preload("res://data/zombies/brute.tres")
## Open outdoor spots (tiles) across town; one is drawn each morning.
const SITES: Array[Vector2] = [
	Vector2(40, 58), Vector2(115, 58), Vector2(60, 24), Vector2(100, 24), Vector2(140, 40),
	Vector2(20, 40), Vector2(130, 72), Vector2(30, 70), Vector2(150, 58), Vector2(78, 26),
]
const MIN_FROM_SAFEHOUSE: float = 420.0

var game: Node
var player: Player
var actors: Node2D
var crate: LootContainer


func setup(game_root: Node, p: Player, actors_root: Node2D) -> void:
	game = game_root
	player = p
	actors = actors_root
	game.day_cycle.dawn.connect(func(_s: Dictionary) -> void: new_drop())
	if not GameState.supply_drop.is_empty() and int(GameState.supply_drop.get("day", 0)) == GameState.day:
		_place_crate(Vector2(float(GameState.supply_drop.x), float(GameState.supply_drop.y)), StringName(GameState.supply_drop.id))


## True while there's a crate nobody has opened yet (the HUD arrow shows).
func is_unopened() -> bool:
	return crate != null and is_instance_valid(crate) and not GameState.is_rolled(crate.container_id)


func target() -> Dictionary:
	return {"pos": crate.global_position, "label": "DROP"} if is_unopened() else {}


## Morning: a new crate (from day 2). Returns its position, or Vector2.INF if none.
func new_drop() -> Vector2:
	_remove_crate()
	if GameState.day < 2:
		GameState.supply_drop = {}
		return Vector2.INF
	var at: Vector2 = _pick_site()
	if at == Vector2.INF:
		return at
	var id := StringName("drop_d%d" % GameState.day)
	GameState.supply_drop = {"id": String(id), "x": at.x, "y": at.y, "day": GameState.day}
	_place_crate(at, id)
	_spawn_guards(at)
	AudioManager.play_ui(preload("res://assets/audio/sfx/supply_drop.wav"), -3.0)
	get_tree().call_group(&"hud", &"show_banner", "SUPPLY DROP", "A crate came down in town. Follow the yellow arrow. They heard it too.")
	dropped.emit(at)
	return at


func _pick_site() -> Vector2:
	var map: RID = player.get_world_2d().navigation_map
	var home: Vector2 = Vector2(78.5, 71.5) * 16.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:drop%d" % [GameState.world_seed, GameState.day])
	var order: Array = range(SITES.size())
	for i in range(order.size() - 1, 0, -1):   # seeded shuffle
		var j: int = rng.randi() % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in order:
		var cand: Vector2 = (SITES[i] + Vector2(0.5, 0.5)) * 16.0
		if cand.distance_to(home) < MIN_FROM_SAFEHOUSE:
			continue
		var on_mesh: Vector2 = NavigationServer2D.map_get_closest_point(map, cand)
		if NavigationServer2D.map_get_regions(map).is_empty() or on_mesh.distance_to(cand) < 10.0:
			return on_mesh if not NavigationServer2D.map_get_regions(map).is_empty() else cand
	return Vector2.INF


func _place_crate(at: Vector2, id: StringName) -> void:
	crate = CONTAINER.instantiate()
	crate.name = "SupplyCrate"
	crate.container_id = id
	crate.container_type = &"supply_crate"
	crate.look = LootContainer.Look.STORAGE_BOX
	crate.display_name = "Supply crate"
	crate.position = at - Vector2(8, 8)
	game.get_node("World/Map/Containers").add_child(crate)
	var flare := PointLight2D.new()
	flare.name = "Flare"
	flare.texture = DayCycle._radial_texture()
	flare.color = Color(1.0, 0.25, 0.2)
	flare.energy = 1.2
	flare.texture_scale = 1.3
	flare.position = Vector2(8, 8)
	crate.add_child(flare)
	var pulse: Tween = flare.create_tween().set_loops()
	pulse.tween_property(flare, "energy", 0.5, 0.6)
	pulse.tween_property(flare, "energy", 1.2, 0.6)
	var smoke := CPUParticles2D.new()
	smoke.name = "Smoke"
	smoke.amount = 18
	smoke.lifetime = 2.2
	smoke.position = Vector2(8, 4)
	smoke.direction = Vector2.UP
	smoke.spread = 18.0
	smoke.gravity = Vector2(6, -14)
	smoke.initial_velocity_min = 8.0
	smoke.initial_velocity_max = 16.0
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 4.0
	smoke.color = Color(0.85, 0.3, 0.25, 0.55)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.35, 0.3, 0.6))
	ramp.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	smoke.color_ramp = ramp
	crate.add_child(smoke)


func _spawn_guards(at: Vector2) -> void:
	var map: RID = player.get_world_2d().navigation_map
	var count: int = mini(3 + GameState.day / 2, 7)
	for i in count:
		var z: Zombie = WALKER.instantiate()
		if i == 0 and GameState.day >= 4:
			z.data = BRUTE
		elif randf() < 0.3:
			z.data = LURCHER
		var spot: Vector2 = at + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(50, 110)
		z.position = NavigationServer2D.map_get_closest_point(map, spot) if not NavigationServer2D.map_get_regions(map).is_empty() else spot
		z.initial_facing = Vector2.RIGHT.rotated(randf() * TAU)
		actors.add_child(z)
		z.add_to_group(&"population")   # removed again when you're far away and they're calm


func _remove_crate() -> void:
	if crate != null and is_instance_valid(crate):
		crate.queue_free()
	crate = null
