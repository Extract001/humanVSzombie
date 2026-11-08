extends "res://tests/test_case.gd"
## Phase 5: death backpack (in-session) and respawn.
## Rule (owner decision): carried bag items -> backpack at the death spot; equipped weapons and the
## rounds loaded in them stay with you; quest items go in the backpack; several backpacks can exist.


func _contents_total(id: StringName) -> Dictionary:
	var t := {}
	for e in GameState.get_contents(id):
		t[e.id] = int(t.get(e.id, 0)) + int(e.qty)
	return t


func test_death_moves_bag_into_backpack_and_keeps_weapons() -> void:
	GameState.new_game(1)
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	p.inventory.add_item(&"food_can", 3)
	p.inventory.add_item(&"radio_part", 1)
	var loaded: int = p.weapons.rounds_in_mag[1]
	var weapon_count: int = p.weapons.slots.size()
	p.health.take_damage(1000.0)
	await physics_frames(1)
	check_eq(p.inventory.used_slots(), 0, "bag emptied")
	check_eq(GameState.backpack_ids().size(), 1, "one backpack")
	var bp: StringName = GameState.backpack_ids()[0]
	check_eq(_contents_total(bp), {&"ammo_pistol": 16, &"bandage": 2, &"food_can": 3, &"radio_part": 1},
		"backpack holds everything that was carried (totals conserved, quest item included)")
	check_eq(p.weapons.slots.size(), weapon_count, "equipped weapons kept")
	check_eq(p.weapons.rounds_in_mag[1], loaded, "loaded pistol rounds kept")
	check_eq(GameState.stats.deaths, 1, "death counted")


func test_backpack_is_snapped_onto_navigation() -> void:
	GameState.new_game(1)
	var sb := make_sandbox()
	var wall: Rect2 = Rect2(160, 60, 40, 80)
	add_wall(sb, wall)
	await add_navigation(sb, Rect2(0, 0, 400, 300))
	var p := spawn_player(sb, Vector2(120, 100))
	await physics_frames(2)
	p.global_position = Vector2(180, 100)  # forced inside the wall (e.g. pushed into a corner)
	p.health.take_damage(1000.0)
	await physics_frames(1)
	var pos: Vector2 = GameState.piles[GameState.backpack_ids()[0]].position
	check(not wall.grow(-1.0).has_point(pos), "backpack not inside the wall (at %s)" % str(pos))
	var map: RID = sb.get_world_2d().navigation_map
	check(NavigationServer2D.map_get_closest_point(map, pos).distance_to(pos) < 1.0, "backpack is on the navigation mesh")


func test_two_deaths_two_backpacks_and_quest_items_recovered() -> void:
	GameState.new_game(1)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(5)
	var p: Player = game.get_node("World/Actors/Player")
	p.inventory.add_item(&"bolt_cutters", 1)
	p.health.take_damage(1000.0)
	await physics_frames(70)
	check(game.get_node("GameOver").visible, "death screen shown")
	game.respawn_player()
	await physics_frames(2)
	p.global_position += Vector2(48, 0)
	p.inventory.add_item(&"radio_part", 1)
	p.inventory.add_item(&"scrap", 4)
	p.health.take_damage(1000.0)
	await physics_frames(2)
	var ids: Array = GameState.backpack_ids()
	check_eq(ids.size(), 2, "dying twice before recovery -> two backpacks")
	check_eq(game.get_node("World/Piles").get_child_count(), 2, "both backpacks exist in the world")
	var all := {}
	for id in ids:
		for e in GameState.get_contents(id):
			all[e.id] = int(all.get(e.id, 0)) + int(e.qty)
	check_eq(all.get(&"bolt_cutters", 0), 1, "first backpack kept the bolt cutters")
	check_eq(all.get(&"radio_part", 0), 1, "second backpack has the radio component")
	await physics_frames(70)
	game.respawn_player()
	await physics_frames(2)
	for id in ids:
		GameState.take_all(id, p.inventory)
	await physics_frames(2)
	check_eq(p.inventory.count(&"bolt_cutters"), 1, "bolt cutters recovered")
	check_eq(p.inventory.count(&"radio_part"), 1, "radio component recovered")
	check(GameState.backpack_ids().is_empty(), "emptied backpacks removed from GameState")
	await physics_frames(1)
	var left := 0
	for n in game.get_node("World/Piles").get_children():
		if not n.is_queued_for_deletion():
			left += 1
	check_eq(left, 0, "emptied backpacks removed from the world")
	game.queue_free()


func test_respawn_at_75_hp_normal_full_stamina() -> void:
	GameState.new_game(1)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(5)
	var p: Player = game.get_node("World/Actors/Player")
	p.global_position += Vector2(0, -400)  # die somewhere out in the street
	p.spend_stamina(60.0)
	p.health.take_damage(1000.0)
	await physics_frames(70)
	var go: CanvasLayer = game.get_node("GameOver")
	check(go.get_node("%RespawnButton") is Button, "respawn button on the death screen")
	go.get_node("%RespawnButton").emit_signal(&"pressed")
	await physics_frames(2)
	var bed: Vector2 = game.get_node("World/Map/RespawnPoint").global_position
	check(p.global_position.distance_to(bed) < 1.0, "respawned at the safehouse bed point")
	check_eq(p.health.current_health, 75.0, "75 HP")
	check_eq(p.state, Player.State.NORMAL, "NORMAL state")
	check_eq(p.stamina, p.stats.max_stamina, "full stamina")
	check(not go.visible, "death screen hidden")
	check(p.hurtbox.monitorable, "can be hit again (no lingering death state)")
	check(p.try_attack(), "can act again")
	var hud: CanvasLayer = game.get_node("HUD")
	check_eq(hud.get_node("%HealthBar").value, 75.0, "HUD shows 75")
	await physics_frames(2)
	var marker: Control = hud.backpack_marker
	check(marker.visible, "HUD arrow shown while a backpack is out there")
	check(marker.distance_metres() > 20, "arrow reports the distance (%d m)" % marker.distance_metres())
	game.queue_free()
