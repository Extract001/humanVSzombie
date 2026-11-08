extends "res://tests/test_case.gd"
## Phase 6: running noise, noise meter + rings, flashlight + batteries, darkness/flashlight vs zombie sight.


func _collect_noises() -> Array:
	var heard: Array = []
	NoiseSystem.noise_emitted.connect(func(pos: Vector2, r: float, src: Node) -> void:
		heard.append({"pos": pos, "radius": r, "source": src}))
	return heard


func test_walking_is_silent_running_is_heard_at_120() -> void:
	var p := spawn_player(make_sandbox(), Vector2(200, 200))
	await physics_frames(2)
	var heard: Array = _collect_noises()
	p.move_override = Vector2.RIGHT
	await physics_frames(60)
	var from_player := heard.filter(func(n: Dictionary) -> bool: return n.source == p)
	check_eq(from_player.size(), 0, "1 s of walking makes no noise")
	Input.action_press(&"run")
	await physics_frames(60)
	Input.action_release(&"run")
	p.move_override = Vector2.INF
	from_player = heard.filter(func(n: Dictionary) -> bool: return n.source == p)
	check(from_player.size() >= 2 and from_player.size() <= 4, "1 s of running: a noise every 0.4 s (%d)" % from_player.size())
	for n in from_player:
		check_eq(n.radius, 120.0, "running noise radius 120 px")


func test_walking_past_a_zombies_back_vs_running() -> void:
	var sb := make_sandbox()
	# Walker facing up; the player passes 60 px behind it (outside the 24 px close sense).
	var z := spawn_walker(sb, Vector2(300, 200), Vector2.UP)
	var p := spawn_player(sb, Vector2(200, 260))
	await physics_frames(2)
	p.move_override = Vector2.RIGHT
	await physics_frames(90)  # walks 120 px, passing behind it
	check(z.state == Zombie.State.IDLE, "walking past its back: not noticed (state %d)" % z.state)
	p.move_override = Vector2.ZERO
	p.global_position = Vector2(200, 260)
	await physics_frames(2)
	p.move_override = Vector2.RIGHT
	Input.action_press(&"run")
	await physics_frames(30)
	Input.action_release(&"run")
	p.move_override = Vector2.INF
	check(z.state == Zombie.State.INVESTIGATE or z.state == Zombie.State.CHASE,
		"running past its back: it hears and turns (state %d)" % z.state)


func test_darkness_and_flashlight_change_sight_range() -> void:
	GameState.new_game(1)
	var sb := make_sandbox()
	var z := spawn_walker(sb, Vector2(200, 200), Vector2.RIGHT)
	var p := spawn_player(sb, Vector2(320, 200))  # 120 px in front of it
	await physics_frames(2)
	check(z.can_see(p), "lit area: seen at 120 px (range 160)")
	p.enter_darkness()
	check_near(z.sight_multiplier_for(p), 0.5, 0.001, "darkness, light off: ×0.5")
	check(not z.can_see(p), "darkness, light off: not seen at 120 px (range 80)")
	p.set_flashlight(true)
	check_near(z.sight_multiplier_for(p), 1.5, 0.001, "darkness, light on: ×1.5")
	check(z.can_see(p), "darkness, light on: seen at 120 px")
	p.global_position = Vector2(420, 200)  # 220 px
	check(z.can_see(p), "darkness, light on: seen at 220 px (range 240)")
	p.exit_darkness()
	check_near(z.sight_multiplier_for(p), 1.0, 0.001, "lit area: flashlight changes nothing")
	check(not z.can_see(p), "lit area: 220 px is beyond the normal 160 px")


func test_flashlight_battery_drain_swap_and_dead() -> void:
	GameState.new_game(1)
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	check(not p.flashlight_on and not p.flashlight.enabled, "starts off")
	check_near(p.flashlight_charge(), 180.0, 0.001, "starts with a full 3-minute battery")
	check(p.toggle_flashlight(), "F turns it on")
	check(p.flashlight.enabled, "light node enabled")
	await physics_frames(60)
	check_near(p.flashlight_charge(), 179.0, 0.05, "drains 1 s per second")
	p.inventory.add_item(&"battery", 1)
	GameState.flashlight_charge = 0.05
	await physics_frames(10)
	check(p.flashlight_on, "a spare battery is swapped in automatically")
	check_eq(p.inventory.count(&"battery"), 0, "spare battery used")
	check(p.flashlight_charge() > 179.0, "full charge again")
	var msgs: Array = []
	p.message.connect(func(t: String) -> void: msgs.append(t))
	GameState.flashlight_charge = 0.05
	await physics_frames(10)
	check(not p.flashlight_on and not p.flashlight.enabled, "no spare: the light goes out")
	check(msgs.has("Flashlight battery is dead"), "player is told why")
	check(not p.toggle_flashlight(), "can't switch on with a dead battery and no spare")
	check(msgs.has("No batteries"), "player is told there are no batteries")
	p.inventory.add_item(&"battery", 1)
	check(p.toggle_flashlight(), "picking up a battery lets you switch on again")


func test_flashlight_aims_and_turns_off_on_death() -> void:
	GameState.new_game(1)
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(1)
	p.aim_direction = Vector2.LEFT
	p.set_flashlight(true)
	await physics_frames(2)
	check_near(absf(p.flashlight.rotation), PI, 0.01, "beam follows the aim")
	check(p.flashlight.shadow_enabled, "beam casts shadows (walls, shelves, doors)")
	var charge: float = p.flashlight_charge()
	p.health.take_damage(1000.0)
	await physics_frames(1)
	check(not p.flashlight_on, "light off when you die")
	check_near(p.flashlight_charge(), charge, 0.1, "the flashlight (equipment) keeps its battery")


func test_occluders_on_walls_shelves_crates_and_doors() -> void:
	var m: Node = load("res://scenes/world/ashford_lane.tscn").instantiate()
	var layers: Array = m.find_children("*", "TileMapLayer", true, false)
	var ts: TileSet = (layers[0] as TileMapLayer).tile_set
	var src := ts.get_source(0) as TileSetAtlasSource
	for tile in [Vector2i(6, 0), Vector2i(7, 0), Vector2i(9, 0)]:  # wall, crate, shelf
		var td: TileData = src.get_tile_data(tile, 0)
		check(td.get_occluder_polygons_count(0) > 0 if td.has_method(&"get_occluder_polygons_count") else td.get_occluder(0) != null,
			"tile %s blocks light" % str(tile))
	var door: Node = m.find_child("WarehouseDoor", true, false)
	check(door != null and door.find_child("Occluder", true, false) is LightOccluder2D, "doors block light")
	m.free()


func test_noise_rings_and_meter() -> void:
	GameState.new_game(1)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(5)
	var p: Player = game.get_node("World/Actors/Player")
	var rings: Node2D = game.get_node("World/NoiseRings")
	NoiseSystem.emit_noise(p.global_position, 40.0, p)
	check_eq(rings.rings.size(), 0, "tiny noises (shove) don't draw a ring")
	NoiseSystem.emit_noise(p.global_position, 140.0, game.get_node("World/Actors/Walker1"))
	check_eq(rings.rings.size(), 0, "zombie groans don't draw rings")
	NoiseSystem.emit_noise(p.global_position, 480.0, p)
	check_eq(rings.rings.size(), 1, "a gunshot draws a ring")
	var hud: CanvasLayer = game.get_node("HUD")
	await physics_frames(2)
	check_near(hud.noise_bar.value, 100.0, 0.5, "meter full after a gunshot")
	check(hud.noise_label.text.ends_with("LOUD"), "meter says LOUD")
	await physics_frames(60)
	check(rings.rings.is_empty(), "ring gone after about a second")
	await physics_frames(60)
	check_near(hud.noise_bar.value, 0.0, 0.5, "meter back to quiet after the noise fades")
	check(hud.noise_label.text.ends_with("quiet"), "meter says quiet")
	p.set_flashlight(true)
	check(hud.light_label.text.begins_with("LIGHT on"), "HUD shows the flashlight is on")
	check_near(hud.light_bar.value, 100.0, 1.0, "HUD battery full")
	game.queue_free()
