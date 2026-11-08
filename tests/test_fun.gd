extends "res://tests/test_case.gd"
## Fun pass: score & streaks, street population, Lurchers, goal arrow.


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func test_kills_score_with_streaks() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var actors: Node = game.get_node("World/Actors")
	var a := spawn_walker(actors, p.global_position + Vector2(200, 0), Vector2.LEFT)
	var b := spawn_walker(actors, p.global_position + Vector2(220, 0), Vector2.LEFT)
	var c := spawn_walker(actors, p.global_position + Vector2(240, 0), Vector2.LEFT)
	await physics_frames(1)
	a.hurtbox.receive_hit(1000.0, p)
	check_eq(GameState.score, 10, "a Walker kill = 10")
	b.hurtbox.receive_hit(1000.0, p)
	check_eq(GameState.score, 30, "a quick second kill = x2 (+20)")
	check_eq(game.score_keeper.streak, 2, "streak 2")
	check(game.hud.streak_label.text.contains("x2"), "the HUD shows the streak")
	game.score_keeper._last_kill_ms -= ScoreKeeper.STREAK_WINDOW_MS + 100
	c.hurtbox.receive_hit(1000.0, p)
	check_eq(GameState.score, 40, "after 4 s the streak starts over (+10)")
	check(game.hud.score_label.text.contains("40"), "score on the HUD")
	check(game.world.get_node("BloodSplats").get_child_count() == 3, "a blood splat per kill")
	game.queue_free()


func test_loot_objectives_and_nights_score() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var shelf: LootContainer = game.get_node("World/Map/Containers/C_grocery_shelf_01")
	shelf.open_contents()
	var before: int = GameState.score
	var moved: int = GameState.take_from(shelf.container_id, &"food_can", 2, p.inventory)
	check_eq(GameState.score - before, 2 * moved, "+2 per looted item")
	var pile: StringName = GameState.create_pile(p.global_position, [{"id": &"scrap", "qty": 3}], false)
	before = GameState.score
	GameState.take_from(pile, &"scrap", 3, p.inventory)
	check_eq(GameState.score, before, "picking your own drop back up scores nothing")
	before = GameState.score
	game.score_keeper.on_objective_completed()
	check_eq(GameState.score - before, 100, "objective +100")
	check_eq(game.score_keeper.on_night_survived(3), 150, "night 3 survived = +150")
	game.queue_free()


func test_records_kept_only_when_allowed() -> void:
	var game := _game()
	await physics_frames(3)
	var old_path: String = Settings.config_path
	Settings.config_path = "user://test_records.cfg"
	var old_best: int = Settings.best_score
	Settings.best_score = 0
	GameState.add_score(500)
	check(not game.score_keeper.record(), "tests never write records")
	check_eq(Settings.best_score, 0, "unchanged")
	GameState.records_disabled = false
	check(game.score_keeper.record(), "a new best score")
	check_eq(Settings.best_score, 500, "recorded")
	Settings.best_score = 0
	Settings.load_settings()
	check_eq(Settings.best_score, 500, "saved with the settings")
	GameState.records_disabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_records.cfg"))
	Settings.config_path = old_path
	Settings.best_score = old_best
	game.queue_free()


func test_score_is_saved() -> void:
	var game := _game()
	await physics_frames(3)
	GameState.add_score(1234)
	var d: Dictionary = GameState.to_dict()
	GameState.new_game(2)
	check_eq(GameState.score, 0, "a new game starts at 0")
	GameState.from_dict(d)
	check_eq(GameState.score, 1234, "the score comes back from the save")
	game.queue_free()


func test_population_keeps_the_streets_alive() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.health.setup(1.0e9)
	p.global_position = Vector2(78.5, 40.5) * 16.0   # the parking lot / main street area
	for z in get_tree().get_nodes_in_group(&"zombies"):
		z.queue_free()
	await physics_frames(320)   # navigation ready
	var pop: Population = game.population
	pop.enabled = true
	var spawned: Array = []
	for i in pop.target_count() + 4:
		var z: Zombie = pop.spawn_one()
		if z != null:
			spawned.append(z)
	check(spawned.size() >= pop.target_count(), "spawns on walkable ground around you (%d)" % spawned.size())
	var ok_dist := true
	var in_safehouse := false
	var lurchers := 0
	for z in spawned:
		if z.global_position.distance_to(p.global_position) < Population.SPAWN_MIN - 20.0:
			ok_dist = false
		if game.SAFEHOUSE_RECT.has_point(z.global_position):
			in_safehouse = true
		if z.data.id == &"lurcher":
			lurchers += 1
	check(ok_dist, "never spawns on screen (≥ %d px away)" % int(Population.SPAWN_MIN - 20))
	check(not in_safehouse, "never inside the safehouse")
	print("    (%d spawned, %d Lurchers)" % [spawned.size(), lurchers])
	# Far away and calm: removed again.
	p.global_position = Vector2(78.5, 72.5) * 16.0
	var far: Zombie = spawned[0]
	far.global_position = p.global_position + Vector2(1200, 0)
	far._enter_idle()
	pop._despawn_far()
	await physics_frames(2)
	check(not is_instance_valid(far), "zombies that drift far away are removed")
	# Off at dusk.
	GameState.phase = GameState.Phase.DUSK
	var count: int = get_tree().get_nodes_in_group(&"population").size()
	p.global_position = Vector2(78.5, 40.5) * 16.0
	await physics_frames(130)
	check(get_tree().get_nodes_in_group(&"population").size() <= count, "no street spawns at dusk/night")
	game.queue_free()


func test_lurcher_is_faster_than_walking() -> void:
	var lurcher: ZombieData = load("res://data/zombies/lurcher.tres")
	var stats: PlayerStats = load("res://data/player/player_stats.tres")
	var walker: ZombieData = load("res://data/zombies/walker.tres")
	check(lurcher.chase_speed > stats.walk_speed, "a Lurcher catches a walking player")
	check(lurcher.chase_speed < stats.run_speed, "but not a running one")
	check(lurcher.max_health < walker.max_health, "and dies faster than a Walker")
	check(lurcher.tint != Color.WHITE, "it looks different")


func test_goal_arrow_points_the_way() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var g: Dictionary = GoalFinder.find(game)
	check_eq(g.get("label", ""), "SEARCH", "day 1: go and search")
	var target_ok := false
	for c in ["grocery_shelf", "house_a_kitchen", "house_b_kitchen"]:
		for n in game.get_node("World/Map/Containers").get_children():
			if String(n.name).contains(c) and (n as Node2D).global_position == g.pos:
				target_ok = true
	check(target_ok, "points at a container with food or water")
	p.inventory.add_item(&"food_can", 5)
	p.inventory.add_item(&"water_bottle", 3)
	check_eq(GoalFinder.find(game).get("label", ""), "STASH", "carrying enough: back to the stash")
	GameState.phase = GameState.Phase.DUSK
	p.global_position = Vector2(78.5, 58.5) * 16.0
	check_eq(GoalFinder.find(game).get("label", ""), "HOME", "dusk outside: go home")
	p.global_position = Vector2(78.5, 72.5) * 16.0
	p.inventory.add_item(&"scrap", 2)
	check_eq(GoalFinder.find(game).get("label", ""), "BOARD UP", "dusk at home with scrap: board up")
	GameState.phase = GameState.Phase.DAY
	GameState.objectives_completed.append_array([&"stock_up", &"first_aid"])
	game.objectives.evaluate()
	var cut: Dictionary = GoalFinder.find(game)
	var trunk: Node2D = game.get_node("World/Map/Containers/C_vehicle_trunk_pickup_01")
	check(cut.get("pos", Vector2.INF) == trunk.global_position, "Cut the lock: find the bolt cutters in the pickup")
	p.inventory.add_item(&"bolt_cutters", 1)
	check_eq(GoalFinder.find(game).get("label", ""), "CUT", "with the cutters: to the gate")
	game.queue_free()
