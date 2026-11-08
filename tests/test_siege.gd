extends "res://tests/test_case.gd"
## Slice 1 — day/night cycle, Heat, barricades, night horde, dawn (GDD §16).

const SIEGE: SiegeData = preload("res://data/siege/siege_data.tres")


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func _window(game: Node, id: String) -> Barricade:
	return game.get_node("World/Map/Barricades/Window_" + id) as Barricade


func _close_dawn(game: Node) -> void:
	if game.dawn_panel.visible:
		game.dawn_panel.close()
	get_tree().paused = false


func test_heat_only_from_loud_daytime_noises() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	check_eq(GameState.heat, 0.0, "a new game starts with no Heat")
	NoiseSystem.emit_noise(p.global_position, 480.0, p)   # a pistol shot
	check_near(GameState.heat, 1.0, 0.001, "a pistol shot = +1 Heat")
	NoiseSystem.emit_noise(p.global_position, 120.0, p)   # running
	check_near(GameState.heat, 1.0, 0.001, "running doesn't raise Heat")
	var z := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(400, 0), Vector2.LEFT)
	NoiseSystem.emit_noise(z.global_position, 480.0, z)
	check_near(GameState.heat, 1.0, 0.001, "zombie noises don't count")
	NoiseSystem.emit_noise(p.global_position, 480.0 * 3.0, p)
	check_eq(game.day_cycle.horde_estimate(), SIEGE.horde_base + roundi(SIEGE.horde_per_heat * 4.0), "Heat makes tonight's horde bigger")
	GameState.phase = GameState.Phase.NIGHT
	NoiseSystem.emit_noise(p.global_position, 480.0, p)
	check_near(GameState.heat, 4.0, 0.001, "noise at night doesn't add Heat (the horde is already coming)")
	game.queue_free()


func test_horde_size_formula_and_cap() -> void:
	var game := _game()
	await physics_frames(3)
	var awake: int = get_tree().get_nodes_in_group(&"zombies").size()
	check_eq(game.day_cycle.horde_estimate(), SIEGE.horde_base, "night 1, no Heat = the base horde")
	GameState.nights_survived = 4
	check_eq(game.day_cycle.horde_estimate(), SIEGE.horde_base + roundi(SIEGE.horde_per_night * 4), "grows every night")
	GameState.add_heat(500.0)
	check_eq(game.day_cycle.horde_estimate(), SIEGE.max_zombies_total - awake, "capped: never more than %d Walkers awake" % SIEGE.max_zombies_total)
	game.queue_free()


func test_cycle_day_dusk_night_dawn() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.health.setup(1.0e9)
	check_eq(GameState.phase, GameState.Phase.DAY, "starts at day")
	check_eq(game.day_cycle.clock_text(), "06:00", "06:00 in the morning")
	GameState.phase_time = SIEGE.day_length - 0.05
	await physics_frames(6)
	check_eq(GameState.phase, GameState.Phase.DUSK, "dusk after the day")
	GameState.add_heat(2.0)
	var expected: int = game.day_cycle.horde_estimate()
	GameState.phase_time = SIEGE.dusk_length - 0.05
	await physics_frames(6)
	check_eq(GameState.phase, GameState.Phase.NIGHT, "night after dusk")
	check_eq(game.day_cycle.horde_alive(), expected, "the whole horde is on its way")
	# Let the first arrivals spawn.
	GameState.phase_time = SIEGE.night_length * SIEGE.arrival_share + 3.0
	await physics_frames(3)
	var horde: Array = get_tree().get_nodes_in_group(&"horde")
	check_eq(horde.size(), expected, "all horde Walkers spawned by %d%% of the night" % int(SIEGE.arrival_share * 100))
	var far := true
	for z in horde:
		if (z as Zombie).global_position.distance_to(p.global_position) < DayCycle.MIN_SPAWN_DISTANCE - 20.0:
			far = false
		check((z as Zombie).is_besieging(), "horde Walkers head for the safehouse")
	check(far, "they spawn away from the player")
	var kills_before: int = int(GameState.stats.kills)
	(horde[0] as Zombie).health.take_damage(1000.0)
	await physics_frames(2)
	check_eq(int(GameState.stats.kills), kills_before + 1, "horde kills count")
	GameState.phase_time = SIEGE.night_length - 0.02
	await physics_frames(4)
	check_eq(GameState.phase, GameState.Phase.DAY, "dawn: a new day")
	check_eq(GameState.day, 2, "day 2")
	check_eq(GameState.nights_survived, 1, "one night survived")
	check_eq(GameState.heat, 0.0, "Heat resets at dawn")
	check(game.dawn_panel.visible and get_tree().paused, "the dawn summary shows and pauses the game")
	check(game.dawn_panel.get_node("Panel").find_child("Summary", true, false).text.contains("Killed tonight: 1"), "summary counts tonight's kills")
	check_eq(SaveSystem.last_save_reason, "dawn", "autosave at dawn")
	await physics_frames(2)
	var living := 0
	for z in get_tree().get_nodes_in_group(&"horde"):
		if (z as Zombie).state != Zombie.State.DEAD:
			living += 1
	check_eq(living, 0, "the horde leaves at dawn (only corpses stay)")
	_close_dawn(game)
	check(not get_tree().paused, "Continue resumes")
	game.queue_free()


func test_barricade_planks_hits_and_breaking() -> void:
	var game := _game()
	await physics_frames(3)
	var w: Barricade = _window(game, "safehouse_west")
	check_eq(w.planks(), SIEGE.start_planks, "windows start with %d plank" % SIEGE.start_planks)
	w.set_planks(2)
	check(not w.take_hit(SIEGE.plank_health * 0.5), "a hit damages")
	check_eq(w.planks(), 2, "half a plank gone: still 2 (one cracked)")
	w.take_hit(SIEGE.plank_health)
	check_eq(w.planks(), 1, "one plank left")
	check(w.take_hit(SIEGE.plank_health), "the last plank breaks")
	check(w.is_broken(), "broken")
	await physics_frames(2)
	check(w.get_node("Shape").disabled, "a broken window lets anyone through")
	w.add_plank()
	await physics_frames(2)
	check(not w.get_node("Shape").disabled, "boarded again")
	check_eq(w.collision_layer, Barricade.LAYER, "barricades are their own physics layer (bullets and sight pass)")
	game.queue_free()


func test_player_boards_up_a_window_with_scrap() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var w: Barricade = _window(game, "safehouse_east")
	w.set_planks(0)
	p.global_position = w.center() + Vector2(-14, 0)
	p.aim_direction = Vector2.RIGHT
	p.use_mouse_aim = false
	await physics_frames(3)
	check(p.current_interactable == w.get_node("Interact"), "the window is the thing in front of you")
	check(p.try_interact(), "E on the window")
	check(not p.is_working(), "no scrap: nothing happens")
	p.inventory.add_item(&"scrap", 2)
	check(p.try_interact(), "E again")
	check(p.is_working(), "nailing a plank")
	await physics_frames(int(SIEGE.plank_build_time * 60.0) + 4)
	check_eq(w.planks(), 1, "one plank nailed")
	check_eq(p.inventory.count(&"scrap"), 1, "it cost one scrap")
	p.try_interact()
	await physics_frames(10)
	p.move_override = Vector2.UP
	await physics_frames(3)
	p.move_override = Vector2.ZERO
	check(not p.is_working(), "walking away cancels the job")
	check_eq(p.inventory.count(&"scrap"), 1, "a cancelled plank costs nothing")
	game.queue_free()


func test_horde_walker_breaks_a_window_then_comes_in() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.health.setup(1.0e9)
	p.global_position = Vector2(84.5, 76.0) * 16.0   # by the bed, far side of the room
	var w: Barricade = _window(game, "safehouse_west")
	w.set_planks(2)
	var z := spawn_walker(game.get_node("World/Actors"), w.center() + Vector2(-60, 0), Vector2.RIGHT, true)
	z.siege_goal = w.center() + Vector2(20, 0)
	var t := 0
	while not w.is_broken() and t < 60 * 20:
		await physics_frames(1)
		t += 1
	check(w.is_broken(), "a Walker breaks 2 planks")
	var expected_s: float = 2.0 * SIEGE.plank_health / SIEGE.zombie_barricade_damage * SIEGE.zombie_barricade_interval
	check(t / 60.0 < expected_s + 6.0, "in about %.0f s plus walking (took %.1f s)" % [expected_s, t / 60.0])
	await physics_frames(180)
	check(z.global_position.x > w.center().x, "then it climbs in")
	game.queue_free()


func test_night_is_dark_outside_but_not_in_the_safehouse() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.health.setup(1.0e9)
	check(not p.in_darkness, "daylight")
	GameState.phase = GameState.Phase.NIGHT
	GameState.phase_time = 30.0
	await physics_frames(2)
	check(game.is_in_safehouse() and not p.in_darkness, "the lamp-lit safehouse isn't dark")
	p.global_position = Vector2(78.5, 58.5) * 16.0
	await physics_frames(2)
	check(p.in_darkness, "outside at night = darkness (Walkers see you at half range)")
	check(game.day_cycle.tint.color.v < 0.75, "the world is tinted dark")
	game.queue_free()


func test_restock_at_dawn_never_touches_quest_containers() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.health.setup(1.0e9)
	var emptied: Array = []
	for c in get_tree().get_nodes_in_group(&"loot_containers"):
		var lc := c as LootContainer
		lc.open_contents()
		GameState.containers[lc.container_id] = []   # emptied by the player
		emptied.append(lc)
	var restocked: int = game.day_cycle.restock_town()
	check_eq(restocked, SIEGE.restock_per_dawn, "%d places restocked" % SIEGE.restock_per_dawn)
	var quest_rerolled := false
	var fresh := 0
	for lc in emptied:
		if not GameState.is_rolled(lc.container_id):
			fresh += 1
			if not lc.all_guaranteed_items().is_empty():
				quest_rerolled = true
	check_eq(fresh, restocked, "restocked containers roll new loot when searched")
	check(not quest_rerolled, "quest containers are never restocked (no duplicate quest items)")
	game.queue_free()


func test_siege_state_saves_and_a_night_save_restarts_at_dusk() -> void:
	var game := _game()
	await physics_frames(3)
	GameState.add_heat(3.0)
	GameState.nights_survived = 2
	_window(game, "safehouse_south").set_planks(3)
	GameState.phase = GameState.Phase.NIGHT
	GameState.phase_time = 70.0
	check(game.save_now("test"), "saved")
	game.queue_free()
	await physics_frames(2)
	GameState.new_game(5)
	check(SaveSystem.load_game().ok, "loaded")
	var game2: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game2)
	await physics_frames(3)
	check_near(GameState.heat, 3.0, 0.001, "Heat kept")
	check_eq(GameState.nights_survived, 2, "nights survived kept")
	check_eq(_window(game2, "safehouse_south").planks(), 3, "boards kept")
	check_eq(GameState.phase, GameState.Phase.DUSK, "a save from the night restarts at dusk (no half-spawned horde)")
	check(GameState.phase_time < 1.0, "at the start of dusk")
	game2.queue_free()


func test_evacuation_after_night_ten_with_the_radio() -> void:
	var game := _game()
	await physics_frames(3)
	_player(game).health.setup(1.0e9)
	var got: Array = []
	game.day_cycle.dawn.connect(func(s: Dictionary) -> void: got.append(s))
	GameState.nights_survived = SIEGE.nights_to_win - 1
	GameState.phase = GameState.Phase.NIGHT
	game.day_cycle.end_night()
	check(not got[0].evac, "night 10 without the radio: no convoy")
	_close_dawn(game)
	GameState.add_unlock(&"radio_repaired")
	GameState.phase = GameState.Phase.NIGHT
	game.day_cycle.end_night()
	check(got[1].evac, "radio repaired and 10+ nights: the convoy comes")
	check_eq(game.dawn_panel.get_node("Panel").find_child("Continue", true, false).text, "Keep surviving", "endless after the rescue")
	_close_dawn(game)
	game.queue_free()
