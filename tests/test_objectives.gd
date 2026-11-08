extends "res://tests/test_case.gd"
## Phase 7: objective chain, stash, bed, bolt-cutter gate, radio, quest-item safety net.


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


## Takes exactly the guaranteed items of a designated container into the bag.
func _take_guaranteed(container_id: String, p: Player, game: Node) -> void:
	var c: LootContainer = game.get_node("World/Map/Containers/C_" + container_id)
	c.open_contents()
	var g: Dictionary = QuestGuarantees.for_container(StringName(container_id))
	for id in g:
		var moved: int = GameState.take_from(StringName(container_id), id, g[id], p.inventory)
		check_eq(moved, g[id], "took guaranteed %s x%d from %s" % [id, g[id], container_id])


func test_chain_data() -> void:
	var ids: Array = ObjectiveChain.get_data().objectives.map(func(o: ObjectiveData) -> StringName: return o.id)
	check_eq(ids, [&"stock_up", &"first_aid", &"cut_the_lock", &"signal_parts", &"last_signal"], "5 objectives in GDD order")
	for o in ObjectiveChain.get_data().objectives:
		check(o.title != "" and o.description != "", "%s has a title and description" % o.id)
		for id in o.items:
			check(ItemRegistry.get_item(StringName(id)) != null, "%s uses a known item %s" % [o.id, id])
	var stock: ObjectiveData = ObjectiveChain.get_data().objectives[0]
	check(QuestGuarantees.total(&"food_can") >= int(stock.items[&"food_can"]), "guaranteed food covers Stock up")
	check(QuestGuarantees.total(&"water_bottle") >= int(stock.items[&"water_bottle"]), "guaranteed water covers Stock up")
	var aid: ObjectiveData = ObjectiveChain.get_data().objectives[1]
	var medical := 0
	for cid in QuestGuarantees.get_data().guarantees:
		if String(cid).begins_with(aid.container_prefix):
			for item in QuestGuarantees.get_data().guarantees[cid]:
				if aid.item_ids.has(StringName(item)):
					medical += int(QuestGuarantees.get_data().guarantees[cid][item])
	check(medical >= aid.amount, "guaranteed pharmacy medical (%d) covers First aid (%d)" % [medical, aid.amount])


func test_delivery_completes_exactly_once() -> void:
	var game := _game()
	await physics_frames(3)
	var t: ObjectiveTracker = game.get_node("Objectives")
	var done: Array = []
	t.objective_completed.connect(func(o: ObjectiveData) -> void: done.append(o.id))
	check_eq(t.current().id, &"stock_up", "starts with Stock up")
	GameState.stash_add(&"food_can", 4)
	GameState.stash_add(&"water_bottle", 3)
	check_eq(t.current().id, &"stock_up", "4 of 5 food: not done")
	check_eq(t.progress_text(t.current()), "Canned food 4/5 in stash · Water 3/3 in stash", "progress text")
	GameState.stash_add(&"food_can", 2)
	check_eq(done, [&"stock_up"], "completed when the 5th food arrives")
	check_eq(GameState.stash_count(&"food_can"), 1, "5 food handed over, the extra one stays")
	check_eq(GameState.stash_count(&"water_bottle"), 0, "3 water handed over")
	GameState.stash_add(&"food_can", 10)
	GameState.stash_add(&"water_bottle", 10)
	t.evaluate()
	check_eq(done, [&"stock_up"], "more deliveries never complete it again")
	check_eq(GameState.objectives_completed.count(&"stock_up"), 1, "recorded once")
	check_eq(t.current().id, &"first_aid", "next objective starts automatically")
	game.queue_free()


func test_first_aid_counts_only_pharmacy_and_early_finds() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var t: ObjectiveTracker = game.get_node("Objectives")
	GameState.roll_container(&"house_x_box", &"backpack", {&"bandage": 3})
	GameState.take_all(&"house_x_box", p.inventory)
	GameState.roll_container(&"pharmacy_cabinet_01", &"backpack", {&"medkit": 1, &"bandage": 1})
	GameState.take_all(&"pharmacy_cabinet_01", p.inventory)  # found BEFORE First aid is active
	check_eq(t.current().id, &"stock_up", "still on Stock up")
	GameState.stash_add(&"food_can", 5)
	GameState.stash_add(&"water_bottle", 3)
	check(t.is_completed(&"first_aid"), "pharmacy finds made earlier complete First aid as soon as it starts")
	check_eq(t.looted_count(ObjectiveChain.get_data().objectives[1]), 2, "the 3 bandages from a house don't count")
	game.queue_free()


func test_warehouse_gate_needs_bolt_cutters_and_stays_open() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var gate: Door = game.get_node("World/Map/WarehouseGate")
	check(gate.locked, "gate starts locked")
	check(not gate.toggle(p), "can't open without bolt cutters")
	check(gate.locked and not gate.is_open, "still locked")
	p.inventory.add_item(&"bolt_cutters", 1)
	check(gate.get_prompt().begins_with("Cut the chain"), "prompt offers to cut the chain")
	var noises: Array = []
	NoiseSystem.noise_emitted.connect(func(_pos: Vector2, r: float, _s: Node) -> void: noises.append(r))
	check(gate.toggle(p), "bolt cutters open it")
	check(not gate.locked and gate.is_open, "unlocked and open")
	check_eq(p.inventory.count(&"bolt_cutters"), 0, "bolt cutters used up")
	check(noises.has(260.0), "cutting the chain is loud (260 px)")
	check(GameState.has_unlock(&"warehouse_gate"), "remembered in GameState")
	game.queue_free()
	await physics_frames(2)
	# A fresh game scene in the same run (respawn/load): the gate is already open.
	var again: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(again)
	await physics_frames(2)
	var gate2: Door = again.get_node("World/Map/WarehouseGate")
	check(not gate2.locked and gate2.is_open, "stays cut in the same run")
	check(not gate2.is_in_group(&"nav_source"), "no longer blocks zombie paths")
	again.queue_free()


func test_stash_unlimited_safe_on_death_and_full_bag() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	GameState.stash_add(&"scrap", 500)
	check_eq(GameState.stash_count(&"scrap"), 500, "stash has no capacity limit")
	check_eq(GameState.store_in_stash(p.inventory, &"bandage", 99), 2, "stored the 2 bandages from the bag")
	check_eq(p.inventory.count(&"bandage"), 0, "bag no longer has them")
	check_eq(GameState.take_from_stash(p.inventory, &"scrap", 500), 11 * 20, "bag takes what fits (11 free slots x 20)")
	check_eq(GameState.stash_count(&"scrap"), 500 - 220, "the rest stays in the stash")
	var before: Dictionary = GameState.stash.duplicate()
	p.health.take_damage(1000.0)
	await physics_frames(2)
	check_eq(GameState.stash, before, "dying never touches the stash")
	game.queue_free()


## Slice 1: the bed heals and skips to dusk (the day changes at dawn, after the night).
func test_bed_heals_new_day_refused_near_zombies() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var z := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(100, 0), Vector2.LEFT)
	await physics_frames(1)
	check(not game.try_sleep(), "can't sleep with a zombie 100 px away")
	check_eq(GameState.phase, GameState.Phase.DAY, "still day")
	z.queue_free()
	await physics_frames(1)
	p.health.take_damage(60.0)
	check(game.try_sleep(), "sleeps when no zombie is close")
	check_eq(p.health.current_health, 100.0, "full heal")
	check_eq(GameState.phase, GameState.Phase.DUSK, "sleeping skips to dusk")
	check_eq(GameState.day, 1, "same day until dawn")
	check(not game.try_sleep(), "no sleeping at dusk")
	var bed: Node2D = game.get_node("World/Map/Bed")
	var point: Node2D = game.get_node("World/Map/RespawnPoint")
	check(point.global_position.distance_to(bed.global_position) < 40.0, "respawn point is beside the bed")
	game.queue_free()


func test_radio_only_repairs_at_the_end() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.inventory.add_item(&"radio_part", 1)
	var t: ObjectiveTracker = game.get_node("Objectives")
	check(t.try_repair_radio() != "", "too early: the radio refuses")
	check_eq(p.inventory.count(&"radio_part"), 1, "nothing used up")
	check(not GameState.has_unlock(&"radio_repaired"), "not repaired")
	game.queue_free()


func test_full_chain_with_only_guaranteed_items() -> void:
	for seed_value in [3, 17, 91]:
		var game := _game(seed_value)
		await physics_frames(3)
		var p := _player(game)
		var t: ObjectiveTracker = game.get_node("Objectives")
		# 1. Stock up: grocery shelves + kitchens, then the stash.
		for cid in ["grocery_shelf_01", "grocery_shelf_02", "grocery_shelf_03", "grocery_shelf_04", "house_a_kitchen", "house_b_kitchen"]:
			_take_guaranteed(cid, p, game)
		GameState.store_in_stash(p.inventory, &"food_can", 5)
		GameState.store_in_stash(p.inventory, &"water_bottle", 3)
		check(t.is_completed(&"stock_up"), "seed %d: Stock up done" % seed_value)
		# 2. First aid: pharmacy.
		for cid in ["pharmacy_counter_01", "pharmacy_cabinet_01", "pharmacy_cabinet_02"]:
			_take_guaranteed(cid, p, game)
		check(t.is_completed(&"first_aid"), "seed %d: First aid done" % seed_value)
		# 3. Cut the lock: truck bed, then the gate.
		_take_guaranteed("vehicle_trunk_pickup_01", p, game)
		check(game.get_node("World/Map/WarehouseGate").toggle(p), "seed %d: gate cut" % seed_value)
		check(t.is_completed(&"cut_the_lock"), "seed %d: Cut the lock done" % seed_value)
		# 4. Signal parts: warehouse office locker (reachable now).
		_take_guaranteed("warehouse_office_locker", p, game)
		check(t.is_completed(&"signal_parts"), "seed %d: Signal parts done" % seed_value)
		# 5. Last signal: the radio desk.
		var ended := [false]
		game.ending_panel.opened.connect(func() -> void: ended[0] = true)
		game.use_radio()
		check(t.is_chain_complete(), "seed %d: chain complete" % seed_value)
		check(ended[0] and game.ending_panel.visible, "seed %d: ending broadcast shown" % seed_value)
		check_eq(p.inventory.count(&"radio_part") + GameState.stash_count(&"radio_part"), 0, "radio component used")
		game.queue_free()
		await physics_frames(2)


func test_path_to_radio_locker_after_gate_is_cut() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.inventory.add_item(&"bolt_cutters", 1)
	game.get_node("World/Map/WarehouseGate").toggle(p)
	var map: RID = game.get_world_2d().navigation_map
	var from: Vector2 = game.get_node("World/Map/PlayerSpawn").global_position
	var to: Vector2 = game.get_node("World/Map/Containers/C_warehouse_office_locker").global_position
	var path := PackedVector2Array()
	for i in 90:
		await physics_frames(1)
		path = NavigationServer2D.map_get_path(map, from, to, true)
		if not path.is_empty() and path[path.size() - 1].distance_to(to) < 24.0:
			break
	check(not path.is_empty() and path[path.size() - 1].distance_to(to) < 24.0, "walkable path from the safehouse to the radio locker")
	game.queue_free()


func test_missing_quest_item_is_put_back() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var t: ObjectiveTracker = game.get_node("Objectives")
	check(t.validate_quest_items().is_empty(), "nothing missing at the start (guarantees cover unsearched containers)")
	game.get_node("World/Map/Containers/C_vehicle_trunk_pickup_01").open_contents()
	GameState.take_from(&"vehicle_trunk_pickup_01", &"bolt_cutters", 1, p.inventory)
	p.inventory.remove_item(&"bolt_cutters", 1)  # lost by a bug / a damaged save
	check_eq(t.validate_quest_items(), [&"bolt_cutters"] as Array[StringName], "missing bolt cutters detected")
	var back := 0
	for e in GameState.get_contents(&"vehicle_trunk_pickup_01"):
		if e.id == &"bolt_cutters":
			back += int(e.qty)
	check_eq(back, 1, "put back in the truck bed")
	check(t.validate_quest_items().is_empty(), "never duplicated by running it again")
	game.queue_free()


func test_stations_open_their_panels() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var board: SafehouseStation = game.get_node("World/Map/ObjectiveBoard")
	board.get_node("Interact").interact(p)
	check(game.objectives_panel.visible and p.ui_open, "objective board opens the objectives panel")
	check(game.objectives_panel.board_text().contains("Stock up"), "board shows the current objective")
	game.objectives_panel.close()
	game.get_node("World/Map/Stash").get_node("Interact").interact(p)
	check(game.stash_panel.visible, "stash opens the stash panel")
	game.stash_panel.close()
	check(not p.ui_open, "control returns after closing")
	var hud: CanvasLayer = game.get_node("HUD")
	check(hud.objective_label != null and hud.objective_label.text.contains("Stock up"), "HUD shows the current objective")
	game.queue_free()
