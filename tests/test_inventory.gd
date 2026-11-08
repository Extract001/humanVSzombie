extends "res://tests/test_case.gd"
## Phase 5: slot inventory (stacking, capacity, never negative), items (use, drop, quest rules).


func _bag(slots: int = 12) -> Inventory:
	var inv := Inventory.new()
	inv.capacity_slots = slots
	add_child(inv)
	return inv


func test_stacking_respects_max_stack() -> void:
	var inv := _bag()
	check_eq(inv.add_item(&"bandage", 7), 0, "7 bandages all fit")
	check_eq(inv.count(&"bandage"), 7, "count 7")
	check_eq(inv.used_slots(), 2, "max stack 5 -> two slots (5 + 2)")
	check_eq(inv.slots[0].qty, 5, "first stack is full")
	inv.add_item(&"bandage", 3)
	check_eq(inv.used_slots(), 2, "tops up the existing stack before opening a new slot")
	check_eq(inv.count(&"bandage"), 10, "count 10")
	check_eq(inv.add_item(&"bolt_cutters", 1), 0, "quest item added")
	check_eq(inv.used_slots(), 3, "max stack 1 -> own slot")


func test_full_bag_reports_leftover_and_never_goes_negative() -> void:
	var inv := _bag()
	check_eq(inv.add_item(&"scrap", 12 * 20 + 7), 7, "12 slots x 20 scrap fit; 7 reported back")
	check_eq(inv.count(&"scrap"), 240, "240 scrap carried")
	check_eq(inv.space_for(&"food_can"), 0, "no room for anything else")
	check_eq(inv.add_item(&"food_can", 2), 2, "a new item type doesn't fit at all")
	check_eq(inv.remove_item(&"scrap", 999), 240, "removing too many removes only what exists")
	check_eq(inv.count(&"scrap"), 0, "count is 0, not negative")
	check_eq(inv.used_slots(), 0, "empty stacks free their slots")
	check_eq(inv.remove_item(&"scrap", 5), 0, "removing from nothing removes nothing")


func test_take_all_empties_bag_and_conserves_totals() -> void:
	var inv := _bag()
	inv.add_item(&"ammo_pistol", 60)  # 48 + 12, two stacks
	inv.add_item(&"water_bottle", 2)
	var out: Array = inv.take_all()
	var totals := {}
	for e in out:
		totals[e.id] = e.qty
	check_eq(totals.get(&"ammo_pistol", 0), 60, "ammo merged into one entry, total kept")
	check_eq(totals.get(&"water_bottle", 0), 2, "water kept")
	check_eq(inv.used_slots(), 0, "bag empty")


func test_player_starts_with_ammo_and_bandages() -> void:
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	check_eq(p.inventory.capacity_slots, 12, "12 slots")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "16 pistol rounds")
	check_eq(p.inventory.count(&"bandage"), 2, "2 bandages")


func test_bandage_heals_over_time_medkit_heals_60() -> void:
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	p.health.take_damage(70.0)
	check(p.use_item(&"bandage"), "bandage used")
	check_eq(p.inventory.count(&"bandage"), 1, "one bandage consumed")
	await physics_frames(60)
	check(p.health.current_health > 30.0 and p.health.current_health < 55.0, "healing gradually (%.1f after 1 s)" % p.health.current_health)
	await physics_frames(150)
	check_near(p.health.current_health, 55.0, 0.5, "bandage healed 25 in total over 3 s")
	p.inventory.add_item(&"medkit", 1)
	check(p.use_item(&"medkit"), "medkit used")
	await physics_frames(75)
	check_near(p.health.current_health, 100.0, 0.5, "medkit heals up to 60 (capped at max)")
	check_eq(p.inventory.count(&"medkit"), 0, "medkit consumed")
	check(not p.use_item(&"bandage"), "can't use at full health")
	check_eq(p.inventory.count(&"bandage"), 1, "refused use consumes nothing")
	check(not p.use_item(&"food_can"), "food isn't usable yet (needs come later)")


func test_quest_items_cannot_be_dropped_or_used() -> void:
	GameState.new_game(1)
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	p.inventory.add_item(&"bolt_cutters", 1)
	p.inventory.add_item(&"radio_part", 1)
	check_eq(p.drop_item(&"bolt_cutters", 1), 0, "bolt cutters can't be dropped")
	check_eq(p.drop_item(&"radio_part", 1), 0, "radio component can't be dropped")
	check(not p.use_item(&"bolt_cutters"), "quest item can't be used up")
	check_eq(p.inventory.count(&"bolt_cutters"), 1, "still carried")
	check_eq(p.inventory.count(&"radio_part"), 1, "still carried")
	check(GameState.piles.is_empty(), "no pile created")
	var item: ItemData = ItemRegistry.get_item(&"bolt_cutters")
	check(item.is_quest_item and not item.can_drop(), "data marks it as quest item")


func test_drop_makes_a_pile_that_disappears_when_emptied() -> void:
	GameState.new_game(1)
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	check_eq(p.drop_item(&"ammo_pistol", 10), 10, "dropped 10 rounds")
	check_eq(p.inventory.count(&"ammo_pistol"), 6, "6 left in the bag")
	check_eq(GameState.piles.size(), 1, "one pile in the world")
	var id: StringName = GameState.piles.keys()[0]
	check(not GameState.piles[id].backpack, "a dropped pile, not a backpack")
	check(GameState.take_all(id, p.inventory), "picked everything back up")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "all 16 rounds back")
	check(GameState.piles.is_empty(), "empty pile removed")


func test_every_item_has_data_and_an_icon() -> void:
	var ids: Array = []
	for item in ItemRegistry.all_items():
		ids.append(item.id)
		check(item.max_stack >= 1, "%s has a stack size" % item.id)
		check(item.description != "", "%s has a description" % item.id)
		check(ItemRegistry.icon(item.id).region.size == Vector2(16, 16), "%s has a 16x16 icon" % item.id)
	for id in [&"food_can", &"water_bottle", &"bandage", &"medkit", &"ammo_pistol", &"ammo_shotgun",
			&"scrap", &"battery", &"bolt_cutters", &"radio_part"]:
		check(ids.has(id), "item exists: " + id)
	check_eq(ItemRegistry.get_item(&"ammo_pistol").max_stack, 48, "pistol rounds stack to 48")
