extends "res://tests/test_case.gd"
## Batch 1 — Brute, Screamer, night events, supply drops.

const BRUTE: ZombieData = preload("res://data/zombies/brute.tres")
const SCREAMER: ZombieData = preload("res://data/zombies/screamer.tres")


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func _spawn(game: Node, data: ZombieData, at: Vector2) -> Zombie:
	var z := spawn_walker(game.get_node("World/Actors"), at, Vector2.LEFT)
	z.data = data
	return z


func test_brute_is_big_tough_and_breaks_things() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var z: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
	z.data = BRUTE
	z.position = p.global_position + Vector2(300, 0)
	game.get_node("World/Actors").add_child(z)
	await physics_frames(2)
	check(z.sprite.scale.x > 1.3, "a head taller")
	check_eq(z.health.current_health, 180.0, "180 health")
	var w: Barricade = game.get_node("World/Map/Barricades/Window_safehouse_west")
	w.set_planks(2)
	w.take_hit(SiegeData.new().zombie_barricade_damage * BRUTE.barricade_damage_mult)
	check_eq(w.planks(), 1, "one Brute hit = one whole plank")
	z.on_hit(0.0, Vector2(300, 0), 0.6, p)
	check(z._stun_left < 0.3, "a shove barely staggers it")
	var door: Door = game.get_node("World/Map/SafehouseDoor")
	door.is_open = false
	check(door.smash_open(), "Brutes burst unlocked doors")
	check(door.is_open, "open")
	var gate: Door = game.get_node("World/Map/WarehouseGate")
	check(not gate.smash_open(), "but never the locked quest gate")
	game.queue_free()
	GameState.new_game(1)


func test_screamer_calls_the_others() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	p.global_position = Vector2(78.5, 58.5) * 16.0
	for zz in get_tree().get_nodes_in_group(&"zombies"):
		zz.queue_free()
	await physics_frames(2)
	var far := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(400, 40), Vector2.RIGHT)
	var s: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
	s.data = SCREAMER
	s.position = p.global_position + Vector2(60, 0)
	s.initial_facing = Vector2.LEFT
	var screamed := [false]
	s.screamed.connect(func() -> void: screamed[0] = true)
	game.get_node("World/Actors").add_child(s)
	await physics_frames(30)
	check(screamed[0], "it screams when it sees you")
	check(far.state == Zombie.State.INVESTIGATE or far.state == Zombie.State.CHASE, "a Walker 400 px away comes running")
	check_eq(GameState.heat, 0.0, "a scream isn't your noise: no Heat")
	game.queue_free()
	GameState.new_game(1)


func test_night_events_are_picked_fairly() -> void:
	check_eq(NightEvents.pick(1, &"none", 5), NightEvents.NONE, "night 1 is always calm")
	var seen := {}
	for s in 40:
		var e: StringName = NightEvents.pick(2, &"none", s)
		check(e != NightEvents.NONE, "night 2 always has an event") if s == 0 else null
		seen[e] = true
		var e2: StringName = NightEvents.pick(3, e, s)
		if e2 == e:
			check(false, "never the same event twice in a row")
	check(seen.size() >= 4, "several kinds of night (%d)" % seen.size())
	check_eq(NightEvents.pick(5, &"fog", 99), NightEvents.pick(5, &"fog", 99), "same world + night = same event (daily runs)")


func test_events_change_the_night() -> void:
	var game := _game()
	await physics_frames(3)
	_player(game).health.setup(1.0e9)
	GameState.nights_survived = 3
	var normal: int = game.day_cycle.horde_estimate()
	GameState.phase = GameState.Phase.DUSK
	GameState.night_event = NightEvents.BLOOD_MOON
	check(game.day_cycle.horde_estimate() >= roundi(normal * 1.4), "Blood Moon: a bigger horde")
	GameState.phase = GameState.Phase.NIGHT
	var z := spawn_walker(game.get_node("World/Actors"), _player(game).global_position + Vector2(300, 0), Vector2.LEFT)
	await physics_frames(1)
	z.hurtbox.receive_hit(1000.0, _player(game))
	check_eq(GameState.score, 20, "Blood Moon: kills score double")
	GameState.night_event = NightEvents.BLACKOUT
	GameState.phase_time = 30.0
	await physics_frames(2)
	check(not game.day_cycle.lamp.enabled, "Blackout: no lamp in the safehouse")
	# Brute night: Brutes in the horde.
	GameState.phase = GameState.Phase.DUSK
	GameState.night_event = NightEvents.BRUTES
	game.day_cycle.start_night()
	GameState.phase_time = 100.0
	await physics_frames(3)
	var brutes := 0
	for h in get_tree().get_nodes_in_group(&"horde"):
		if (h as Zombie).data.id == &"brute":
			brutes += 1
	check_eq(brutes, 1, "Brute night 4: a Brute comes (2 from night 5)")
	game.queue_free()
	GameState.new_game(1)


func test_dusk_announces_the_event() -> void:
	var game := _game()
	await physics_frames(3)
	_player(game).health.setup(1.0e9)
	GameState.nights_survived = 1
	game.day_cycle.start_dusk()
	check(GameState.night_event != NightEvents.NONE, "night 2 has an event")
	check(game.hud.banner.modulate.a >= 0.0 and game.hud._banner_title.text.begins_with("TONIGHT:"), "a banner announces it")
	await physics_frames(12)
	game.hud._update_cycle_labels()
	check(game.hud.heat_label.text.begins_with(NightEvents.title(GameState.night_event)), "and the HUD keeps showing it")
	var d: Dictionary = GameState.to_dict()
	var ev: StringName = GameState.night_event
	GameState.new_game(2)
	GameState.from_dict(d)
	check_eq(GameState.night_event, ev, "saved")
	game.queue_free()
	GameState.new_game(1)


func test_supply_drops() -> void:
	var game := _game()
	await physics_frames(320)
	var sd: SupplyDrops = game.supply_drops
	check(sd.new_drop() == Vector2.INF, "no drop on day 1")
	GameState.day = 2
	var count_before: int = get_tree().get_nodes_in_group(&"zombies").size()
	var at: Vector2 = sd.new_drop()
	check(at != Vector2.INF, "day 2: a crate comes down")
	check(at.distance_to(Vector2(78.5, 71.5) * 16.0) >= SupplyDrops.MIN_FROM_SAFEHOUSE, "away from home")
	check(get_tree().get_nodes_in_group(&"zombies").size() >= count_before + 4, "guarded")
	check(sd.is_unopened() and sd.target().label == "DROP", "the yellow arrow points to it")
	check_eq(game.hud.drop_marker.provider.call().get("label", ""), "DROP", "the HUD's second arrow uses it")
	var items: Array = sd.crate.open_contents()
	check(items.size() >= 3, "good loot (%d stacks)" % items.size())
	check(not sd.is_unopened(), "arrow gone once opened")
	var saved: Dictionary = GameState.supply_drop.duplicate()
	check_eq(int(saved.day), 2, "saved with the day")
	GameState.day = 3
	var at3: Vector2 = sd.new_drop()
	check(at3 != Vector2.INF and str(GameState.supply_drop.id) == "drop_d3", "next morning, a new one")
	check(get_tree().get_nodes_in_group(&"loot_containers").filter(func(c): return String(c.container_id) == "drop_d2" and not c.is_queued_for_deletion()).is_empty(), "the old crate is gone")
	game.queue_free()
	GameState.new_game(1)
