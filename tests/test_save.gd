extends "res://tests/test_case.gd"
## Phase 10: save/load round trips, broken and old saves, autosave points, Continue.
## Uses the runner's test save path (never the player's real save).


func _clear() -> void:
	for ext in ["", ".tmp", ".bak", ".broken", ".bak.broken"]:
		if FileAccess.file_exists(SaveSystem.path + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.path + ext))
	SaveSystem.pending_player = {}
	SaveSystem.fresh_start = false


func _game() -> Node:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _write(text: String) -> void:
	var f := FileAccess.open(SaveSystem.path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_world_state_round_trip_is_identical() -> void:
	_clear()
	GameState.new_game(77)
	GameState.roll_container(&"grocery_shelf_01", &"grocery_shelf", {&"food_can": 2})
	var inv := Inventory.new()
	add_child(inv)
	GameState.take_from(&"grocery_shelf_01", &"food_can", 1, inv)
	GameState.create_pile(Vector2(123.5, 456.25), [{"id": &"bolt_cutters", "qty": 1}, {"id": &"scrap", "qty": 3}], true)
	GameState.create_pile(Vector2(10, 20), [{"id": &"bandage", "qty": 1}], false)
	GameState.stash_add(&"water_bottle", 4)
	GameState.add_unlock(&"warehouse_gate")
	GameState.objectives_completed.append(&"stock_up")
	GameState.day = 3
	GameState.flashlight_charge = 97.5
	GameState.stats.kills = 9
	var before: Dictionary = GameState.to_dict()
	check_eq(SaveSystem.save_game({"player": {}, "world": before, "game": {}}, "test"), OK, "saved")
	check(not FileAccess.file_exists(SaveSystem.path + ".tmp"), "no temp file left behind")
	GameState.new_game(1)  # wipe
	var r: Dictionary = SaveSystem.load_game()
	check(r.ok, "loaded")
	var after: Dictionary = GameState.to_dict()
	check_eq(JSON.stringify(after), JSON.stringify(before), "GameState identical after save -> load (containers, backpacks, quest item, stash, unlocks, objectives, day)")
	check_eq(GameState.backpack_ids().size(), 1, "backpack restored")
	check_eq(GameState.get_contents(GameState.backpack_ids()[0])[0].id, &"bolt_cutters", "quest item still in the backpack")
	check(GameState.piles.values()[0].position.is_equal_approx(Vector2(123.5, 456.25)) or GameState.piles.values()[1].position.is_equal_approx(Vector2(123.5, 456.25)), "backpack position exact")
	check(GameState.create_pile(Vector2.ZERO, [{"id": &"scrap", "qty": 1}], false) == &"pile_3", "pile numbering continues (no id clash)")
	_clear()


func test_full_game_round_trip_after_death() -> void:
	_clear()
	GameState.new_game(5)
	var game := _game()
	await physics_frames(3)
	var p: Player = game.get_node("World/Actors/Player")
	# Some progress: stash, a searched shelf, a cut gate, a dead zombie, an open door, then death outside.
	GameState.stash_add(&"scrap", 2)
	GameState.stash_add(&"food_can", 5)    # completes "Stock up"
	GameState.stash_add(&"water_bottle", 3)
	game.get_node("World/Map/Containers/C_grocery_shelf_01").open_contents()
	p.inventory.add_item(&"bolt_cutters", 1)
	game.get_node("World/Map/WarehouseGate").toggle(p)
	var z: Zombie = game.get_node("World/Actors/Walker1")
	z.health.take_damage(1000.0)
	game.get_node("World/Map/YardGate").toggle(p)
	p.inventory.add_item(&"radio_part", 1)
	p.weapons.rounds_in_mag[1] = 5
	p.global_position = Vector2(78, 58) * 16.0
	await physics_frames(2)
	p.health.take_damage(1000.0)
	await physics_frames(2)
	check(FileAccess.file_exists(SaveSystem.path), "death saved immediately")
	check_eq(SaveSystem.read_save().data.reason, "death", "save reason is the death")
	game.queue_free()
	await physics_frames(2)
	# "Quit and Continue"
	GameState.new_game(1)
	check(SaveSystem.load_game().ok, "Continue loads")
	var again := _game()
	await physics_frames(3)
	var p2: Player = again.get_node("World/Actors/Player")
	var bed: Vector2 = again.get_node("World/Map/RespawnPoint").global_position
	check(p2.global_position.distance_to(bed) < 1.0, "woke up at the bed (the save was made on death)")
	check_eq(p2.health.current_health, 75.0, "with 75 HP")
	check(not p2.is_dead(), "alive")
	check_eq(p2.inventory.used_slots(), 0, "bag empty: everything is in the backpack")
	check_eq(p2.weapons.rounds_in_mag[1], 5, "loaded pistol rounds kept")
	check_eq(GameState.backpack_ids().size(), 1, "backpack still out there")
	var in_pack := {}
	for e in GameState.get_contents(GameState.backpack_ids()[0]):
		in_pack[e.id] = e.qty
	check_eq(in_pack.get(&"radio_part", 0), 1, "quest item in the saved backpack")
	check_eq(again.get_node("World/Piles").get_child_count(), 1, "backpack node spawned")
	check_eq(GameState.stash_count(&"scrap"), 2, "stash kept")
	check(GameState.is_rolled(&"grocery_shelf_01"), "searched shelf stays searched")
	var gate: Door = again.get_node("World/Map/WarehouseGate")
	check(not gate.locked and gate.is_open, "cut gate stays open")
	check(again.get_node("World/Actors").get_node_or_null("Walker1") == null or again.get_node("World/Actors/Walker1").is_queued_for_deletion(), "killed zombie stays dead")
	check(again.get_node("World/Map/YardGate").is_open, "opened yard gate still open")
	check(again.objectives.is_completed(&"stock_up"), "objective progress kept")
	check_eq(again.objectives.current().id, &"first_aid", "next objective still current")
	check_eq(GameState.stats.deaths, 1, "death count kept")
	again.queue_free()
	_clear()


func test_broken_and_empty_saves_start_fresh_without_crashing() -> void:
	_clear()
	_write("{ this is not json")
	var r: Dictionary = SaveSystem.read_save()
	check(not r.ok and r.message.contains("damaged"), "broken save reported: " + r.message)
	r = SaveSystem.load_game()
	check(not r.ok, "load refused")
	check(FileAccess.file_exists(SaveSystem.path + ".broken"), "broken file kept as .broken (not deleted)")
	check(not SaveSystem.has_save(), "menu no longer offers it")
	_write("")
	check(not SaveSystem.read_save().ok and SaveSystem.read_save().message != "", "empty file reported")
	_write("[1, 2, 3]")
	check(not SaveSystem.read_save().ok, "wrong shape reported")
	_write("{\"version\": 1}")
	check(SaveSystem.read_save().message.contains("incomplete"), "missing parts reported")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await physics_frames(2)
	menu.continue_game()
	check(menu.get_node("Dialog").visible, "menu shows a message instead of crashing")
	check(menu.continue_button.disabled, "Continue disabled afterwards")
	menu.queue_free()
	_clear()


func test_old_save_is_migrated_and_newer_save_is_rejected() -> void:
	_clear()
	var v0 := {"version": 0, "player": {"x": 100, "y": 100, "dead": false, "health": 60, "inventory": [{"id": "scrap", "qty": 2}]},
		"world_seed": 4, "stash": {"food_can": 3}, "unlocks": ["warehouse_gate"], "containers": {}, "piles": {}}
	_write(JSON.stringify(v0))
	var r: Dictionary = SaveSystem.load_game()
	check(r.ok, "version 0 save loads (migrated)")
	check_eq(int(r.data.version), SaveSystem.VERSION, "upgraded to the current version")
	check_eq(GameState.day, 1, "missing day filled in")
	check_eq(GameState.stash_count(&"food_can"), 3, "old stash kept")
	check(GameState.has_unlock(&"warehouse_gate"), "old unlocks kept")
	SaveSystem.pending_player = {}
	_write(JSON.stringify({"version": 99, "player": {}, "world": {}}))
	r = SaveSystem.load_game()
	check(not r.ok and r.message.contains("newer"), "newer save rejected: " + r.message)
	check(FileAccess.file_exists(SaveSystem.path), "newer save left untouched")
	_clear()


func test_save_replaces_old_file_safely() -> void:
	_clear()
	GameState.new_game(1)
	SaveSystem.save_game({"player": {"x": 1}, "world": GameState.to_dict(), "game": {}}, "first")
	GameState.day = 7
	SaveSystem.save_game({"player": {"x": 2}, "world": GameState.to_dict(), "game": {}}, "second")
	var r: Dictionary = SaveSystem.read_save()
	check_eq(int(r.data.world.day), 7, "newest save wins")
	check(not FileAccess.file_exists(SaveSystem.path + ".bak") and not FileAccess.file_exists(SaveSystem.path + ".tmp"), "no leftovers")
	# A save interrupted after the old file was moved aside: the .bak is still used.
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SaveSystem.path), ProjectSettings.globalize_path(SaveSystem.path + ".bak"))
	check(SaveSystem.read_save().ok, "falls back to the previous save (.bak)")
	_clear()


func test_autosave_on_entering_safehouse_and_sleeping_not_outside() -> void:
	_clear()
	GameState.new_game(1)
	var game := _game()
	await physics_frames(3)
	var p: Player = game.get_node("World/Actors/Player")
	check(not FileAccess.file_exists(SaveSystem.path), "no save just for loading a scene")
	p.global_position = Vector2(78, 58) * 16.0  # street
	await physics_frames(3)
	check(not FileAccess.file_exists(SaveSystem.path), "no saving mid-expedition")
	p.global_position = Vector2(78, 70) * 16.0  # back inside
	await physics_frames(3)
	check(FileAccess.file_exists(SaveSystem.path), "walking into the safehouse saves")
	check_eq(SaveSystem.last_save_reason, "safehouse", "reason: safehouse")
	p.health.take_damage(30.0)
	check(game.try_sleep(), "slept")
	check_eq(SaveSystem.last_save_reason, "bed", "sleeping saves")
	check_eq(int(SaveSystem.read_save().data.world.day), 2, "the new day is in the save")
	game.queue_free()
	_clear()


func test_new_game_replaces_save_and_continue_shows_day() -> void:
	_clear()
	GameState.new_game(1)
	GameState.day = 4
	SaveSystem.save_game({"player": {}, "world": GameState.to_dict(), "game": {}}, "bed")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await physics_frames(2)
	check(not menu.continue_button.disabled, "Continue enabled with a save")
	check(menu.continue_button.has_focus(), "Continue focused")
	check(menu.save_label.text.contains("Day 4"), "shows the saved day: " + menu.save_label.text)
	menu.ask_new_game()
	check(menu.get_node("Dialog").visible, "New game asks before replacing the save")
	menu.queue_free()
	# What New game does after confirming (without changing scene): fresh start saves right away.
	GameState.new_game(2)
	SaveSystem.fresh_start = true
	var game := _game()
	await physics_frames(3)
	check_eq(SaveSystem.read_save().data.reason, "new_game", "new game saved immediately")
	check_eq(int(SaveSystem.read_save().data.world.day), 1, "old save (day 4) replaced")
	game.queue_free()
	_clear()
