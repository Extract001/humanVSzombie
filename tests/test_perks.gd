extends "res://tests/test_case.gd"
## Slice 2 — perk cards at dawn.


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func test_offer_is_three_different_open_perks() -> void:
	GameState.new_game(1)
	var offer: Array[PerkData] = Perks.offer(3)
	check_eq(offer.size(), 3, "three cards")
	check(offer[0].id != offer[1].id and offer[1].id != offer[2].id and offer[0].id != offer[2].id, "all different")
	for p in Perks.pool():
		for i in p.max_stacks:
			GameState.add_perk(p.id)
	check(Perks.offer(3).is_empty(), "nothing left to offer when every perk is maxed")
	_reset_perks()
	check(Perks.pool().size() >= 12, "a pool of at least 12 perks (%d)" % Perks.pool().size())


func test_stat_perks_change_the_player() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var base_noise: float = p.stats.run_noise_radius
	var base_speed: float = p.stats.walk_speed
	p.health.take_damage(10.0)
	GameState.add_perk(&"quiet_feet")
	GameState.add_perk(&"thick_skin")
	GameState.add_perk(&"deep_pockets")
	GameState.add_perk(&"fleet_foot")
	GameState.add_perk(&"night_owl")
	check_near(p.stats.run_noise_radius, base_noise * 0.7, 0.01, "Quiet Feet: running is 30% quieter")
	check_eq(p.health.max_health, 125.0, "Thick Skin: +25 max health")
	check_eq(p.health.current_health, 115.0, "and the same damage taken (90 -> 115)")
	check_eq(p.inventory.capacity_slots, 15, "Deep Pockets: +3 bag slots")
	check_near(p.stats.walk_speed, base_speed * 1.1, 0.01, "Fleet Foot: 10% faster")
	check_near(p.stats.flashlight_battery_seconds, p.base_stats.flashlight_battery_seconds * 1.6, 0.01, "Night Owl: battery +60%")
	check_near(p.base_stats.run_noise_radius, base_noise, 0.01, "the base data file is untouched")
	game.queue_free()
	_reset_perks()


func test_weapon_search_and_plank_perks() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var z := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(20, 0), Vector2.LEFT)
	p.aim_direction = Vector2.RIGHT
	p.use_mouse_aim = false
	await physics_frames(2)
	GameState.add_perk(&"heavy_hands")
	var hp: float = z.health.current_health
	p.try_attack()
	await physics_frames(20)
	check_near(hp - z.health.current_health, 25.0 * 1.3, 0.01, "Heavy Hands: the bat hits 30% harder")
	var shelf: LootContainer = game.get_node("World/Map/Containers/C_grocery_shelf_01")
	var t: float = shelf.get_search_time()
	GameState.add_perk(&"scavenger")
	check_near(shelf.get_search_time(), t * 0.65, 0.001, "Scavenger: 35% faster searches")
	z.queue_free()
	await physics_frames(30)
	var plank: float = Barricade.plank_health()
	GameState.add_perk(&"carpenter")
	check_near(Barricade.plank_health(), plank * 1.5, 0.01, "Carpenter: planks 50% tougher")
	GameState.add_perk(&"steady_hands")
	p.try_switch(1)
	await physics_frames(20)
	p.inventory.add_item(&"ammo_pistol", 10)
	p.weapons.rounds_in_mag[1] = 0
	check(p.try_reload(), "reloading")
	var frames := 0
	while p.weapons.is_reloading and frames < 200:
		await physics_frames(1)
		frames += 1
	check_near(frames / 60.0, 1.2 * 0.7, 0.05, "Steady Hands: reload 30%% faster (%.2f s)" % (frames / 60.0))
	game.queue_free()
	_reset_perks()


func test_bloodlust_heals_on_kills() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.health.take_damage(30.0)
	GameState.add_perk(&"bloodlust")
	var z := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(200, 0), Vector2.LEFT)
	await physics_frames(1)
	z.hurtbox.receive_hit(1000.0, p)
	check_eq(p.health.current_health, 74.0, "a kill heals 4")
	game.queue_free()
	_reset_perks()


func test_dawn_cards_pick_and_save() -> void:
	var game := _game()
	await physics_frames(3)
	_player(game).health.setup(1.0e9)
	GameState.phase = GameState.Phase.NIGHT
	game.day_cycle.end_night()
	var panel: CanvasLayer = game.dawn_panel
	check(panel.visible and panel.get_node("Panel").find_child("Cards", true, false).visible, "three perk cards at dawn")
	check_eq(panel.get_node("Panel").find_child("Cards", true, false).get_child_count(), 3, "three of them")
	panel.close()
	check(panel.visible, "you can't skip the pick")
	await physics_frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	panel._input(key)
	check(panel.picked != &"", "key 2 takes the second card")
	check_eq(Perks.stacks(panel.picked), 1, "the perk is yours")
	panel.close()
	check(not panel.visible and not get_tree().paused, "then Continue")
	var id: StringName = panel.picked
	var d: Dictionary = GameState.to_dict()
	GameState.new_game(3)
	check_eq(Perks.stacks(id), 0, "a new game has no perks")
	GameState.from_dict(d)
	check_eq(Perks.stacks(id), 1, "perks come back from the save")
	game.queue_free()
	_reset_perks()


func test_dawn_without_open_perks_just_continues() -> void:
	var game := _game()
	await physics_frames(3)
	_player(game).health.setup(1.0e9)
	for p in Perks.pool():
		for i in p.max_stacks:
			GameState.add_perk(p.id)
	GameState.phase = GameState.Phase.NIGHT
	game.day_cycle.end_night()
	check(not game.dawn_panel.get_node("Panel").find_child("Cards", true, false).visible, "no cards when everything is maxed")
	game.dawn_panel.close()
	check(not game.dawn_panel.visible, "Continue works")
	game.queue_free()
	_reset_perks()


## Perks live in GameState: never leave them behind for the next test.
func _reset_perks() -> void:
	GameState.perks.clear()
	GameState.perks_changed.emit()
