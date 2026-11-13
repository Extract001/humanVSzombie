extends "res://tests/test_case.gd"
## Slice 2 — shotgun and fire axe.


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func test_weapon_caches_in_the_world() -> void:
	var game := _game()
	await physics_frames(3)
	var box: LootContainer = game.get_node("World/Map/Containers/C_house_a_bedroom")
	var tool: LootContainer = game.get_node("World/Map/Containers/C_house_c_toolbox")
	check(box.all_guaranteed_items().has(&"shotgun"), "the shotgun is in house A's wardrobe box")
	check(tool.all_guaranteed_items().has(&"fire_axe"), "the fire axe is in house C's toolbox")
	for s in [1, 42, 777]:
		GameState.new_game(s)
		var items: Array = box.open_contents()
		var found := false
		for e in items:
			if e.id == &"shotgun":
				found = true
		check(found, "seed %d: always there" % s)
	game.queue_free()


func test_picking_up_gives_a_weapon_slot_even_with_a_full_bag() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	while p.inventory.slots.size() < p.inventory.capacity_slots:
		p.inventory.add_item(&"scrap", 99)
		if p.inventory.space_for(&"scrap") == 0:
			break
	var box: LootContainer = game.get_node("World/Map/Containers/C_house_a_bedroom")
	box.open_contents()
	var moved: int = GameState.take_from(box.container_id, &"shotgun", 1, p.inventory)
	check_eq(moved, 1, "taken even though the bag is full")
	await physics_frames(3)
	check(p.weapons.has_weapon(&"shotgun"), "it's in a weapon slot")
	check_eq(p.inventory.count(&"shotgun"), 0, "not in the bag")
	check_eq(p.weapons.current_weapon().id, &"shotgun", "and in your hands")
	check_eq(p.weapons.loaded_rounds(), 4, "loaded (4 shells)")
	GameState.put_into(box.container_id, &"shotgun", 1)
	GameState.take_from(box.container_id, &"shotgun", 1, p.inventory)
	await physics_frames(3)
	check_eq(p.weapons.slots.size(), 3, "a second copy doesn't add another slot")
	game.queue_free()


func test_shotgun_spreads_pellets_and_is_loud() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.use_mouse_aim = false
	p.weapons.add_weapon(load("res://data/weapons/shotgun.tres"))
	p.try_switch(2)
	await physics_frames(20)
	var actors: Node = game.get_node("World/Actors")
	var zs: Array = []
	for k in 3:
		zs.append(spawn_walker(actors, p.global_position + Vector2(50, -12 + k * 12), Vector2.LEFT))
	await physics_frames(2)
	var heat: float = GameState.heat
	p.aim_direction = Vector2.RIGHT
	check(p.try_attack(), "fires")
	await physics_frames(2)
	var hurt := 0
	for z in zs:
		if (z as Zombie).health.current_health < (z as Zombie).data.max_health:
			hurt += 1
	check(hurt >= 2, "one blast hits several zombies close up (%d of 3)" % hurt)
	check_near(GameState.heat - heat, 1.25, 0.01, "a shot = +1.25 Heat")
	game.queue_free()


func test_fire_axe_two_hits_a_walker() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.use_mouse_aim = false
	p.weapons.add_weapon(load("res://data/weapons/fire_axe.tres"))
	p.try_switch(2)
	await physics_frames(20)
	var z := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(18, 0), Vector2.LEFT)
	z.data = z.data.duplicate()
	z.data.bite_damage = 0.0
	p.health.setup(1.0e9)
	await physics_frames(2)
	p.aim_direction = Vector2.RIGHT
	p.try_attack()
	await physics_frames(60)
	z.global_position = p.global_position + Vector2(18, 0)
	p.try_attack()
	await physics_frames(30)
	check_eq(z.state, Zombie.State.DEAD, "two axe hits kill a Walker (60 HP)")
	game.queue_free()


func test_found_weapons_are_saved() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.weapons.add_weapon(load("res://data/weapons/shotgun.tres"), 2)
	p.weapons.add_weapon(load("res://data/weapons/fire_axe.tres"))
	var d: Dictionary = p.to_save_dict()
	game.queue_free()
	await physics_frames(2)
	var game2 := _game()
	await physics_frames(3)
	var p2 := _player(game2)
	p2.apply_save_dict(d, p2.global_position)
	check(p2.weapons.has_weapon(&"shotgun") and p2.weapons.has_weapon(&"fire_axe"), "found weapons come back")
	check_eq(p2.weapons.rounds_in_mag[2], 2, "with the shells that were loaded")
	game2.queue_free()
