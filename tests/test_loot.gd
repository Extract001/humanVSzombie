extends "res://tests/test_case.gd"
## Phase 5: searching containers, one-time seeded rolls, no duplication, full bag, quest guarantees.

const DESIGNATED: Array[String] = [
	"grocery_shelf_01", "grocery_shelf_02", "grocery_shelf_03", "grocery_shelf_04",
	"house_a_kitchen", "house_b_kitchen", "pharmacy_counter_01", "pharmacy_cabinet_01",
	"pharmacy_cabinet_02", "vehicle_trunk_pickup_01", "warehouse_office_locker",
]


func _container(parent: Node, id: String, type: String, pos: Vector2) -> LootContainer:
	var c: LootContainer = load("res://scenes/world/loot_container.tscn").instantiate()
	c.container_id = StringName(id)
	c.container_type = StringName(type)
	c.position = pos
	parent.add_child(c)
	return c


func _total(items: Array) -> Dictionary:
	var t := {}
	for e in items:
		t[e.id] = int(t.get(e.id, 0)) + int(e.qty)
	return t


## The map's containers: id -> type.
func _map_containers() -> Dictionary:
	var m: Node = load("res://scenes/world/ashford_lane.tscn").instantiate()
	var out := {}
	for c in m.get_node("Containers").get_children():
		if c is LootContainer:
			out[String(c.container_id)] = c.container_type
	m.free()
	return out


func test_search_takes_time_then_opens_and_makes_noise() -> void:
	GameState.new_game(7)
	var sb := make_sandbox()
	var p := spawn_player(sb, Vector2(100, 100))
	var c := _container(sb, "test_box", "grocery_shelf", Vector2(100, 116))
	var z := spawn_walker(sb, Vector2(100, 50), Vector2.UP)  # 50 px away, facing away
	await physics_frames(2)
	var opened := [null]
	p.loot_opened.connect(func(x: LootContainer) -> void: opened[0] = x)
	c.get_node("Interact").interact(p)
	check(p.is_searching(), "searching started")
	check_eq(p.state, Player.State.NORMAL, "searching is not a separate player state")
	check(not GameState.is_rolled(&"test_box"), "nothing rolled before the search ends")
	check_eq(z.state, Zombie.State.INVESTIGATE, "a Walker 50 px away hears the 60 px rummaging")
	z.queue_free()  # (it would turn round, see the player and attack - not what this test is about)
	await physics_frames(5)
	check_near(c.get_search_time(), 0.8, 0.001, "grocery shelf search time 0.8 s")
	await physics_frames(30)
	check(opened[0] == null and p.search_progress() > 0.5, "still searching at ~0.6 s")
	await physics_frames(15)
	check(opened[0] == c, "loot opened when the search completed")
	check(GameState.is_rolled(&"test_box"), "contents rolled once")
	check(not p.is_searching(), "search finished")


func test_search_cancelled_by_moving_damage_attack_or_shove_grants_nothing() -> void:
	GameState.new_game(7)
	var sb := make_sandbox()
	var p := spawn_player(sb, Vector2(100, 100))
	var c := _container(sb, "test_box", "vehicle_trunk", Vector2(100, 116))
	await physics_frames(2)
	var bag_before: int = p.inventory.used_slots()
	# moving
	c.get_node("Interact").interact(p)
	await physics_frames(10)
	p.move_override = Vector2.RIGHT
	await physics_frames(2)
	p.move_override = Vector2.INF
	check(not p.is_searching(), "moving cancels")
	# damage
	c.get_node("Interact").interact(p)
	await physics_frames(10)
	p.health.take_damage(5.0)
	check(not p.is_searching(), "a hit cancels")
	# attack
	c.get_node("Interact").interact(p)
	await physics_frames(10)
	p.try_attack()
	check(not p.is_searching(), "attacking cancels")
	await physics_frames(40)
	# shove
	c.get_node("Interact").interact(p)
	await physics_frames(10)
	p.try_shove()
	check(not p.is_searching(), "shoving cancels")
	await physics_frames(130)  # longer than the 2 s trunk search
	check(not GameState.is_rolled(&"test_box"), "cancelled searches never roll or grant loot")
	check_eq(p.inventory.used_slots(), bag_before, "bag unchanged")


func test_reopening_never_duplicates() -> void:
	GameState.new_game(3)
	var guaranteed := {&"food_can": 2, &"water_bottle": 1}
	var first: Array = GameState.roll_container(&"grocery_shelf_01", &"grocery_shelf", guaranteed).duplicate(true)
	for i in 20:
		var again: Array = GameState.roll_container(&"grocery_shelf_01", &"grocery_shelf", guaranteed)
		check_eq(_total(again), _total(first), "reopen #%d gives the same contents" % i)
	var inv := Inventory.new()
	add_child(inv)
	GameState.take_all(&"grocery_shelf_01", inv)
	var after: Array = GameState.roll_container(&"grocery_shelf_01", &"grocery_shelf", guaranteed)
	check(after.is_empty(), "after taking everything, reopening finds it empty (no re-roll)")
	for id in _total(first):
		check_eq(inv.count(id), _total(first)[id], "took exactly what was there: " + id)


func test_full_bag_leaves_the_rest_in_the_container() -> void:
	GameState.new_game(3)
	var inv := Inventory.new()
	inv.capacity_slots = 1
	add_child(inv)
	inv.add_item(&"food_can", 3)  # 1 slot, room for 2 more food
	GameState.roll_container(&"box", &"backpack", {&"food_can": 4, &"water_bottle": 2})
	check(not GameState.take_all(&"box", inv), "not everything fit")
	check_eq(inv.count(&"food_can"), 5, "food topped up to the stack limit")
	check_eq(_total(GameState.get_contents(&"box")), {&"food_can": 2, &"water_bottle": 2}, "the rest stayed in the container")
	inv.remove_item(&"food_can", 5)
	GameState.take_all(&"box", inv)
	check_eq(inv.count(&"food_can") + inv.count(&"water_bottle"), 2, "space freed -> more can be taken (1 slot)")


func test_rolls_are_seeded_and_per_container() -> void:
	GameState.new_game(42)
	var a: Dictionary = _total(GameState.roll_container(&"x1", &"storage_box", {}))
	GameState.new_game(42)
	var b: Dictionary = _total(GameState.roll_container(&"x1", &"storage_box", {}))
	check_eq(a, b, "same seed + same container -> same loot")
	# Over many seeds, a table produces varied results (including empty ones).
	var empty := 0
	var kinds := {}
	for s in 200:
		GameState.new_game(s)
		var items: Array = GameState.roll_container(&"x1", &"storage_box", {})
		if items.is_empty():
			empty += 1
		for e in items:
			kinds[e.id] = true
			check(e.qty > 0, "never zero/negative quantities")
	check(empty > 30 and empty < 120, "storage boxes are sometimes empty (%d / 200)" % empty)
	check(kinds.size() >= 3, "several item kinds appear (%d)" % kinds.size())


func test_guaranteed_items_present_for_1000_seeds() -> void:
	var types: Dictionary = _map_containers()
	var data: QuestGuarantees = QuestGuarantees.get_data()
	for id in DESIGNATED:
		check(data.guarantees.has(id), "quest_guarantees.tres lists " + id)
		check(types.has(id), "designated container is in the map: " + id)
	for id in data.guarantees:
		check(DESIGNATED.has(id), "every guarantee entry is a designated container: " + id)
	var missing := 0
	for s in 1000:
		GameState.new_game(s)
		for id in DESIGNATED:
			var got: Dictionary = _total(GameState.roll_container(StringName(id), types.get(id, &""),
				QuestGuarantees.for_container(StringName(id))))
			var want: Dictionary = QuestGuarantees.for_container(StringName(id))
			for item in want:
				if int(got.get(item, 0)) < want[item]:
					missing += 1
	check_eq(missing, 0, "every guaranteed item present in every designated container, 1000 seeds")


func test_map_containers_pick_up_their_guarantees() -> void:
	GameState.new_game(5)
	var m: Node = load("res://scenes/world/ashford_lane.tscn").instantiate()
	add_child(m)
	await physics_frames(1)
	var c: LootContainer = m.get_node("Containers/C_vehicle_trunk_pickup_01")
	check_eq(c.all_guaranteed_items(), {&"bolt_cutters": 1}, "truck bed guarantees the bolt cutters")
	check(_total(c.open_contents()).get(&"bolt_cutters", 0) == 1, "opening it yields the bolt cutters")
	var l: LootContainer = m.get_node("Containers/C_warehouse_office_locker")
	check(_total(l.open_contents()).get(&"radio_part", 0) == 1, "office locker yields the radio component")
	check_near(c.get_search_time(), 2.0, 0.001, "vehicle trunk search 2.0 s")
	check_near(l.get_search_time(), 1.2, 0.001, "locker search 1.2 s")
	m.queue_free()


func test_guaranteed_totals_cover_objectives() -> void:
	var food: int = QuestGuarantees.total(&"food_can")
	var water: int = QuestGuarantees.total(&"water_bottle")
	var medical: int = QuestGuarantees.total(&"bandage") + QuestGuarantees.total(&"medkit")
	check(food >= 7, "guaranteed food >= 7 (objective needs 5): %d" % food)
	check(water >= 5, "guaranteed water >= 5 (objective needs 3): %d" % water)
	check(medical >= 4, "guaranteed medical >= 4 (objective needs 2): %d" % medical)
	check_eq(QuestGuarantees.total(&"bolt_cutters"), 1, "exactly one bolt cutters")
	check_eq(QuestGuarantees.total(&"radio_part"), 1, "exactly one radio component")


func test_loot_tables_only_use_known_items() -> void:
	var known := {}
	for item in ItemRegistry.all_items():
		known[item.id] = item
	var types := _map_containers()
	for id in types:
		if types[id] == &"":
			continue
		var table: LootTable = LootTableRegistry.get_table(types[id])
		check(table != null, "container %s has a loot table (%s)" % [id, types[id]])
		if table == null:
			continue
		for item_id in table.item_ids:
			check(known.has(StringName(item_id)), "table %s item exists: %s" % [types[id], item_id])
			if known.has(StringName(item_id)):
				check(not known[StringName(item_id)].is_quest_item, "quest items never come from random tables")


func test_loot_panel_take_all_in_game() -> void:
	GameState.new_game(11)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(5)
	var p: Player = game.get_node("World/Actors/Player")
	var c: LootContainer = game.get_node("World/Map/Containers/C_grocery_shelf_01")
	p.global_position = c.global_position + Vector2(0, 14)
	p.inventory.take_all()
	await physics_frames(2)
	check(p.start_search(c, c.get_search_time()), "search started")
	await physics_frames(55)
	var panel: CanvasLayer = game.get_node("LootPanel")
	check(panel.visible, "loot panel open after the search")
	check(p.ui_open, "player input goes to the panel")
	panel.take_all()
	check(p.inventory.count(&"food_can") >= 2 and p.inventory.count(&"water_bottle") >= 1,
		"guaranteed food and water now in the bag")
	panel.close()
	check(not p.ui_open, "closing gives control back")
	var inv_panel: CanvasLayer = game.get_node("InventoryPanel")
	inv_panel.open()
	check(inv_panel.visible and p.ui_open, "inventory panel opens")
	inv_panel.close()
	check(not p.ui_open, "inventory panel closes")
	game.queue_free()
