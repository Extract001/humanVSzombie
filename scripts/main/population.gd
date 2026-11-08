class_name Population
extends Node
## Fun pass: keeps the streets around the player alive by day.
## Every second it counts living zombies within NEAR px of the player. Below the target, it spawns
## one out of sight (SPAWN_MIN..SPAWN_MAX px away, on walkable ground, never in the safehouse).
## Some spawns are Lurchers (fast); some come looking for you (they "heard something").
## Spawned zombies that drift far away (and their corpses) are removed again.
## Off at dusk and night (the horde takes over) and in tests/bots (GameState.street_spawns_disabled).

const WALKER: PackedScene = preload("res://scenes/zombies/walker.tscn")
const LURCHER: ZombieData = preload("res://data/zombies/lurcher.tres")
const NEAR: float = 520.0
const SPAWN_MIN: float = 380.0
const SPAWN_MAX: float = 560.0
const DESPAWN: float = 950.0
## Day 1 aims for this many zombies near you (within NEAR); +1 per night survived, up to MAX_TARGET.
const BASE_TARGET: int = 10
const MAX_TARGET: int = 18
const LURCHER_CHANCE: float = 0.2
## Share of spawns that come towards you straight away.
const HUNTER_CHANCE: float = 0.5

var enabled: bool = true
var game: Node
var player: Player
var actors: Node2D
var data: SiegeData = preload("res://data/siege/siege_data.tres")
var _timer: float = 0.0
var spawned_total: int = 0


func setup(game_root: Node, p: Player, actors_root: Node2D) -> void:
	game = game_root
	player = p
	actors = actors_root
	enabled = not GameState.street_spawns_disabled


func target_count() -> int:
	return mini(BASE_TARGET + GameState.nights_survived, MAX_TARGET)


func _physics_process(delta: float) -> void:
	if not enabled or player == null or player.is_dead():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	_despawn_far()
	if GameState.phase != GameState.Phase.DAY or game.is_in_safehouse():
		return
	var near := 0
	var awake := 0
	for z in get_tree().get_nodes_in_group(&"zombies"):
		awake += 1
		if (z as Node2D).global_position.distance_squared_to(player.global_position) < NEAR * NEAR:
			near += 1
	if near < target_count() and awake < data.max_zombies_total:
		spawn_one()


## Returns the new zombie, or null if no good spot was found this time.
func spawn_one() -> Zombie:
	var map: RID = player.get_world_2d().navigation_map
	if NavigationServer2D.map_get_regions(map).is_empty():
		return null
	for attempt in 12:
		var cand: Vector2 = player.global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(SPAWN_MIN, SPAWN_MAX)
		var on_mesh: Vector2 = NavigationServer2D.map_get_closest_point(map, cand)
		if on_mesh.distance_to(cand) > 6.0 or game.SAFEHOUSE_RECT.has_point(on_mesh):
			continue
		if on_mesh.distance_to(player.global_position) < SPAWN_MIN - 20.0:
			continue
		var z: Zombie = WALKER.instantiate()
		if randf() < LURCHER_CHANCE:
			z.data = LURCHER
		z.position = on_mesh
		z.initial_facing = Vector2.RIGHT.rotated(randf() * TAU)
		actors.add_child(z)
		z.add_to_group(&"population")
		if randf() < HUNTER_CHANCE:
			# "Heard something": wanders over to roughly where you are now.
			z.hear_noise(player.global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60)), 0.0, null)
		spawned_total += 1
		return z
	return null


func _despawn_far() -> void:
	for z in get_tree().get_nodes_in_group(&"population"):
		var zz := z as Zombie
		if zz.global_position.distance_squared_to(player.global_position) < DESPAWN * DESPAWN:
			continue
		if zz.state == Zombie.State.DEAD or zz.state == Zombie.State.IDLE or zz.state == Zombie.State.WANDER:
			zz.queue_free()
