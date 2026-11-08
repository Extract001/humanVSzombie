extends "res://tests/test_case.gd"
## Phase 4: Ashford Lane map, routes, doors, interaction prompts, roofs, locked gate.

const TILE: int = 16
const DESIGNATED_CONTAINERS: Array[String] = [
	"grocery_shelf_01", "grocery_shelf_02", "grocery_shelf_03", "grocery_shelf_04",
	"house_a_kitchen", "house_b_kitchen", "pharmacy_counter_01", "pharmacy_cabinet_01",
	"pharmacy_cabinet_02", "vehicle_trunk_pickup_01", "warehouse_office_locker",
]


func _map() -> Node2D:
	var m: Node2D = load("res://scenes/world/ashford_lane.tscn").instantiate()
	add_child(m)
	return m


## Waits until the navigation server answers for this map (max 2 s).
# The navigation server syncs maps in the background; under CPU load this has taken > 2 s (seen 2026-11-08),
# so wait up to 5 s. Only the waiting changed; the checks are the same.
func _wait_nav(m: Node2D, from: Vector2, to: Vector2) -> bool:
	for i in 300:
		await physics_frames(1)
		if not NavigationServer2D.map_get_path(m.get_world_2d().navigation_map, from, to, true).is_empty():
			return true
	return false


func _path_len(m: Node2D, a: Vector2, b: Vector2) -> Array:
	var path: PackedVector2Array = NavigationServer2D.map_get_path(m.get_world_2d().navigation_map, a, b, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return [length, path[-1] if path.size() > 0 else Vector2.INF]


func _t(x: float, y: float) -> Vector2:
	return Vector2(x + 0.5, y + 0.5) * TILE


func test_map_loads_with_bounds_spawn_and_containers() -> void:
	var m := _map()
	await physics_frames(2)
	var bounds: Rect2 = m.get_meta(&"bounds")
	check_eq(bounds.size, Vector2(160 * TILE, 86 * TILE), "map is 160 x 86 tiles")
	var spawn: Vector2 = m.get_node("PlayerSpawn").global_position
	var walls: TileMapLayer = m.get_node("Walls")
	check_eq(walls.get_cell_source_id(walls.local_to_map(spawn)), -1, "spawn is not inside a wall")
	check(Rect2(_t(70, 64), Vector2(16, 14) * TILE).has_point(spawn), "spawn is inside the safehouse")
	var ids: Array[String] = []
	for c in get_tree().get_nodes_in_group(&"loot_containers"):
		ids.append(String((c as LootContainer).container_id))
	var unique := {}
	for id in ids:
		check(id != "", "container has an id")
		check(not unique.has(id), "container id is unique: " + id)
		unique[id] = true
	for id in DESIGNATED_CONTAINERS:
		check_eq(ids.count(id), 1, "designated quest container exists exactly once: " + id)
	m.queue_free()


func test_walkers_and_spawn_are_not_inside_solid_objects() -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(3)
	var space: PhysicsDirectSpaceState2D = (game as Node2D).get_world_2d().direct_space_state
	var zombies: Array = get_tree().get_nodes_in_group(&"zombies")
	check(zombies.size() >= 20, "Ashford Lane has its Walker population (%d)" % zombies.size())
	for z in zombies:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = (z as Node2D).global_position
		q.collision_mask = 1
		check(space.intersect_point(q, 1).is_empty(), "%s is not inside a wall/vehicle" % z.name)
	game.queue_free()


func test_routes_between_safehouse_grocery_and_pharmacy() -> void:
	var m := _map()
	var safehouse_door_out := _t(78, 63)
	var grocery_inside := _t(62, 47)
	check(await _wait_nav(m, safehouse_door_out, grocery_inside), "navigation ready")
	var to_grocery: Array = _path_len(m, safehouse_door_out, grocery_inside)
	var to_pharmacy: Array = _path_len(m, safehouse_door_out, _t(16, 45))
	var alley_route: Array = _path_len(m, _t(70, 31), _t(22, 31))   # grocery back door -> pharmacy back door
	var to_pickup: Array = _path_len(m, safehouse_door_out, _t(77, 23))
	print("    route lengths (tiles): safehouse->grocery %.0f, safehouse->pharmacy %.0f, alley grocery->pharmacy %.0f, safehouse->pickup %.0f" % [
		to_grocery[0] / TILE, to_pharmacy[0] / TILE, alley_route[0] / TILE, to_pickup[0] / TILE])
	check((to_grocery[1] as Vector2).distance_to(grocery_inside) < 8.0, "route to the grocery store exists")
	check((to_pharmacy[1] as Vector2).distance_to(_t(16, 45)) < 8.0, "route to the pharmacy exists")
	check((alley_route[1] as Vector2).distance_to(_t(22, 31)) < 8.0, "back-alley route exists")
	check((to_pickup[1] as Vector2).distance_to(_t(77, 23)) < 8.0, "bolt-cutter truck is reachable (gate closed)")
	check(to_grocery[0] / TILE > 10.0 and to_grocery[0] / TILE < 60.0, "grocery is a short trip")
	check(to_pharmacy[0] / TILE > to_grocery[0] / TILE * 1.5, "pharmacy is clearly farther than the grocery")
	m.queue_free()


func test_locked_warehouse_gate_blocks_the_way_until_unlocked() -> void:
	var m := _map()
	var outside := _t(25, 23)
	var inside := _t(25, 14)  # free floor inside the warehouse (shelf rows are at y 6, 9, 12)
	check(await _wait_nav(m, outside, _t(60, 23)), "navigation ready")
	var blocked: Array = _path_len(m, outside, inside)
	check((blocked[1] as Vector2).distance_to(inside) > 32.0, "no path into the warehouse while the gate is locked")
	var gate: Door = m.get_node("WarehouseGate")
	check(not gate.toggle(null), "locked gate can't be opened")
	check(not gate.is_open, "gate stays closed")
	gate.unlock()
	var opened := false
	for i in 120:
		await physics_frames(1)
		var r: Array = _path_len(m, outside, inside)
		if (r[1] as Vector2).distance_to(inside) < 8.0:
			opened = true
			break
	check(opened, "after unlock() + rebake, zombies and player can path through (Phase 7 hook)")
	m.queue_free()


func _door_sandbox() -> Array:
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(-100, 0, 100, 16))
	add_wall(sandbox, Rect2(32, 0, 100, 16))
	var door: Door = load("res://scenes/world/door.tscn").instantiate()
	door.position = Vector2(0, 0)
	door.width_tiles = 2
	sandbox.add_child(door)
	return [sandbox, door]


func test_closed_door_blocks_open_door_lets_through() -> void:
	var s := _door_sandbox()
	var door: Door = s[1]
	var p := spawn_player(s[0], Vector2(16, 40))
	await physics_frames(3)
	p.move_override = Vector2.UP
	await physics_frames(60)
	check(p.global_position.y > 16.0, "closed door blocks the player (y=%.0f)" % p.global_position.y)
	var noises := [0]
	var count := func(_pos: Vector2, r: float, _s: Node) -> void:
		if is_equal_approx(r, Door.NOISE_RADIUS):
			noises[0] += 1
	NoiseSystem.noise_emitted.connect(count)
	check(door.toggle(p), "door opens")
	NoiseSystem.noise_emitted.disconnect(count)
	check_eq(noises[0], 1, "opening makes a small noise")
	await physics_frames(60)
	check(p.global_position.y < -10.0, "player walks through the open door (y=%.0f)" % p.global_position.y)
	p.move_override = Vector2.ZERO


func test_door_refuses_to_close_on_someone() -> void:
	var s := _door_sandbox()
	var door: Door = s[1]
	door.is_open = true
	var p := spawn_player(s[0], Vector2(16, 8))
	p.set_physics_process(false)
	await physics_frames(3)
	check(not door.toggle(p), "won't close while the player stands in the doorway")
	check(door.is_open, "still open")


func test_zombie_bangs_on_closed_door() -> void:
	var s := _door_sandbox()
	var door: Door = s[1]
	_still(s[0], Vector2(16, -60))
	var z := spawn_walker(s[0], Vector2(16, 40), Vector2.UP)
	var bangs := [0]
	z.door_banged.connect(func(_d: Door) -> void: bangs[0] += 1)
	await physics_frames(3)
	z.hear_noise(Vector2(16, -60), 300.0, null)
	await physics_frames(60 * 4)
	check(bangs[0] >= 2, "walker bangs on the closed door (%d bangs)" % bangs[0])
	check(z.global_position.y > 16.0, "but can't get through")
	check(not door.is_open, "door stays closed (Walkers can't open or break doors)")


func _still(parent: Node, pos: Vector2) -> Player:
	var p := spawn_player(parent, pos)
	p.set_physics_process(false)
	return p


func test_interaction_prompt_needs_range_and_facing() -> void:
	var s := _door_sandbox()
	var door: Door = s[1]
	var p := spawn_player(s[0], Vector2(16, 30))
	p.aim_direction = Vector2.UP
	await physics_frames(3)
	check(p.current_interactable != null and p.current_interactable.get_parent() == door, "facing the door in reach: prompt")
	check_eq(p.current_interactable.get_prompt(), "Open door", "prompt text")
	p.aim_direction = Vector2.DOWN
	await physics_frames(2)
	check(p.current_interactable == null, "facing away: no prompt")
	p.aim_direction = Vector2.UP
	p.global_position = Vector2(16, 90)
	await physics_frames(2)
	check(p.current_interactable == null, "too far: no prompt")
	p.global_position = Vector2(16, 30)
	await physics_frames(2)
	check(p.try_interact(), "E uses the door")
	check(door.is_open, "door opened")
	check_eq(p.current_interactable.get_prompt(), "Close door", "prompt switches to Close")


func test_roof_fades_when_entering_and_returns_when_leaving() -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	var p: Player = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	var roof: Roof = game.get_node("World/Map/SafehouseRoof")
	var hud: CanvasLayer = game.get_node("HUD")
	await physics_frames(30)
	check(roof.player_inside, "player starts inside the safehouse")
	check(roof.get_node("Sprite").modulate.a < 0.05, "safehouse roof faded")
	p.global_position = _t(78, 58)  # out on the street
	await physics_frames(30)
	check(not roof.player_inside, "outside now")
	check(roof.get_node("Sprite").modulate.a > 0.95, "roof back when outside")
	var grocery_roof: Roof = game.get_node("World/Map/GroceryRoof")
	p.global_position = _t(62, 47)
	await physics_frames(10)
	check(grocery_roof.player_inside, "inside the grocery store")
	check_eq(hud.get_node("%ToastLabel").text, "Grocery store", "location name shown")
	game.queue_free()


func test_map_light_budget() -> void:
	# Performance guard (Phase 3 FPS investigation): keep dynamic lights few.
	var m := _map()
	await physics_frames(2)
	var lights: Array = m.find_children("*", "PointLight2D", true, false)
	check(lights.size() <= 8, "map has at most 8 dynamic lights (%d)" % lights.size())
	for l in lights:
		check(not (l as PointLight2D).shadow_enabled, "map darkness lights don't cast shadows")
	m.queue_free()
