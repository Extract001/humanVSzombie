extends "res://tests/test_case.gd"
## Slice 2 — Your Echo: your dead self carries your backpack until you put it down.


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func _die_with(game: Node, items: Dictionary) -> Player:
	var p := _player(game)
	p.global_position = Vector2(78.5, 58.5) * 16.0
	p.inventory.take_all()   # only what the test gives
	for id in items:
		p.inventory.add_item(id, items[id])
	p.health.take_damage(10000.0)
	return p


func test_echo_rises_with_your_backpack() -> void:
	var game := _game()
	await physics_frames(320)
	var p := _die_with(game, {&"food_can": 3, &"bolt_cutters": 1})
	await physics_frames(5)
	var id: StringName = GameState.backpack_ids()[0]
	check_eq(game.echo_manager.echoes().size(), 0, "not straight away")
	await physics_frames(int(EchoManager.RISE_DELAY * 60.0) + 10)
	var echoes: Array = game.echo_manager.echoes()
	check_eq(echoes.size(), 1, "your Echo rises")
	var z: Zombie = echoes[0]
	check(GameState.piles[id].echo, "it carries the backpack")
	check_eq(game.get_node("World/Piles").get_child_count(), 0, "no backpack lying on the ground")
	check(z.sprite.sprite_frames.has_animation(&"attack_down"), "it looks like you (player sprites, with an attack)")
	check(z.get_node("EchoTag").text == "YOUR ECHO", "labelled")
	check_eq(z.data.id, &"echo", "Echo stats")
	check(z.data.max_health > 100.0, "tougher than a Walker")
	game.queue_free()


func test_kill_echo_drops_backpack_where_it_falls() -> void:
	var game := _game()
	await physics_frames(320)
	_die_with(game, {&"food_can": 3, &"bolt_cutters": 1})
	await physics_frames(int(EchoManager.RISE_DELAY * 60.0) + 10)
	var z: Zombie = game.echo_manager.echoes()[0]
	var id: StringName = z.get_meta(&"pile_id")
	z.global_position += Vector2(40, 0)
	await physics_frames(40)   # the tracked position follows the Echo
	check(GameState.piles[id].position.distance_to(z.global_position) < 30.0, "the backpack's position follows the Echo")
	var score_before: int = GameState.score
	z.hurtbox.receive_hit(10000.0, _player(game))
	await physics_frames(3)
	check(not GameState.piles[id].echo, "backpack dropped")
	check(GameState.piles[id].position.distance_to(z.global_position) < 20.0, "where the Echo fell")
	var node: LootContainer = game.get_node("World/Piles").get_child(0)
	check(node != null and node.container_id == id, "a backpack you can search")
	var items: Array = GameState.get_contents(id)
	var total := 0
	for e in items:
		total += int(e.qty)
	check_eq(total, 4, "everything still in it (bolt cutters too)")
	check(GameState.score - score_before >= 100, "an Echo kill is worth 100")
	game.queue_free()


func test_no_echo_with_an_empty_bag() -> void:
	var game := _game()
	await physics_frames(320)
	_die_with(game, {})
	await physics_frames(int(EchoManager.RISE_DELAY * 60.0) + 10)
	check_eq(game.echo_manager.echoes().size(), 0, "nothing carried: nothing to carry off")
	game.queue_free()


func test_echo_is_saved_and_comes_back() -> void:
	var game := _game()
	await physics_frames(320)
	_die_with(game, {&"radio_part": 1})
	await physics_frames(int(EchoManager.RISE_DELAY * 60.0) + 40)
	var z: Zombie = game.echo_manager.echoes()[0]
	var where: Vector2 = z.global_position
	check(game.save_now("test"), "saved")
	game.queue_free()
	await physics_frames(2)
	GameState.new_game(9)
	check(SaveSystem.load_game().ok, "loaded")
	var game2: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game2)
	await physics_frames(3)
	var back: Array = game2.echo_manager.echoes()
	check_eq(back.size(), 1, "your Echo is still out there")
	check((back[0] as Zombie).global_position.distance_to(where) < 30.0, "where it was")
	check_eq(game2.get_node("World/Piles").get_child_count(), 0, "still carrying the backpack")
	game2.queue_free()
